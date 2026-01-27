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

// Track positions to avoid double-counting partials
ulong g_counted_positions[];

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
      double beta = EMRT_GetBeta("XAUEUR");
      if(xau <= 0.0 || eur <= 0.0) return 0.0;
      return xau - beta * eur;
   }

   string exec_symbol = SymbolBridge_GetExecutionSymbol(symbol);
   if(exec_symbol == "") exec_symbol = symbol;

   double spread_out = 0.0;
   double threshold_out = 0.0;
   Liquidity_SpreadOK(exec_symbol, spread_out, threshold_out);
   return spread_out;
}

// Spread mean - simple moving average of recent spreads
// NOTE: Returns current spread as baseline; full implementation in Phase 2
double M7_GetSpreadMean(const string symbol, int periods)
{
   // TODO[M7-Phase2]: Implement rolling spread buffer
   if(periods <= 0) { /* no-op */ }
   return M7_GetSpreadCurrent(symbol);
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

// ATR percentile vs lookback - compares current to 20-day SMA
double M7_GetATR_D1_Percentile(const AppContext &ctx, const string symbol)
{
   if(ctx.symbols_count < 0) { /* suppress unused */ }

   double current_atr = M7_GetATR_D1(symbol);
   if(current_atr < 1e-9) return 0.5;

   // Get ATR SMA using indicator buffer
   // TODO[M7-Phase4]: Full percentile calculation
   // For now, use simple ratio approximation
   IndicatorSnapshot snapshot;
   if(!Indicators_GetSnapshot(symbol, snapshot))
      return 0.5;

   // Approximate: if ATR > 1.2x typical, high percentile
   double typical_atr = snapshot.atr_d1;  // Baseline
   if(typical_atr < 1e-9) return 0.5;

   double ratio = current_atr / typical_atr;
   return MathMin(1.0, MathMax(0.0, ratio - 0.5));  // Map [0.5, 1.5] to [0, 1]
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
   // Check if session changed
   string current_label = "";
   if(Sessions_InLondon(ctx, symbol)) current_label = SESSION_LABEL_LONDON;
   else if(Sessions_InNewYork(ctx, symbol)) current_label = SESSION_LABEL_NEWYORK;

   if(current_label != g_current_session_label)
   {
      // Session changed - reset counters
      g_entries_this_session = 0;
      g_locked_to_mr = false;
      g_current_session_label = current_label;
      M7_ClearPositionTracking();
   }

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
   M7_ClearPositionTracking();
}

#endif // M7_HELPERS_MQH
