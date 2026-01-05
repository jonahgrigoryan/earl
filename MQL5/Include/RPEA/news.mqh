#ifndef RPEA_NEWS_MQH
#define RPEA_NEWS_MQH
// news.mqh - News Calendar (MQL5+CSV) and Blocking Logic (M4 Task 01)
// References: m4-task01.md, finalspec.md §3.4

#include <RPEA/config.mqh>
#include <RPEA/logging.mqh>

//------------------------------------------------------------------------------
// Data Structures
//------------------------------------------------------------------------------

struct NewsEvent
{
   datetime timestamp_utc;
   string   symbol;       // Currency code (if is_currency) or Symbol
   string   impact;
   string   source;
   string   event_desc;
   int      prebuffer_min;
   int      postbuffer_min;
   datetime block_start;  // UTC block start (legacy compatibility)
   datetime block_end;    // UTC block end (legacy compatibility)
   datetime block_start_utc;
   datetime block_end_utc;
   bool     is_valid;
   bool     is_currency;  // true if symbol is a currency (e.g. "USD")
};

struct NewsCsvSchema
{
   int column_count;
   int idx_timestamp;
   int idx_symbol;
   int idx_impact;
   int idx_source;
   int idx_event;
   int idx_prebuffer;
   int idx_postbuffer;
};

struct NewsStabilizationState
{
   string   symbol;
   bool     in_stabilization;
   datetime stabilization_start;
   int      stable_bar_count;
   double   spread_p60;
   double   vol_p70;
   datetime last_bar_time;
   double   spread_history[];
   double   vol_history[];
   int      history_count;
   int      history_index;

   void Reset()
   {
      in_stabilization = false;
      stabilization_start = 0;
      stable_bar_count = 0;
      spread_p60 = 0.0;
      vol_p70 = 0.0;
      last_bar_time = 0;
   }
};

//------------------------------------------------------------------------------
// Global State
//------------------------------------------------------------------------------

static NewsEvent              g_news_events[];
static int                    g_news_event_count = 0;
static bool                   g_news_data_ok = false;
static int                    g_news_source = 0; // 0=NONE, 1=CALENDAR, 2=CSV
static datetime               g_news_last_load_time = 0;

static NewsStabilizationState g_news_stab_state[];
static int                    g_news_stab_count = 0;
static bool                   g_news_stab_enabled = true;

static bool                   g_news_prev_blocked[]; // Track transitions
static string                 g_news_missing_currency_symbols[];
static int                    g_news_missing_currency_count = 0;
static string                 g_news_select_fail_symbols[];
static int                    g_news_select_fail_count = 0;

// CSV Fallback State
static datetime               g_news_cached_mtime = 0;
static bool                   g_news_cache_valid = false;
static string                 g_news_cached_path = "";

// Test Overrides
static bool                   g_news_calendar_override_active = false;
static NewsEvent              g_news_calendar_override_events[];
static int                    g_news_calendar_override_count = 0;

// Legacy/Test globals
static string                 g_news_test_override_path = "";
static int                    g_news_test_override_max_age = -1;
static bool                   g_news_time_override_active = false;
static datetime               g_news_override_server_now = 0;
static datetime               g_news_override_utc_now = 0;
static int                    g_news_test_read_count = 0;

//------------------------------------------------------------------------------
// Time & Helper Utilities
//------------------------------------------------------------------------------

datetime News_GetNowServer()
{
   if(g_news_time_override_active) return g_news_override_server_now;
   return TimeCurrent();
}

datetime News_GetNowUtc()
{
   if(g_news_time_override_active) return g_news_override_utc_now;
   return TimeGMT();
}

string News_Trim(const string value)
{
   string copy = value;
   StringTrimLeft(copy);
   StringTrimRight(copy);
   return copy;
}

string News_NormalizeSymbol(const string symbol_raw)
{
   string value = News_Trim(symbol_raw);
   if(StringLen(value) == 0) return "";
   StringToUpper(value);
   int suffix_pos = StringFind(value, ".");
   if(suffix_pos >= 0)
      value = StringSubstr(value, 0, suffix_pos);
   // Removal of leading/trailing spaces already done by Trim
   return value;
}

