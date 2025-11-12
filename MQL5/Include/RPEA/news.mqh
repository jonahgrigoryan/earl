#ifndef RPEA_NEWS_MQH
#define RPEA_NEWS_MQH
// news.mqh - News CSV fallback loader and blocking helpers (M3 Task 10)
// References: .kiro/specs/rpea-m3/tasks.md §10, requirements.md §10

#include <RPEA/config.mqh>

struct NewsEvent
{
   datetime timestamp_utc;
   string   symbol;
   string   impact;
   string   source;
   string   event_desc;
   int      prebuffer_min;
   int      postbuffer_min;
   datetime block_start_utc;
   datetime block_end_utc;
   bool     is_valid;
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

static NewsEvent g_news_events[];
static int       g_news_event_count = 0;
static datetime  g_news_cached_mtime = 0;
static bool      g_news_cache_valid = false;
static string    g_news_cached_path = "";
static bool      g_news_force_reload = false;
static string    g_news_test_override_path = "";
static int       g_news_test_override_max_age = -1;
static bool      g_news_time_override_active = false;
static datetime  g_news_override_server_now = 0;
static datetime  g_news_override_utc_now = 0;
static int       g_news_test_read_count = 0;

//------------------------------------------------------------------------------
// Helper utilities
//------------------------------------------------------------------------------

string News_Trim(const string value)
{
   string copy = value;
   StringTrimLeft(copy);
   StringTrimRight(copy);
   return copy;
}

void News_ClearCache()
{
   ArrayResize(g_news_events, 0);
   g_news_event_count = 0;
   g_news_cache_valid = false;
   g_news_cached_mtime = 0;
   g_news_cached_path = "";
}

string News_GetConfiguredCsvPath()
{
   if(StringLen(g_news_test_override_path) > 0)
      return g_news_test_override_path;
   if(StringLen(NewsCSVPath) > 0)
      return NewsCSVPath;
   return DEFAULT_NewsCSVPath;
}

int News_GetConfiguredMaxAgeHours()
{
   if(g_news_test_override_max_age >= 0)
      return g_news_test_override_max_age;
   if(NewsCSVMaxAgeHours > 0)
      return NewsCSVMaxAgeHours;
   if(NewsCSVMaxAgeHours == 0)
      return 0;
   return DEFAULT_NewsCSVMaxAgeHours;
}

datetime News_GetNowServer()
{
   if(g_news_time_override_active)
      return g_news_override_server_now;
   return TimeCurrent();
}

datetime News_GetNowUtc()
{
   if(g_news_time_override_active)
      return g_news_override_utc_now;
   return TimeGMT();
}

bool News_GetFileMTime(const string path, datetime &out_mtime)
{
   int handle = FileOpen(path, FILE_READ|FILE_BIN);
   if(handle == INVALID_HANDLE)
      return false;
   out_mtime = (datetime)FileGetInteger(handle, FILE_MODIFY_DATE);
   FileClose(handle);
   return (out_mtime > 0);
}

double News_CalcFileAgeHours(const datetime mtime, const datetime now_value)
{
   if(mtime <= 0 || now_value <= 0 || now_value < mtime)
      return 0.0;
   return (double)(now_value - mtime) / 3600.0;
}

bool News_IsCsvFresh(const datetime mtime, const int max_age_hours)
{
   if(max_age_hours <= 0)
      return true;
   const datetime now_value = News_GetNowServer();
   const double age_hours = News_CalcFileAgeHours(mtime, now_value);
   return (age_hours <= (double)max_age_hours + 1e-6);
}

string News_NormalizeImpact(const string impact_raw)
{
   string value = News_Trim(impact_raw);
   StringToUpper(value);
   if(StringFind(value, "HIGH") == 0)
      return "HIGH";
   if(StringFind(value, "MED") == 0)
      return "MEDIUM";
   if(StringFind(value, "LOW") == 0)
      return "LOW";
   return "";
}

string News_NormalizeSymbol(const string symbol_raw)
{
   string value = News_Trim(symbol_raw);
   if(StringLen(value) == 0)
      return "";
   StringToUpper(value);
   int suffix_pos = StringFind(value, ".");
   if(suffix_pos >= 0)
      value = StringSubstr(value, 0, suffix_pos);
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
}

datetime News_EncodeUtc(const MqlDateTime &dt)
{
   if(dt.year < 1970)
      return 0;
   int a = (14 - dt.mon) / 12;
   int y = dt.year + 4800 - a;
   int m = dt.mon + 12 * a - 3;
   int julian = dt.day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045;
   long days = (long)julian - 2440588;
   long seconds = (long)dt.hour * 3600 + (long)dt.min * 60 + (long)dt.sec;
   return (datetime)(days * 86400 + seconds);
}

int News_SplitSymbols(const string field, string &tokens[])
{
   ArrayResize(tokens, 0);
   string buffer = "";
   const int len = StringLen(field);
   for(int i = 0; i < len; i++)
   {
      const string ch = StringSubstr(field, i, 1);
      if(ch == ";" || ch == "," || ch == "|" || ch == " " || ch == "/")
      {
         string token = News_NormalizeSymbol(buffer);
         if(StringLen(token) > 0)
         {
            const int idx = ArraySize(tokens);
            ArrayResize(tokens, idx + 1);
            tokens[idx] = token;
         }
         buffer = "";
         continue;
      }
      buffer += ch;
   }
   string trailing = News_NormalizeSymbol(buffer);
   if(StringLen(trailing) > 0)
   {
      const int idx = ArraySize(tokens);
      ArrayResize(tokens, idx + 1);
      tokens[idx] = trailing;
   }
   return ArraySize(tokens);
}

datetime News_ParseTimestamp(const string timestamp_str, bool &ok)
{
   ok = false;
   string value = News_Trim(timestamp_str);
   if(StringLen(value) < 20)
      return 0;
   string clean = value;
   if(StringGetCharacter(clean, (int)StringLen(clean) - 1) == 'Z')
      clean = StringSubstr(clean, 0, StringLen(clean) - 1);
   int split_pos = StringFind(clean, "T");
   if(split_pos < 0)
      split_pos = StringFind(clean, " ");
   if(split_pos < 0)
      return 0;
   string date_part = StringSubstr(clean, 0, split_pos);
   string time_part = StringSubstr(clean, split_pos + 1);
   MqlDateTime dt;
   ZeroMemory(dt);
   if(StringLen(date_part) != 10 || StringLen(time_part) < 8)
      return 0;
   dt.year  = (int)StringToInteger(StringSubstr(date_part, 0, 4));
   dt.mon   = (int)StringToInteger(StringSubstr(date_part, 5, 2));
   dt.day   = (int)StringToInteger(StringSubstr(date_part, 8, 2));
   dt.hour  = (int)StringToInteger(StringSubstr(time_part, 0, 2));
   dt.min   = (int)StringToInteger(StringSubstr(time_part, 3, 2));
   dt.sec   = (int)StringToInteger(StringSubstr(time_part, 6, 2));
   if(dt.year < 1970 || dt.mon < 1 || dt.day < 1)
      return 0;
   datetime utc_time = News_EncodeUtc(dt);
   if(utc_time <= 0)
      return 0;
   ok = true;
   return utc_time;
}

void News_ComputeBlockWindow(NewsEvent &event)
{
   int prebuffer_seconds = 0;
   int postbuffer_seconds = 0;
   if(event.prebuffer_min > 0)
      prebuffer_seconds = event.prebuffer_min * 60;
   if(event.postbuffer_min > 0)
      postbuffer_seconds = event.postbuffer_min * 60;
   const int global_seconds = (NewsBufferS > 0 ? NewsBufferS : 0);
   if(global_seconds > prebuffer_seconds)
      prebuffer_seconds = global_seconds;
   if(global_seconds > postbuffer_seconds)
      postbuffer_seconds = global_seconds;
   event.block_start_utc = event.timestamp_utc - prebuffer_seconds;
   event.block_end_utc = event.timestamp_utc + postbuffer_seconds;
}

int News_FindColumn(string &columns[], const string target)
{
   string expected = target;
   StringToLower(expected);
   for(int i = 0; i < ArraySize(columns); i++)
   {
      string col = News_Trim(columns[i]);
      StringToLower(col);
      if(col == expected)
         return i;
   }
   return -1;
}

bool News_ParseHeader(const string header_line, NewsCsvSchema &schema)
{
   string columns[];
   const int count = StringSplit(header_line, ',', columns);
   if(count < 7)
      return false;
   schema.column_count = count;
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

bool News_ProcessCsvLine(const string line,
                         const NewsCsvSchema &schema,
                         NewsEvent &collector[],
                         int &collector_count,
                         string &error_msg)
{
   string trimmed = News_Trim(line);
   if(trimmed == "" || StringGetCharacter(trimmed, 0) == '#')
      return true;

   string columns[];
   const int count = StringSplit(trimmed, ',', columns);
   if(count < schema.column_count)
   {
      error_msg = "insufficient columns";
      return false;
   }

   bool timestamp_ok = false;
   datetime event_time = News_ParseTimestamp(columns[schema.idx_timestamp], timestamp_ok);
   if(!timestamp_ok)
   {
      error_msg = "invalid timestamp";
      return false;
   }

   const string impact = News_NormalizeImpact(columns[schema.idx_impact]);
   if(impact == "")
   {
      error_msg = "unknown impact";
      return false;
   }

   string symbol_tokens[];
   const int symbol_count = News_SplitSymbols(columns[schema.idx_symbol], symbol_tokens);
   if(symbol_count <= 0)
   {
      error_msg = "symbol column empty";
      return false;
   }

   bool pre_ok = true;
   bool post_ok = true;
   const double prebuffer_value = StringToDouble(News_Trim(columns[schema.idx_prebuffer]));
   const double postbuffer_value = StringToDouble(News_Trim(columns[schema.idx_postbuffer]));
   pre_ok = MathIsValidNumber(prebuffer_value);
   post_ok = MathIsValidNumber(postbuffer_value);
   if(!pre_ok || !post_ok)
   {
      error_msg = "invalid buffer minutes";
      return false;
   }

   NewsEvent base;
   base.timestamp_utc = event_time;
   base.impact = impact;
   base.source = News_Trim(columns[schema.idx_source]);
   base.event_desc = News_Trim(columns[schema.idx_event]);
   base.prebuffer_min = (int)MathMax(0.0, prebuffer_value);
   base.postbuffer_min = (int)MathMax(0.0, postbuffer_value);
   base.is_valid = true;

   const int before = collector_count;
   for(int i = 0; i < symbol_count; i++)
   {
      string normalized_symbol = symbol_tokens[i];
      if(StringLen(normalized_symbol) == 0)
         continue;
      NewsEvent instance = base;
      instance.symbol = normalized_symbol;
      News_ComputeBlockWindow(instance);
      const int idx = collector_count;
      if(ArrayResize(collector, collector_count + 1) < 0)
      {
         error_msg = "unable to grow collector array";
         return false;
      }
      collector[idx] = instance;
      collector_count++;
   }

   if(collector_count == before)
   {
      error_msg = "no usable symbol tokens";
      return false;
   }
   return true;
}

//------------------------------------------------------------------------------
// CSV Loading and caching
//------------------------------------------------------------------------------

bool News_ReadCsvInternal(const string path, const datetime mtime)
{
   g_news_test_read_count++;
   const int max_age = News_GetConfiguredMaxAgeHours();
   if(mtime <= 0 || !News_IsCsvFresh(mtime, max_age))
   {
      const double age_hours = News_CalcFileAgeHours(mtime, News_GetNowServer());
      PrintFormat("[News] CSV stale (age %.1f h > max %d): %s", age_hours, max_age, path);
      News_ClearCache();
      return false;
   }

   int handle = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      const int err = GetLastError();
      PrintFormat("[News] CSV open failed (%d): %s", err, path);
      ResetLastError();
      News_ClearCache();
      return false;
   }

   if(FileIsEnding(handle))
   {
      PrintFormat("[News] CSV empty: %s", path);
      FileClose(handle);
      News_ClearCache();
      return false;
   }

   string header_line = News_Trim(FileReadString(handle));
   NewsCsvSchema schema;
   if(!News_ParseHeader(header_line, schema))
   {
      Print("[News] CSV invalid headers: expected timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min");
      FileClose(handle);
      News_ClearCache();
      return false;
   }

   NewsEvent parsed[];
   int parsed_count = 0;
   int skipped = 0;
   int line_no = 1;
   while(!FileIsEnding(handle))
   {
      string raw_line = FileReadString(handle);
      line_no++;
      string error_reason = "";
      if(!News_ProcessCsvLine(raw_line, schema, parsed, parsed_count, error_reason))
      {
         if(error_reason != "")
            PrintFormat("[News] CSV parse error on line %d: %s", line_no, error_reason);
         skipped++;
      }
   }
   FileClose(handle);

   if(parsed_count <= 0)
   {
      PrintFormat("[News] CSV contained no usable rows: %s", path);
      News_ClearCache();
      return false;
   }

   ArrayResize(g_news_events, parsed_count);
   for(int i = 0; i < parsed_count; i++)
      g_news_events[i] = parsed[i];
   g_news_event_count = parsed_count;
   g_news_cached_mtime = mtime;
   g_news_cached_path = path;
   g_news_cache_valid = true;
   g_news_force_reload = false;
   PrintFormat("[News] Loaded %d events (skipped %d) from fallback CSV", parsed_count, skipped);
   return true;
}

bool News_ReloadIfChanged()
{
   const string path = News_GetConfiguredCsvPath();
   datetime mtime = 0;
   if(!News_GetFileMTime(path, mtime))
   {
      PrintFormat("[News] CSV missing: %s", path);
      News_ClearCache();
      return false;
   }

   if(g_news_cache_valid && !g_news_force_reload &&
      g_news_cached_mtime == mtime && g_news_cached_path == path)
   {
      return true;
   }

   return News_ReadCsvInternal(path, mtime);
}

bool News_LoadCsvFallback()
{
   g_news_force_reload = true;
   return News_ReloadIfChanged();
}

void News_ForceReload()
{
   g_news_force_reload = true;
   g_news_cache_valid = false;
}

//------------------------------------------------------------------------------
// Public helpers
//------------------------------------------------------------------------------

bool News_GetEventsForSymbol(const string symbol, NewsEvent &out_events[])
{
   ArrayResize(out_events, 0);
   if(StringLen(symbol) == 0)
      return false;
   if(!News_ReloadIfChanged())
      return false;

   string normalized = News_NormalizeSymbol(symbol);
   if(StringLen(normalized) == 0)
      return false;

   for(int i = 0; i < g_news_event_count; i++)
   {
      if(g_news_events[i].symbol != normalized)
         continue;
      const int idx = ArraySize(out_events);
      ArrayResize(out_events, idx + 1);
      out_events[idx] = g_news_events[i];
   }
   return (ArraySize(out_events) > 0);
}

bool News_IsBlocked(const string symbol)
{
   if(StringLen(symbol) == 0)
      return false;
   if(!News_ReloadIfChanged())
      return false;

   const datetime now_utc = News_GetNowUtc();
   string normalized = News_NormalizeSymbol(symbol);
   for(int i = 0; i < g_news_event_count; i++)
   {
      const NewsEvent event = g_news_events[i];
      if(event.symbol != normalized)
         continue;
      if(event.impact != "HIGH")
         continue;
      if(now_utc >= event.block_start_utc && now_utc <= event.block_end_utc)
         return true;
   }
   return false;
}

string News_GetWindowState(const string symbol, const bool is_protective)
{
   if(StringLen(symbol) == 0)
      return "CLEAR";
   if(News_IsBlocked(symbol))
      return (is_protective ? "PROTECTIVE_ONLY" : "BLOCKED");
   return "CLEAR";
}

void News_PostNewsStabilization()
{
   // Placeholder for future Task 13 integration
}

//------------------------------------------------------------------------------
// Test hooks
//------------------------------------------------------------------------------

void News_Test_SetOverridePath(const string path)
{
   g_news_test_override_path = path;
   News_ForceReload();
}

void News_Test_SetOverrideMaxAgeHours(const int hours)
{
   g_news_test_override_max_age = hours;
   News_ForceReload();
}

void News_Test_SetCurrentTimes(const datetime server_now, const datetime utc_now)
{
   g_news_time_override_active = true;
   g_news_override_server_now = server_now;
   g_news_override_utc_now = utc_now;
}

void News_Test_ClearCurrentTimeOverride()
{
   g_news_time_override_active = false;
   g_news_override_server_now = 0;
   g_news_override_utc_now = 0;
}

void News_Test_ClearOverrides()
{
   g_news_test_override_path = "";
   g_news_test_override_max_age = -1;
   News_Test_ClearCurrentTimeOverride();
   News_ForceReload();
}

int News_Test_GetReadCount()
{
   return g_news_test_read_count;
}

void News_Test_ResetReadCount()
{
   g_news_test_read_count = 0;
}

#endif // RPEA_NEWS_MQH
