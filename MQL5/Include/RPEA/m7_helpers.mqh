//+------------------------------------------------------------------+
//| m7_helpers.mqh - M7 Ensemble Helper Functions                     |
//+------------------------------------------------------------------+
// References: docs/m7-final-workflow.md (Phase 0.3 Wrapper Functions)
#ifndef M7_HELPERS_MQH
#define M7_HELPERS_MQH

#include <RPEA/indicators.mqh>
#include <RPEA/liquidity.mqh>
#include <RPEA/sessions.mqh>
#include <RPEA/symbol_bridge.mqh>
#include <RPEA/emrt.mqh>
#include <RPEA/order_engine.mqh>
#include <RPEA/news.mqh>

// === M7 Session State Globals ===
int    g_entries_this_session = 0;
bool   g_locked_to_mr = false;
string g_current_session_label = "";
datetime g_entry_budget_day_anchor = 0;

// Track positions to avoid double-counting partials
ulong g_counted_positions[];

// Rolling spread buffer (Task 02)
#define M7_SPREAD_BUFFER_SYMBOL_CAP 16
#define M7_SPREAD_BUFFER_SAMPLE_CAP 512
#define M7_ATR_PERCENTILE_LOOKBACK 60
#define M7_ATR_PERCENTILE_MIN_SAMPLES 20

string g_m7_spread_symbols[];
int    g_m7_spread_counts[];
int    g_m7_spread_next_idx[];
double g_m7_spread_ring[][M7_SPREAD_BUFFER_SAMPLE_CAP];

#ifdef RPEA_TEST_RUNNER
bool   g_m7_test_atr_override_enabled = false;
string g_m7_test_atr_override_symbol = "";
double g_m7_test_atr_override_values[];
#endif

void M7_InitSpreadBuffer()
{
   if(ArraySize(g_m7_spread_symbols) > 0)
      return;

   ArrayResize(g_m7_spread_symbols, M7_SPREAD_BUFFER_SYMBOL_CAP);
   ArrayResize(g_m7_spread_counts, M7_SPREAD_BUFFER_SYMBOL_CAP);
   ArrayResize(g_m7_spread_next_idx, M7_SPREAD_BUFFER_SYMBOL_CAP);
   ArrayResize(g_m7_spread_ring, M7_SPREAD_BUFFER_SYMBOL_CAP);

   for(int i = 0; i < M7_SPREAD_BUFFER_SYMBOL_CAP; i++)
   {
      g_m7_spread_symbols[i] = "";
      g_m7_spread_counts[i] = 0;
      g_m7_spread_next_idx[i] = 0;
      for(int j = 0; j < M7_SPREAD_BUFFER_SAMPLE_CAP; j++)
         g_m7_spread_ring[i][j] = 0.0;
   }
}

int M7_FindSpreadSlot(const string symbol, const bool create_if_missing)
{
   if(symbol == "")
      return -1;

   M7_InitSpreadBuffer();

   int free_idx = -1;
   for(int i = 0; i < M7_SPREAD_BUFFER_SYMBOL_CAP; i++)
   {
      if(g_m7_spread_symbols[i] == symbol)
         return i;
      if(free_idx < 0 && g_m7_spread_symbols[i] == "")
         free_idx = i;
   }

   if(!create_if_missing || free_idx < 0)
      return -1;

   g_m7_spread_symbols[free_idx] = symbol;
   g_m7_spread_counts[free_idx] = 0;
   g_m7_spread_next_idx[free_idx] = 0;
   for(int j = 0; j < M7_SPREAD_BUFFER_SAMPLE_CAP; j++)
      g_m7_spread_ring[free_idx][j] = 0.0;
   return free_idx;
}

void M7_RecordSpreadSample(const string symbol, const double spread)
{
   if(!MathIsValidNumber(spread) || spread <= 0.0)
      return;

   int idx = M7_FindSpreadSlot(symbol, true);
   if(idx < 0)
      return;

   int write_idx = g_m7_spread_next_idx[idx];
   if(write_idx < 0 || write_idx >= M7_SPREAD_BUFFER_SAMPLE_CAP)
      write_idx = 0;

   g_m7_spread_ring[idx][write_idx] = spread;
   g_m7_spread_next_idx[idx] = (write_idx + 1) % M7_SPREAD_BUFFER_SAMPLE_CAP;
   if(g_m7_spread_counts[idx] < M7_SPREAD_BUFFER_SAMPLE_CAP)
      g_m7_spread_counts[idx]++;
}