void News_LogMissingCurrencyOnce(const string symbol)
{
   for(int i = 0; i < g_news_missing_currency_count; i++)
      if(g_news_missing_currency_symbols[i] == symbol) return;

   int idx = g_news_missing_currency_count;
   ArrayResize(g_news_missing_currency_symbols, idx + 1);
   g_news_missing_currency_symbols[idx] = symbol;
   g_news_missing_currency_count = idx + 1;
   LogAuditRow("NEWS_SYMBOL_CURRENCY_MISSING", symbol, LOG_WARN, 
               "Missing base/quote for currency blocking; fallback to symbol match", "{}");
}

void News_LogSymbolSelectFailOnce(const string symbol)
{
   for(int i = 0; i < g_news_select_fail_count; i++)
      if(g_news_select_fail_symbols[i] == symbol) return;

   int idx = g_news_select_fail_count;
   ArrayResize(g_news_select_fail_symbols, idx + 1);
   g_news_select_fail_symbols[idx] = symbol;
   g_news_select_fail_count = idx + 1;
   LogAuditRow("NEWS_SYMBOL_SELECT_FAIL", symbol, LOG_WARN, 
               "SymbolSelect failed; currency match may be incomplete", "{}");
}

bool News_EnsureSymbolSelected(const string symbol)
{
   if(SymbolSelect(symbol, true)) return true;
   News_LogSymbolSelectFailOnce(symbol);
   return false;
}

bool News_SymbolMatchesEvent(const string symbol, const NewsEvent &event)
{
   string normalized = News_NormalizeSymbol(symbol);
   if(event.is_currency)
   {
      string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
      string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
      if(StringLen(base) == 0 || StringLen(quote) == 0)
      {
         News_LogMissingCurrencyOnce(normalized);
         return (normalized == event.symbol);
      }
      return (base == event.symbol || quote == event.symbol);
   }
   return (normalized == event.symbol);
}

void News_ComputeBlockWindow(NewsEvent &event)
{
   int prebuffer_seconds = 0;
   int postbuffer_seconds = 0;
   if(event.prebuffer_min > 0) prebuffer_seconds = event.prebuffer_min * 60;
   if(event.postbuffer_min > 0) postbuffer_seconds = event.postbuffer_min * 60;
   
   const int global_seconds = (NewsBufferS > 0 ? NewsBufferS : 0);
   if(global_seconds > prebuffer_seconds) prebuffer_seconds = global_seconds;
   if(global_seconds > postbuffer_seconds) postbuffer_seconds = global_seconds;
   
   event.block_start_utc = event.timestamp_utc - prebuffer_seconds;
   event.block_end_utc = event.timestamp_utc + postbuffer_seconds;
   event.block_start = event.block_start_utc;
   event.block_end = event.block_end_utc;
}

//------------------------------------------------------------------------------
// Fallback CSV Loader
//------------------------------------------------------------------------------
// Reuses logic from previous implementation but adapted to fills g_news_events
// Note: CSV events set is_currency=false unless we want to parse it?
// Requirement says: CSV schema remains timestamp,symbol,...
// We will treat CSV symbols as literal symbols unless length=3? 
// Safer to stick to old behavior: normalize symbol, is_currency=false.

int News_FindColumn(string &columns[], const string target)
{
    string expected = target; StringToLower(expected);
    for(int i=0; i<ArraySize(columns); i++) {
        string col = News_Trim(columns[i]); StringToLower(col);
        if(col == expected) return i;
    }
    return -1;
}

bool News_ValidateCsvSchema(string &columns[], NewsCsvSchema &schema)
{
   schema.idx_timestamp = News_FindColumn(columns, "timestamp_utc");
   schema.idx_symbol = News_FindColumn(columns, "symbol");
   schema.idx_impact = News_FindColumn(columns, "impact");
   schema.idx_source = News_FindColumn(columns, "source");
   schema.idx_event = News_FindColumn(columns, "event");
   schema.idx_prebuffer = News_FindColumn(columns, "prebuffer_min");
   schema.idx_postbuffer = News_FindColumn(columns, "postbuffer_min");

   return (schema.idx_timestamp >= 0 &&
           schema.idx_symbol >= 0 &&
           schema.idx_impact >= 0 &&
           schema.idx_source >= 0 &&
           schema.idx_event >= 0 &&
           schema.idx_prebuffer >= 0 &&
           schema.idx_postbuffer >= 0);
}

