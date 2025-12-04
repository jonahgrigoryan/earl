#ifndef RPEA_LIQUIDITY_MQH
#define RPEA_LIQUIDITY_MQH
// liquidity.mqh - Spread/slippage gates with ATR-based filtering (Task 22)
// References: finalspec.md (Liquidity Intelligence), tasks.md (Task 22)

#include <RPEA/config.mqh>
#include <RPEA/indicators.mqh>
#include <RPEA/logging.mqh>

//+------------------------------------------------------------------+
//| Check if spread is acceptable relative to ATR (Task 22)          |
//| Formula: MaxSpread = ATR(D1) * SpreadMultATR                     |
//| Default SpreadMultATR = 0.005 (0.5% of Daily ATR)                |
//+------------------------------------------------------------------+
bool Liquidity_SpreadOK(const string symbol, double &out_spread, double &out_threshold)
{
   out_spread = 0.0;
   out_threshold = 0.0;

   // Get SpreadMultATR from config
   double spread_mult_atr = Config_GetSpreadMultATR();

   // Get current spread in points and convert to price units
   long spread_pts = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
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

void Liquidity_UpdateStats(const string symbol)
{
   // TODO[M6]: update rolling spread/slippage stats
}
#endif // RPEA_LIQUIDITY_MQH