double M7_GetSpreadMeanFromBuffer(const string symbol, int periods)
{
   int idx = M7_FindSpreadSlot(symbol, false);
   if(idx < 0)
      return 0.0;

   int count = g_m7_spread_counts[idx];
   if(count <= 0)
      return 0.0;

   if(periods <= 0)
      periods = 1;
   if(periods > count)
      periods = count;

   double sum = 0.0;
   int read_idx = g_m7_spread_next_idx[idx] - 1;
   if(read_idx < 0)
      read_idx = M7_SPREAD_BUFFER_SAMPLE_CAP - 1;

   for(int i = 0; i < periods; i++)
   {
      sum += g_m7_spread_ring[idx][read_idx];
      read_idx--;
      if(read_idx < 0)
         read_idx = M7_SPREAD_BUFFER_SAMPLE_CAP - 1;
   }

   return (periods > 0) ? (sum / (double)periods) : 0.0;
}

double M7_PercentileRank(const double value, const double &samples[])
{
   if(!MathIsValidNumber(value) || value <= 0.0)
      return 0.5;

   int less = 0;
   int equal = 0;
   int valid = 0;
   int n = ArraySize(samples);
   for(int i = 0; i < n; i++)
   {
      double sample = samples[i];
      if(!MathIsValidNumber(sample) || sample <= 0.0)
         continue;
      valid++;
      if(sample < value)
         less++;
      else if(MathAbs(sample - value) <= 1e-9)
         equal++;
   }

   if(valid <= 0)
      return 0.5;

   double rank = ((double)less + 0.5 * (double)equal) / (double)valid;
   return MathMax(0.0, MathMin(1.0, rank));
}

bool M7_LoadATRSamples(const string symbol, const int lookback, double &out_current, double &out_history[])
{
   out_current = 0.0;
   ArrayResize(out_history, 0);

   if(symbol == "" || lookback <= 0)
      return false;

   int atr_handle = iATR(symbol, PERIOD_D1, 14);
   if(atr_handle == INVALID_HANDLE)
      return false;

   double atr_vals[];
   ArraySetAsSeries(atr_vals, true);
   int copied = CopyBuffer(atr_handle, 0, 0, lookback + 1, atr_vals);
   IndicatorRelease(atr_handle);
   if(copied <= 1)
      return false;

   out_current = atr_vals[0];
   if(!MathIsValidNumber(out_current) || out_current <= 0.0)
      return false;

   int valid_count = 0;
   ArrayResize(out_history, copied - 1);
   for(int i = 1; i < copied; i++)
   {
      double sample = atr_vals[i];
      if(!MathIsValidNumber(sample) || sample <= 0.0)
         continue;
      out_history[valid_count] = sample;
      valid_count++;
   }

   ArrayResize(out_history, valid_count);
   return (valid_count > 0);
}

#ifdef RPEA_TEST_RUNNER
bool M7_LoadATRSamplesFromTestOverride(const string symbol,
                                       double &out_current,
                                       double &out_history[])
{
   out_current = 0.0;
   ArrayResize(out_history, 0);

   if(!g_m7_test_atr_override_enabled)
      return false;
   if(g_m7_test_atr_override_symbol != "" && g_m7_test_atr_override_symbol != symbol)
      return false;

   int n = ArraySize(g_m7_test_atr_override_values);
   if(n <= 1)
      return false;

   out_current = g_m7_test_atr_override_values[0];
   if(!MathIsValidNumber(out_current) || out_current <= 0.0)
      return false;

   int valid = 0;
   ArrayResize(out_history, n - 1);
   for(int i = 1; i < n; i++)
   {
      double sample = g_m7_test_atr_override_values[i];
      if(!MathIsValidNumber(sample) || sample <= 0.0)
         continue;
      out_history[valid] = sample;
      valid++;
   }
   ArrayResize(out_history, valid);
   return (valid > 0);
}
#endif

// ATR accessor using existing snapshot infrastructure
double M7_GetATR_D1(const string symbol)
{
   IndicatorSnapshot snapshot;
   if(Indicators_GetSnapshot(symbol, snapshot))
      return snapshot.atr_d1;
   return 0.0;  // Safe default
}