bool News_LoadCsvFallbackInternal()
{
   string path = (StringLen(g_news_test_override_path) > 0) ? g_news_test_override_path : NewsCSVPath;
   if(StringLen(path) == 0) path = DEFAULT_NewsCSVPath;

   int handle = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE) return false;
   
   // Parse Header
   if(FileIsEnding(handle)) { FileClose(handle); return false; }
   string header = News_Trim(FileReadString(handle));
   string cols[];
   if(StringSplit(header, ',', cols) < 7) { FileClose(handle); return false; }
   
   NewsCsvSchema schema;

   if(!News_ValidateCsvSchema(cols, schema)) {
       FileClose(handle);
       return false;
   }

   NewsEvent collector[];
   int count = 0;
   
   while(!FileIsEnding(handle))
   {
       string line = FileReadString(handle);
       string trimmed = News_Trim(line);
       if(trimmed == "" || StringGetCharacter(trimmed, 0) == '#') continue;
       
       string parts[];
       if(StringSplit(trimmed, ',', parts) < 7) continue;
       
       // Parse timestamp (simplified for brevity, reuse logic if needed)
       string ts_str = parts[schema.idx_timestamp];
       StringReplace(ts_str, "T", " ");
       StringReplace(ts_str, "Z", "");
       datetime dt = StringToTime(ts_str);
       if(dt <= 0) continue;
       
       // Parse Impact
       string imp = News_Trim(parts[schema.idx_impact]);
       StringToUpper(imp);
       if(StringLen(imp) == 0) continue;
       string impact = imp;
       if(StringFind(imp, "HIGH") >= 0)
          impact = "HIGH";
       else if(StringFind(imp, "MEDIUM") >= 0)
          impact = "MEDIUM";
       else if(StringFind(imp, "LOW") >= 0)
          impact = "LOW";
       
       // Parse Buffers
       int pre = (int)StringToInteger(parts[schema.idx_prebuffer]);
       int post = (int)StringToInteger(parts[schema.idx_postbuffer]);
       if(pre < 0) pre = 0;
       if(post < 0) post = 0;
       
       // Parse Symbols
       string sym_field = parts[schema.idx_symbol];
       string tokens[];
       StringSplit(sym_field, ';', tokens);
       
       for(int i=0; i<ArraySize(tokens); i++) {
           string exact_sym = News_NormalizeSymbol(tokens[i]);
           if(exact_sym == "") continue;
           
           if(ArrayResize(collector, count + 1) < 0) break;
           collector[count].timestamp_utc = dt;
           collector[count].impact = impact;
           collector[count].symbol = exact_sym;
           collector[count].is_currency = false; // CSV symbols treated as literal symbols
           collector[count].prebuffer_min = pre;
           collector[count].postbuffer_min = post;
           collector[count].source = "CSV";
           collector[count].event_desc = "CSV Event";
           collector[count].is_valid = true;
           News_ComputeBlockWindow(collector[count]);
           count++;
       }
   }
   FileClose(handle);
   
   if(count > 0) {
       ArrayResize(g_news_events, count);
       for(int i=0; i<count; i++) g_news_events[i] = collector[i];
       g_news_event_count = count;
       return true;
   }
   return false;
}

bool News_GetFileMTime(const string path, datetime &mtime)
{
   int handle = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;
   mtime = (datetime)FileGetInteger(handle, FILE_MODIFY_DATE);
   FileClose(handle);
   return (mtime > 0);
}

int News_GetCsvMaxAgeHours()
{
   if(g_news_test_override_max_age >= 0)
      return g_news_test_override_max_age;
   return NewsCSVMaxAgeHours;
}

bool News_IsCsvFresh(const datetime mtime, const int max_age_hours)
{
   if(max_age_hours <= 0)
      return true;
   datetime now = News_GetNowServer();
   if(now <= 0 || mtime <= 0)
      return true;
   double age_hours = (double)(now - mtime) / 3600.0;
   return (age_hours <= (double)max_age_hours);
}

