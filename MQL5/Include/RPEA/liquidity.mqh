#ifndef RPEA_LIQUIDITY_MQH
#define RPEA_LIQUIDITY_MQH
// liquidity.mqh - Spread/slippage gates with ATR-based filtering (Task 22)
// References: finalspec.md (Liquidity Intelligence), tasks.md (Task 22)

#include <RPEA/config.mqh>
#include <RPEA/indicators.mqh>
#include <RPEA/logging.mqh>

#define LIQUIDITY_WINDOW 200

string g_liquidity_symbols[];
double g_liquidity_spread_samples[][LIQUIDITY_WINDOW];
double g_liquidity_slippage_samples[][LIQUIDITY_WINDOW];
int    g_liquidity_spread_count[];
int    g_liquidity_slippage_count[];
int    g_liquidity_spread_index[];
int    g_liquidity_slippage_index[];
double g_liquidity_last_spread[];
double g_liquidity_last_slippage[];
bool   g_liquidity_has_last_spread[];
bool   g_liquidity_has_last_slippage[];

//+------------------------------------------------------------------+
//| Check if spread is acceptable relative to ATR (Task 22)          |
//| Formula: MaxSpread = ATR(D1) * SpreadMultATR                     |
//| Default SpreadMultATR = 0.005 (0.5% of Daily ATR)                |
//| Fail open by design on missing ATR/point to avoid false gate     |
//+------------------------------------------------------------------+
bool Liquidity_SpreadOK(const string symbol, double &out_spread, double &out_threshold)
{
   out_spread = 0.0;
   out_threshold = 0.0;

   // Get SpreadMultATR from config
   double spread_mult_atr = Config_GetSpreadMultATR();

   // Get current spread in points and convert to price units
   long spread_pts = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   // Security: Clamp negative spread values from broker
   if(spread_pts < 0) spread_pts = 0;
   
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(point <= 0.0)
   {
      LogDecision("Liquidity", "WARNING", StringFormat(
         "{\"symbol\":\"%s\",\"reason\":\"Point unavailable, allowing trade\"}",
         symbol));
      return true; // Fail open
   }

   out_spread = (double)spread_pts * point;

   // Get ATR from indicator snapshot
   IndicatorSnapshot snapshot;
   if(!Indicators_GetSnapshot(symbol, snapshot) || !snapshot.has_atr || snapshot.atr_d1 <= 0.0)
   {
      LogDecision("Liquidity", "WARNING", StringFormat(
         "{\"symbol\":\"%s\",\"spread_pts\":%d,\"spread\":%.5f,\"reason\":\"ATR unavailable, allowing trade\"}",
         symbol, spread_pts, out_spread));
      return true; // Fail open
   }

   double atr = snapshot.atr_d1;
   // Threshold = ATR(D1) * configurable multiplier (default 0.005 ≈ 0.5% ATR)
   out_threshold = atr * spread_mult_atr;

   // Check spread against threshold
   if(out_spread > out_threshold)
   {
      LogDecision("Liquidity", "GATED", StringFormat(
         "{\"symbol\":\"%s\",\"spread_pts\":%d,\"spread\":%.5f,\"atr\":%.5f,\"threshold\":%.5f,\"mult\":%.4f,\"reason\":\"Spread too wide\"}",
         symbol, spread_pts, out_spread, atr, out_threshold, spread_mult_atr));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Legacy overload for backward compatibility                       |
//+------------------------------------------------------------------+
bool Liquidity_SpreadOK(const string symbol)
{
   double spread_val = 0.0;
   double spread_thresh = 0.0;
   return Liquidity_SpreadOK(symbol, spread_val, spread_thresh);
}

int Liquidity_FindSymbolIndex(const string symbol)
{
   if(symbol == "")
      return -1;

   int count = ArraySize(g_liquidity_symbols);
   for(int i = 0; i < count; i++)
   {
      if(g_liquidity_symbols[i] == symbol)
         return i;
   }
   return -1;
}

int Liquidity_EnsureSymbolIndex(const string symbol)
{
   if(symbol == "")
      return -1;

   int idx = Liquidity_FindSymbolIndex(symbol);
   if(idx >= 0)
      return idx;

   int new_idx = ArraySize(g_liquidity_symbols);
   ArrayResize(g_liquidity_symbols, new_idx + 1);
   ArrayResize(g_liquidity_spread_samples, new_idx + 1);
   ArrayResize(g_liquidity_slippage_samples, new_idx + 1);
   ArrayResize(g_liquidity_spread_count, new_idx + 1);
   ArrayResize(g_liquidity_slippage_count, new_idx + 1);
   ArrayResize(g_liquidity_spread_index, new_idx + 1);
   ArrayResize(g_liquidity_slippage_index, new_idx + 1);
   ArrayResize(g_liquidity_last_spread, new_idx + 1);
   ArrayResize(g_liquidity_last_slippage, new_idx + 1);
   ArrayResize(g_liquidity_has_last_spread, new_idx + 1);
   ArrayResize(g_liquidity_has_last_slippage, new_idx + 1);

   g_liquidity_symbols[new_idx] = symbol;
   g_liquidity_spread_count[new_idx] = 0;
   g_liquidity_slippage_count[new_idx] = 0;
   g_liquidity_spread_index[new_idx] = 0;
   g_liquidity_slippage_index[new_idx] = 0;
   g_liquidity_last_spread[new_idx] = 0.0;
   g_liquidity_last_slippage[new_idx] = 0.0;
   g_liquidity_has_last_spread[new_idx] = false;
   g_liquidity_has_last_slippage[new_idx] = false;
   for(int i = 0; i < LIQUIDITY_WINDOW; i++)
   {
      g_liquidity_spread_samples[new_idx][i] = 0.0;
      g_liquidity_slippage_samples[new_idx][i] = 0.0;
   }

   return new_idx;
}

bool Liquidity_UpdateStats(const string symbol, const double spread_pts, const double slippage_pts)
{
   int idx = Liquidity_EnsureSymbolIndex(symbol);
   if(idx < 0)
      return false;

   bool updated = false;

   if(MathIsValidNumber(spread_pts) && spread_pts > 0.0)
   {
      int pos = g_liquidity_spread_index[idx];
      g_liquidity_spread_samples[idx][pos] = spread_pts;
      g_liquidity_spread_index[idx] = (pos + 1) % LIQUIDITY_WINDOW;
      if(g_liquidity_spread_count[idx] < LIQUIDITY_WINDOW)
         g_liquidity_spread_count[idx]++;
      g_liquidity_last_spread[idx] = spread_pts;
      g_liquidity_has_last_spread[idx] = true;
      updated = true;
   }

   if(MathIsValidNumber(slippage_pts) && slippage_pts >= 0.0)
   {
      int pos = g_liquidity_slippage_index[idx];
      g_liquidity_slippage_samples[idx][pos] = slippage_pts;
      g_liquidity_slippage_index[idx] = (pos + 1) % LIQUIDITY_WINDOW;
      if(g_liquidity_slippage_count[idx] < LIQUIDITY_WINDOW)
         g_liquidity_slippage_count[idx]++;
      g_liquidity_last_slippage[idx] = slippage_pts;
      g_liquidity_has_last_slippage[idx] = true;
      updated = true;
   }

   return updated;
}

double Liquidity_GetSpreadQuantile(const string symbol)
{
   int idx = Liquidity_FindSymbolIndex(symbol);
   if(idx < 0 || !g_liquidity_has_last_spread[idx] || g_liquidity_spread_count[idx] <= 0)
      return 0.5;

   // Inline quantile: MQL5 cannot pass 2D array row as 1D ref parameter
   double current_value = g_liquidity_last_spread[idx];
   int n = g_liquidity_spread_count[idx];
   if(n > LIQUIDITY_WINDOW)
      n = LIQUIDITY_WINDOW;
   int less = 0;
   int equal = 0;
   for(int i = 0; i < n; i++)
   {
      double sample = g_liquidity_spread_samples[idx][i];
      if(sample < current_value)
         less++;
      else if(sample == current_value)
         equal++;
   }
   double quantile = ((double)less + 0.5 * (double)equal) / (double)n;
   if(quantile < 0.0) quantile = 0.0;
   if(quantile > 1.0) quantile = 1.0;
   return quantile;
}

double Liquidity_GetSlippageQuantile(const string symbol)
{
   int idx = Liquidity_FindSymbolIndex(symbol);
   if(idx < 0 || !g_liquidity_has_last_slippage[idx] || g_liquidity_slippage_count[idx] <= 0)
      return 0.5;

   // Inline quantile: MQL5 cannot pass 2D array row as 1D ref parameter
   double current_value = g_liquidity_last_slippage[idx];
   int n = g_liquidity_slippage_count[idx];
   if(n > LIQUIDITY_WINDOW)
      n = LIQUIDITY_WINDOW;
   int less = 0;
   int equal = 0;
   for(int i = 0; i < n; i++)
   {
      double sample = g_liquidity_slippage_samples[idx][i];
      if(sample < current_value)
         less++;
      else if(sample == current_value)
         equal++;
   }
   double quantile = ((double)less + 0.5 * (double)equal) / (double)n;
   if(quantile < 0.0) quantile = 0.0;
   if(quantile > 1.0) quantile = 1.0;
   return quantile;
}
#endif // RPEA_LIQUIDITY_MQH