// Spread accessor: synthetic for XAUEUR, Liquidity_SpreadOK for others
double M7_GetSpreadCurrent(const string symbol)
{
   if(symbol == "XAUEUR")
   {
      double xau = SymbolInfoDouble("XAUUSD", SYMBOL_BID);
      double eur = SymbolInfoDouble("EURUSD", SYMBOL_BID);
      if(xau <= 0.0 || eur <= 0.0) return 0.0;
      if(MR_UseLogRatio)
         return MathLog(xau) - MathLog(eur);
      double beta = EMRT_GetBeta("XAUEUR");
      return xau - beta * eur;
   }

   string exec_symbol = SymbolBridge_GetExecutionSymbol(symbol);
   if(exec_symbol == "") exec_symbol = symbol;

   double spread_out = 0.0;
   double threshold_out = 0.0;
   Liquidity_SpreadOK(exec_symbol, spread_out, threshold_out);
   return spread_out;
}

// Spread mean from rolling symbol-local buffer (Task 02)
double M7_GetSpreadMean(const string symbol, int periods)
{
   if(periods <= 0)
      periods = 1;

   double current_spread = M7_GetSpreadCurrent(symbol);
   if(!MathIsValidNumber(current_spread) || current_spread <= 0.0)
      return 0.0;

   M7_RecordSpreadSample(symbol, current_spread);
   double mean = M7_GetSpreadMeanFromBuffer(symbol, periods);
   if(!MathIsValidNumber(mean) || mean <= 0.0)
      return current_spread;
   return mean;
}

// ORE (Opening Range Energy) - uses existing OR snapshot + ATR
double M7_GetCurrentORE(const AppContext &ctx, const string symbol)
{
   SessionORSnapshot or_snap;
   if(!Sessions_GetLondonORSnapshot(ctx, symbol, or_snap))
      return 0.5;  // Neutral default
   if(!or_snap.or_complete)
      return 0.5;

   double or_span = or_snap.or_high - or_snap.or_low;
   double atr = M7_GetATR_D1(symbol);
   if(atr < 1e-9) return 0.5;

   return or_span / atr;  // ORE = OR span / ATR(D1)
}

// ATR percentile vs lookback (Task 03): rank current ATR against D1 history
double M7_GetATR_D1_Percentile(const AppContext &ctx, const string symbol)
{
   if(ctx.symbols_count < 0)
      return 0.5;

   string exec_symbol = SymbolBridge_GetExecutionSymbol(symbol);
   if(exec_symbol == "")
      exec_symbol = symbol;

   double current_atr = 0.0;
   double history[];
   bool loaded = false;

#ifdef RPEA_TEST_RUNNER
   loaded = M7_LoadATRSamplesFromTestOverride(symbol, current_atr, history);
#endif
   if(!loaded)
      loaded = M7_LoadATRSamples(exec_symbol, M7_ATR_PERCENTILE_LOOKBACK, current_atr, history);
   if(!loaded)
      return 0.5;

   if(ArraySize(history) < M7_ATR_PERCENTILE_MIN_SAMPLES)
      return 0.5;

   return M7_PercentileRank(current_atr, history);
}

// Session age in minutes since session start
int M7_GetSessionAgeMinutes(const AppContext &ctx, const string symbol)
{
   // Determine current session
   bool in_london = Sessions_InLondon(ctx, symbol);
   bool in_ny = Sessions_InNewYork(ctx, symbol);

   if(!in_london && !in_ny)
      return 0;  // Not in session

   // Get session start time from OR snapshot
   SessionORSnapshot or_snap;
   if(in_london)
   {
      if(!Sessions_GetLondonORSnapshot(ctx, symbol, or_snap))
         return 60;  // Default
   }
   else
   {
      if(!Sessions_GetORSnapshot(ctx, symbol, SESSION_LABEL_NEWYORK, or_snap))
         return 60;  // Default
   }

   // Calculate minutes since OR start
   datetime now = ctx.current_server_time;
   int age_seconds = (int)(now - or_snap.or_start);
   return age_seconds / 60;
}

// News proximity check - wrapper around existing News_IsBlocked
bool M7_NewsIsWithin15Minutes(const string symbol)
{
   // The existing News_IsBlocked uses configurable windows
   return News_IsBlocked(symbol);
}

// Clear position tracking on session change
void M7_ClearPositionTracking()
{
   ArrayResize(g_counted_positions, 0);
}