bool News_LoadCsvFallback()
{
   string path = (StringLen(g_news_test_override_path) > 0) ? g_news_test_override_path : NewsCSVPath;
   if(StringLen(path) == 0) path = DEFAULT_NewsCSVPath;

   datetime mtime = 0;
   if(!News_GetFileMTime(path, mtime))
   {
      News_ClearCache();
      g_news_cache_valid = false;
      g_news_cached_path = path;
      g_news_cached_mtime = 0;
      return false;
   }

   int max_age = News_GetCsvMaxAgeHours();
   if(!News_IsCsvFresh(mtime, max_age))
   {
      News_ClearCache();
      g_news_cache_valid = false;
      g_news_cached_path = path;
      g_news_cached_mtime = mtime;
      return false;
   }

   g_news_test_read_count++;
   bool ok = News_LoadCsvFallbackInternal();
   if(!ok)
   {
      News_ClearCache();
      g_news_cache_valid = false;
      g_news_cached_path = path;
      g_news_cached_mtime = mtime;
      return false;
   }

   g_news_cached_mtime = mtime;
   g_news_cached_path = path;
   g_news_cache_valid = true;
   g_news_data_ok = true;
   g_news_source = 2;
   g_news_last_load_time = News_GetNowServer();
   return true;
}

bool News_ReloadIfChanged()
{
   string path = (StringLen(g_news_test_override_path) > 0) ? g_news_test_override_path : NewsCSVPath;
   if(StringLen(path) == 0) path = DEFAULT_NewsCSVPath;

   datetime mtime = 0;
   if(!News_GetFileMTime(path, mtime))
   {
      News_ClearCache();
      g_news_cache_valid = false;
      g_news_cached_mtime = 0;
      g_news_cached_path = path;
      return false;
   }

   int max_age = News_GetCsvMaxAgeHours();
   if(g_news_cache_valid && g_news_cached_mtime == mtime && g_news_cached_path == path)
   {
      if(News_IsCsvFresh(mtime, max_age))
         return true;
      News_ClearCache();
      g_news_cache_valid = false;
      return false;
   }

   return News_LoadCsvFallback();
}

bool News_GetEventsForSymbol(const string symbol, NewsEvent &out[])
{
   ArrayResize(out, 0);
   if(!News_ReloadIfChanged())
      return false;

   int count = 0;
   for(int i = 0; i < g_news_event_count; i++)
   {
      if(!g_news_events[i].is_valid)
         continue;
      if(!News_SymbolMatchesEvent(symbol, g_news_events[i]))
         continue;
      int idx = count;
      ArrayResize(out, idx + 1);
      out[idx] = g_news_events[i];
      count++;
   }
   return (count > 0);
}

//------------------------------------------------------------------------------
// Loader Orchestration
//------------------------------------------------------------------------------

bool News_LoadCalendarEvents(const datetime from_utc, const datetime to_utc)
{
#ifdef RPEA_TEST_RUNNER
   if(g_news_calendar_override_active) {
      ArrayResize(g_news_events, g_news_calendar_override_count);
      for(int i=0; i<g_news_calendar_override_count; i++)
         g_news_events[i] = g_news_calendar_override_events[i];
      g_news_event_count = g_news_calendar_override_count;
      return (g_news_calendar_override_count > 0);
   }
   // MQL5 Calendar not available in Strategy Tester without data
   // But we can check if running in EA mode
#endif

   MqlCalendarValue values[];
   // Reset last error
   ResetLastError();
   
   // Load all HIGH impact events in range
   // Using empty country/currency to get all
   if(CalendarValueHistory(values, from_utc, to_utc, NULL, NULL))
   {
       NewsEvent collector[];
       int count = 0;
       
       for(int i=0; i<ArraySize(values); i++)
       {
           MqlCalendarEvent evt;
           if(!CalendarEventById(values[i].event_id, evt)) continue;
           
           if(evt.importance != CALENDAR_IMPORTANCE_HIGH) continue;
           
           if(ArrayResize(collector, count + 1) < 0) break;

           MqlCalendarCountry country;
           string currency = "";
           if(CalendarCountryById(evt.country_id, country))
              currency = country.currency;
           if(StringLen(currency) == 0)
              continue;

           collector[count].timestamp_utc = values[i].time; // is this UTC? Spec implies it usually is
           collector[count].symbol = currency;
           collector[count].is_currency = true;
           collector[count].impact = "HIGH";
           collector[count].source = "CAL";
           collector[count].event_desc = StringFormat("Calendar event %I64d", (long)evt.id);
           collector[count].prebuffer_min = 0; // Default, will use global
           collector[count].postbuffer_min = 0;
           collector[count].is_valid = true;
           News_ComputeBlockWindow(collector[count]);
           count++;
       }
       
       if(count > 0) {
           ArrayResize(g_news_events, count);
           for(int i=0; i<count; i++) g_news_events[i] = collector[i];
           g_news_event_count = count;
           return true; 
       }
   }
   return false;
}

bool News_LoadEvents()
{
   datetime now = News_GetNowServer();
   // Cache for 60 seconds
   if(g_news_data_ok && (now - g_news_last_load_time < 60) && !g_news_calendar_override_active)
      return g_news_data_ok;

   const datetime now_utc = News_GetNowUtc();
   const datetime from_utc = now_utc - (NewsCalendarLookbackHours * 3600);
   const datetime to_utc = now_utc + (NewsCalendarLookaheadHours * 3600);
   
   // Try Calendar First
   if(News_LoadCalendarEvents(from_utc, to_utc)) {
       g_news_data_ok = true;
       g_news_source = 1;
       g_news_last_load_time = now;
       return true;
   }
   
   // Fallback to CSV
   if(News_LoadCsvFallback()) {
       g_news_data_ok = true;
       g_news_source = 2;
       g_news_last_load_time = now;
       LogAuditRow("NEWS_SOURCE_FALLBACK", "News", LOG_INFO, "Calendar unavailable, using CSV", "{}");
       return true;
   }
   
   News_ClearCache();
   g_news_data_ok = false;
   g_news_source = 0;
   g_news_last_load_time = now;
   LogAuditRow("NEWS_DATA_UNAVAILABLE", "News", LOG_WARN, "No calendar or CSV data", "{}");
   return false;
}

//------------------------------------------------------------------------------
// Stabilization Logic
//------------------------------------------------------------------------------

void News_InitStabilization(const string &symbols[], const int count)
{
    ArrayResize(g_news_stab_state, count);
    ArrayResize(g_news_prev_blocked, count);
    g_news_stab_count = count;
    for(int i=0; i<count; i++) {
        g_news_stab_state[i].symbol = symbols[i];
        g_news_stab_state[i].Reset();
        g_news_prev_blocked[i] = false;
    }
}

int News_FindStabIndex(const string symbol)
{
    string normalized = News_NormalizeSymbol(symbol);
    for(int i=0; i<g_news_stab_count; i++) {
        string s = News_NormalizeSymbol(g_news_stab_state[i].symbol);
        if(s == normalized) return i;
    }
    return -1;
}

double News_CalcPercentile(const double &values[], const int count, const double pct)
{
    if(count <= 0) return 0.0;
    double sorted[];
    ArrayResize(sorted, count);
    ArrayCopy(sorted, values, 0, 0, count);
    ArraySort(sorted);
    int idx = (int)MathFloor((pct/100.0) * (count-1));
    idx = MathMax(0, MathMin(idx, count-1));
    return sorted[idx];
}

void News_UpdateStabilizationThresholds(const int idx)
{
    if(g_news_stab_state[idx].history_count <= 0) return;
    g_news_stab_state[idx].spread_p60 = News_CalcPercentile(g_news_stab_state[idx].spread_history,
                                                           g_news_stab_state[idx].history_count,
                                                           SpreadStabilizationPct);
    g_news_stab_state[idx].vol_p70 = News_CalcPercentile(g_news_stab_state[idx].vol_history,
                                                        g_news_stab_state[idx].history_count,
                                                        VolatilityStabilizationPct);
}