// Session entry counter
int M7_GetEntriesThisSession(const AppContext &ctx, const string symbol)
{
   // Track entry budget by trading day, not by overlapping session label.
   // This prevents early-session entries from being "forgotten" when the
   // preferred label flips from NY to LO later in the same day.
   MqlDateTime tm;
   TimeToStruct(ctx.current_server_time, tm);
   tm.hour = 0;
   tm.min = 0;
   tm.sec = 0;
   datetime current_day_anchor = StructToTime(tm);

   if(current_day_anchor != g_entry_budget_day_anchor)
   {
      g_entries_this_session = 0;
      g_locked_to_mr = false;
      g_entry_budget_day_anchor = current_day_anchor;
      M7_ClearPositionTracking();
   }

   string current_label = "";
   if(Sessions_InLondon(ctx, symbol)) current_label = SESSION_LABEL_LONDON;
   else if(Sessions_InNewYork(ctx, symbol)) current_label = SESSION_LABEL_NEWYORK;
   g_current_session_label = current_label;

   return g_entries_this_session;
}

// Increment entry counter
// IMPORTANT: Call from OnTradeTransaction on DEAL_ENTRY_IN, NOT from allocator
// This ensures we count actual fills, not just order attempts
// Filter by EA magic number and use first-entry-per-position guard
void M7_IncrementEntries()
{
   g_entries_this_session++;
}

// Call from OnTradeTransaction when deal is confirmed
// Returns true if this is a new entry that should be counted
bool M7_ShouldCountEntry(const ulong position_id, const long deal_magic)
{
   // Filter: only count our EA's trades
   if(position_id == 0) return false;
   if(!OrderEngine_IsOurMagic(deal_magic)) return false;

   // Check if we already counted this position
   int size = ArraySize(g_counted_positions);
   for(int i = 0; i < size; i++)
   {
      if(g_counted_positions[i] == position_id)
         return false;  // Already counted
   }

   // New position - add to tracked list and count it
   ArrayResize(g_counted_positions, size + 1);
   g_counted_positions[size] = position_id;
   return true;
}

// MR lock flag for hysteresis
bool M7_IsLockedToMR()
{
   return g_locked_to_mr;
}

// Set MR lock (call when MR is chosen)
void M7_SetLockedToMR(bool locked)
{
   g_locked_to_mr = locked;
}

// Reset session state (call on session change or EA init)
void M7_ResetSessionState()
{
   g_entries_this_session = 0;
   g_locked_to_mr = false;
   g_current_session_label = "";
   g_entry_budget_day_anchor = 0;
   M7_ClearPositionTracking();
}

#ifdef RPEA_TEST_RUNNER
void M7_TestResetSpreadBuffer()
{
   M7_InitSpreadBuffer();
   for(int i = 0; i < M7_SPREAD_BUFFER_SYMBOL_CAP; i++)
   {
      g_m7_spread_symbols[i] = "";
      g_m7_spread_counts[i] = 0;
      g_m7_spread_next_idx[i] = 0;
      for(int j = 0; j < M7_SPREAD_BUFFER_SAMPLE_CAP; j++)
         g_m7_spread_ring[i][j] = 0.0;
   }
}

void M7_TestInjectSpreadSample(const string symbol, const double spread)
{
   M7_RecordSpreadSample(symbol, spread);
}

double M7_TestGetSpreadMeanFromBuffer(const string symbol, const int periods)
{
   return M7_GetSpreadMeanFromBuffer(symbol, periods);
}

int M7_TestGetSpreadSampleCount(const string symbol)
{
   int idx = M7_FindSpreadSlot(symbol, false);
   if(idx < 0)
      return 0;
   return g_m7_spread_counts[idx];
}

void M7_TestSetATRPercentileSeries(const string symbol, const double &values[])
{
   g_m7_test_atr_override_enabled = true;
   g_m7_test_atr_override_symbol = symbol;
   int n = ArraySize(values);
   ArrayResize(g_m7_test_atr_override_values, n);
   for(int i = 0; i < n; i++)
      g_m7_test_atr_override_values[i] = values[i];
}

void M7_TestClearATRPercentileSeries()
{
   g_m7_test_atr_override_enabled = false;
   g_m7_test_atr_override_symbol = "";
   ArrayResize(g_m7_test_atr_override_values, 0);
}
#endif // RPEA_TEST_RUNNER

#endif // M7_HELPERS_MQH