void News_RecordM1Metrics(const int idx, const string symbol, const datetime bar_time)
{
    // M1 Spread = SYMBOL_SPREAD (int points) * POINT
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double spread_raw = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    double spread = spread_raw * point;
    
    // M1 Vol = High - Low of previous bar (closed bar)
    double high = iHigh(symbol, PERIOD_M1, 1);
    double low = iLow(symbol, PERIOD_M1, 1);
    double vol = high - low;
    
    if(high == 0 || low == 0) return; // Data not ready
    
    if(ArraySize(g_news_stab_state[idx].spread_history) < StabilizationLookbackBars) {
        ArrayResize(g_news_stab_state[idx].spread_history, StabilizationLookbackBars);
        ArrayResize(g_news_stab_state[idx].vol_history, StabilizationLookbackBars);
    }

    g_news_stab_state[idx].spread_history[g_news_stab_state[idx].history_index] = spread;
    g_news_stab_state[idx].vol_history[g_news_stab_state[idx].history_index] = vol;
    g_news_stab_state[idx].history_index = (g_news_stab_state[idx].history_index + 1) % StabilizationLookbackBars;
    g_news_stab_state[idx].history_count = MathMin(g_news_stab_state[idx].history_count + 1,
                                                   StabilizationLookbackBars);
    
    News_UpdateStabilizationThresholds(idx);
}

void News_OnM1Bar(const string symbol, const datetime bar_time)
{
    int idx = News_FindStabIndex(symbol);
    if(idx < 0) return;
    
    if(bar_time <= g_news_stab_state[idx].last_bar_time) return;
    g_news_stab_state[idx].last_bar_time = bar_time;
    
    News_RecordM1Metrics(idx, symbol, bar_time);
    
    if(!g_news_stab_state[idx].in_stabilization) return;
    
    // Timeout Check
    datetime now = News_GetNowServer();
    int elapsed_min = (int)((now - g_news_stab_state[idx].stabilization_start)/60);
    if(elapsed_min >= StabilizationTimeoutMin) {
        LogAuditRow("NEWS_STABILIZATION_TIMEOUT", symbol, 0, StringFormat("Timeout after %d min", elapsed_min), "{}");
        g_news_stab_state[idx].Reset();
        return;
    }
    
    // Metrics Check (Current bar close metrics)
    // Actually we check CURRENT market conditions or CLOSED bar conditions?
    // "Stabilization requires StabilizationBars consecutive M1 bars... computed from rolling per-bar history"
    // Usually implies last closed bar vs threshold.
    // Let's check the just-closed bar metrics against thresholds.
    // The just-closed bar metrics were recorded in RecordM1Metrics as prev bar.
    // We can use the latest history values.
    
    int last_h_idx = (g_news_stab_state[idx].history_index - 1 + StabilizationLookbackBars) % StabilizationLookbackBars;
    double current_spread = g_news_stab_state[idx].spread_history[last_h_idx];
    double current_vol = g_news_stab_state[idx].vol_history[last_h_idx];
    
    bool spread_ok = (current_spread <= g_news_stab_state[idx].spread_p60);
    bool vol_ok = (current_vol <= g_news_stab_state[idx].vol_p70);
    
    string metrics = StringFormat("{\"spread\":%.5f,\"spread_p60\":%.5f,\"vol\":%.5f,\"vol_p70\":%.5f,\"bars\":%d}",
                                  current_spread,
                                  g_news_stab_state[idx].spread_p60,
                                  current_vol,
                                  g_news_stab_state[idx].vol_p70,
                                  g_news_stab_state[idx].stable_bar_count);

    if(spread_ok && vol_ok) {
        g_news_stab_state[idx].stable_bar_count++;
        LogAuditRow("NEWS_STABILIZING", symbol, 1,
                    StringFormat("Bar %d/%d stable", g_news_stab_state[idx].stable_bar_count, StabilizationBars),
                    metrics);
        if(g_news_stab_state[idx].stable_bar_count >= StabilizationBars) {
            LogAuditRow("NEWS_STABLE", symbol, 1, "Stabilization complete", metrics);
            g_news_stab_state[idx].Reset();
        }
    } else {
        g_news_stab_state[idx].stable_bar_count = 0;
        LogAuditRow("NEWS_STABILIZING", symbol, 0, StringFormat("Reset: spread_ok=%d vol_ok=%d", spread_ok, vol_ok), metrics);
    }
}

bool News_IsStabilizing(const string symbol)
{
    if(!g_news_stab_enabled) return false;
    string normalized = News_NormalizeSymbol(symbol);
    if(normalized == "XAUEUR")
       return (News_IsStabilizing("XAUUSD") || News_IsStabilizing("EURUSD"));

    int idx = News_FindStabIndex(symbol);
    if(idx < 0) return false;
    return g_news_stab_state[idx].in_stabilization;
}

void News_EnterStabilization(const string symbol)
{
    int idx = News_FindStabIndex(symbol);
    if(idx < 0) return;
    
    g_news_stab_state[idx].in_stabilization = true;
    g_news_stab_state[idx].stabilization_start = News_GetNowServer();
    g_news_stab_state[idx].stable_bar_count = 0;
    
    // Compute thresholds immediately
    News_UpdateStabilizationThresholds(idx);
    
    LogAuditRow("NEWS_BLOCK_END", symbol, 1, "Entering stabilization phase",
                StringFormat("{\"spread_p60\":%.5f,\"vol_p70\":%.5f}",
                             g_news_stab_state[idx].spread_p60,
                             g_news_stab_state[idx].vol_p70));
}

void News_OnTimer()
{
   for(int i = 0; i < g_news_stab_count; i++)
   {
      string symbol = g_news_stab_state[i].symbol;
      News_UpdateBlockState(symbol);
      
      // Use SeriesInfoInteger for potentially faster caching or stick to iTime
      datetime bar_time = iTime(symbol, PERIOD_M1, 0);
      if(bar_time > 0)
         News_OnM1Bar(symbol, bar_time);
   }
}

//------------------------------------------------------------------------------
// Blocking Gates
//------------------------------------------------------------------------------

bool News_IsMasterMode()
{
    if(NewsAccountMode == 1) return true;
    if(NewsAccountMode == 2) return false;
    long trade_mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    return (trade_mode == ACCOUNT_TRADE_MODE_REAL && balance >= 25000.0);
}

// Internal Helper that assumes data is loaded
bool News_IsBlocked_Internal(const string symbol)
{
    const datetime now_utc = News_GetNowUtc();
    for(int i=0; i<g_news_event_count; i++) {
        if(!g_news_events[i].is_valid) continue;
        if(g_news_events[i].impact != "HIGH") continue;
        if(now_utc < g_news_events[i].block_start_utc || now_utc > g_news_events[i].block_end_utc) continue;
        if(News_SymbolMatchesEvent(symbol, g_news_events[i])) return true;
    }
    return false;
}

void News_UpdateBlockState(const string symbol)
{
    // Need data to check blocking
    if(!News_LoadEvents()) return; 

    int idx = News_FindStabIndex(symbol);
    if(idx < 0) return; // Not tracked

    if(g_news_stab_state[idx].in_stabilization)
    {
        datetime now = News_GetNowServer();
        int elapsed_min = (int)((now - g_news_stab_state[idx].stabilization_start)/60);
        if(elapsed_min >= StabilizationTimeoutMin)
        {
            LogAuditRow("NEWS_STABILIZATION_TIMEOUT", symbol, 0,
                        StringFormat("Timeout after %d min", elapsed_min), "{}");
            g_news_stab_state[idx].Reset();
        }
    }
    
    bool was_blocked = g_news_prev_blocked[idx];
    bool now_blocked = News_IsBlocked_Internal(symbol);
    
    if(!was_blocked && now_blocked) {
        LogAuditRow("NEWS_BLOCK_START", symbol, 1, "News window active", "{}");
        g_news_stab_state[idx].Reset();
    }
    
    if(was_blocked && !now_blocked) {
        News_EnterStabilization(symbol);
    }
    
    g_news_prev_blocked[idx] = now_blocked;
}

bool News_IsBlocked(const string symbol)
{
    if(!News_LoadEvents()) return false;
    return News_IsBlocked_Internal(symbol);
}

bool News_IsEntryBlocked(const string symbol)
{
    // Load events first
    bool data_ok = News_LoadEvents();
    if(!data_ok) {
        // Fail-closed for Master, Fail-open for Eval
        return News_IsMasterMode(); 
    }
    
    if(News_IsBlocked_Internal(symbol)) return true;
    if(News_IsStabilizing(symbol)) return true;
    
    return false;
}

bool News_IsModifyBlocked(const string symbol)
{
    // Load events first
    bool data_ok = News_LoadEvents();
    if(!data_ok) {
        return News_IsMasterMode();
    }
    
    // Mods only blocked during window, NOT during stabilization
    return News_IsBlocked_Internal(symbol);
}

string News_GetWindowStateDetailed(const string symbol, const bool is_protective)
{
    News_LoadEvents(); // Ensure data freshness
    if(!g_news_data_ok && News_IsMasterMode()) return "DATA_UNAVAILABLE_BLOCK";
    
    if(News_IsBlocked_Internal(symbol)) return (is_protective ? "PROTECTIVE_ONLY" : "BLOCKED");
    if(News_IsStabilizing(symbol)) return "STABILIZING";
    
    return "CLEAR";
}

string News_GetWindowState(const string symbol, const bool is_protective)
{
    return News_GetWindowStateDetailed(symbol, is_protective);
}

//------------------------------------------------------------------------------
// Test Hooks
//------------------------------------------------------------------------------

void News_Test_SetCalendarEvents(const NewsEvent &events[], const int count)
{
   g_news_calendar_override_active = true;
   g_news_calendar_override_count = count;
   ArrayResize(g_news_calendar_override_events, count);
   for(int i=0; i<count; i++) g_news_calendar_override_events[i] = events[i];
   g_news_data_ok = true; 
}

void News_Test_ClearCalendarEvents()
{
   g_news_calendar_override_active = false;
   g_news_calendar_override_count = 0;
   ArrayResize(g_news_calendar_override_events, 0);
   g_news_data_ok = false;
}

// Legacy Override accessors to maintain compat if needed
void News_ForceReload()
{
   g_news_last_load_time = 0;
   g_news_cache_valid = false;
   g_news_cached_mtime = 0;
   g_news_cached_path = "";
}

void News_ClearCache()
{
   g_news_data_ok = false;
   g_news_event_count = 0;
   ArrayResize(g_news_events, 0);
   g_news_cache_valid = false;
}

string News_GetConfiguredCsvPath() { return DEFAULT_NewsCSVPath; }
int News_GetConfiguredMaxAgeHours() { return DEFAULT_NewsCSVMaxAgeHours; }

// Test Setters
void News_Test_SetOverridePath(const string path) { g_news_test_override_path = path; News_ForceReload(); }
void News_Test_SetOverrideMaxAgeHours(const int hours) { g_news_test_override_max_age = hours; News_ForceReload(); }
void News_Test_SetCurrentTimes(const datetime server_now, const datetime utc_now) {
    g_news_time_override_active = true; g_news_override_server_now = server_now; g_news_override_utc_now = utc_now;
}
void News_Test_ClearCurrentTimeOverride() { g_news_time_override_active=false; }
void News_Test_ClearOverrides() { 
    News_Test_ClearCalendarEvents(); 
    News_Test_ClearCurrentTimeOverride();
    g_news_test_override_path=""; 
    g_news_test_override_max_age=-1;
    News_ForceReload(); 
}
int News_Test_GetReadCount() { return g_news_test_read_count; }
void News_Test_ResetReadCount() { g_news_test_read_count=0; }
void News_Test_Clear()
{
   News_Test_ClearOverrides();
   News_ClearCache();
   ArrayResize(g_news_stab_state, 0);
   ArrayResize(g_news_prev_blocked, 0);
   g_news_stab_count = 0;
}

int News_BuildStabilizationSymbols(const string &symbols[], const int count, string &out_symbols[])
{
   ArrayResize(out_symbols, 0);
   bool has_xaueur = false;
   bool has_xauusd = false;
   bool has_eurusd = false;
   for(int i = 0; i < count; i++)
   {
      string sym = News_NormalizeSymbol(symbols[i]);
      if(sym == "") continue;
      int idx = ArraySize(out_symbols);
      ArrayResize(out_symbols, idx + 1);
      out_symbols[idx] = sym;
      if(sym == "XAUEUR") has_xaueur = true;
      if(sym == "XAUUSD") has_xauusd = true;
      if(sym == "EURUSD") has_eurusd = true;
   }
   if(has_xaueur && !has_xauusd) {
      int idx = ArraySize(out_symbols);
      ArrayResize(out_symbols, idx + 1);
      out_symbols[idx] = "XAUUSD";
   }
   if(has_xaueur && !has_eurusd) {
      int idx = ArraySize(out_symbols);
      ArrayResize(out_symbols, idx + 1);
      out_symbols[idx] = "EURUSD";
   }
   return ArraySize(out_symbols);
}

#endif // RPEA_NEWS_MQH
