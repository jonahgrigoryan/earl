#ifndef INDICATORS_MQH
#define INDICATORS_MQH
// indicators.mqh - Indicator handles and init (M2 implementation)
// References: finalspec.md (Session Statistics)

struct AppContext;

// Snapshot exposed to other modules (BWISC, sessions, risk)
struct IndicatorSnapshot
{
   double   atr_d1;
   double   ma20_h1;
   double   rsi_h1;
   double   open_d1_prev;
   double   high_d1_prev;
   double   low_d1_prev;
   double   close_d1_prev;
   datetime last_refresh;
   bool     has_atr;
   bool     has_ma;
   bool     has_rsi;
   bool     has_ohlc;
};

// Internal per-symbol slot storing handles and last values
struct IndicatorSymbolSlot
{
   string   symbol;
   int      handle_ATR_D1;
   int      handle_MA20_H1;
   int      handle_RSI_H1;
   double   atr_d1;
   double   ma20_h1;
   double   rsi_h1;
   double   open_d1_prev;
   double   high_d1_prev;
   double   low_d1_prev;
   double   close_d1_prev;
   datetime last_refresh;
   bool     has_atr;
   bool     has_ma;
   bool     has_rsi;
   bool     has_ohlc;
};

// Static storage sized by Symbols list during init
IndicatorSymbolSlot g_indicator_slots[];

// Helper: release indicator handles for a slot
void Indicators_ReleaseSlot(IndicatorSymbolSlot *slot)
{
   if(slot == NULL)
      return;

   if(slot->handle_ATR_D1 != INVALID_HANDLE)
   {
      IndicatorRelease(slot->handle_ATR_D1);
      slot->handle_ATR_D1 = INVALID_HANDLE;
   }
   if(slot->handle_MA20_H1 != INVALID_HANDLE)
   {
      IndicatorRelease(slot->handle_MA20_H1);
      slot->handle_MA20_H1 = INVALID_HANDLE;
   }
   if(slot->handle_RSI_H1 != INVALID_HANDLE)
   {
      IndicatorRelease(slot->handle_RSI_H1);
      slot->handle_RSI_H1 = INVALID_HANDLE;
   }
}

// Helper: find slot index for symbol
int Indicators_FindSlot(const string symbol)
{
   int total = ArraySize(g_indicator_slots);
   for(int i=0;i<total;i++)
   {
      if(g_indicator_slots[i].symbol == symbol)
         return i;
   }
   return -1;
}

// Helper: copy latest buffer value if available
bool Indicators_CopyLatestValue(const int handle, double &out_value)
{
   out_value = 0.0;
   if(handle == INVALID_HANDLE)
      return false;

   double values[];
   ArraySetAsSeries(values, true);
   int copied = CopyBuffer(handle, 0, 0, 1, values);
   if(copied < 1)
      return false;

   double v = values[0];
   if(!MathIsValidNumber(v) || v == EMPTY_VALUE)
      return false;

   out_value = v;
   return true;
}

// Initialize indicator handles and per-symbol cache
void Indicators_Init(const AppContext& ctx)
{
   // Release any existing handles before reinitializing
   int existing = ArraySize(g_indicator_slots);
   for(int i=0;i<existing;i++)
   {
      Indicators_ReleaseSlot(&g_indicator_slots[i]);
   }

   ArrayResize(g_indicator_slots, ctx.symbols_count);

   for(int i=0;i<ctx.symbols_count;i++)
   {
      g_indicator_slots[i].symbol = ctx.symbols[i];
      g_indicator_slots[i].handle_ATR_D1 = INVALID_HANDLE;
      g_indicator_slots[i].handle_MA20_H1 = INVALID_HANDLE;
      g_indicator_slots[i].handle_RSI_H1 = INVALID_HANDLE;
      g_indicator_slots[i].atr_d1 = 0.0;
      g_indicator_slots[i].ma20_h1 = 0.0;
      g_indicator_slots[i].rsi_h1 = 0.0;
      g_indicator_slots[i].open_d1_prev = 0.0;
      g_indicator_slots[i].high_d1_prev = 0.0;
      g_indicator_slots[i].low_d1_prev = 0.0;
      g_indicator_slots[i].close_d1_prev = 0.0;
      g_indicator_slots[i].last_refresh = 0;
      g_indicator_slots[i].has_atr = false;
      g_indicator_slots[i].has_ma = false;
      g_indicator_slots[i].has_rsi = false;
      g_indicator_slots[i].has_ohlc = false;

      if(g_indicator_slots[i].symbol == "")
         continue;

      ResetLastError();
      g_indicator_slots[i].handle_ATR_D1 = iATR(g_indicator_slots[i].symbol, PERIOD_D1, 14);
      if(g_indicator_slots[i].handle_ATR_D1 == INVALID_HANDLE)
      {
         PrintFormat("RPEA Indicators_Init: failed to create ATR(D1) handle for %s (err=%d)",
                    g_indicator_slots[i].symbol, GetLastError());
      }

      ResetLastError();
      g_indicator_slots[i].handle_MA20_H1 = iMA(g_indicator_slots[i].symbol, PERIOD_H1, 20, 0, MODE_EMA, PRICE_CLOSE);
      if(g_indicator_slots[i].handle_MA20_H1 == INVALID_HANDLE)
      {
         PrintFormat("RPEA Indicators_Init: failed to create EMA20(H1) handle for %s (err=%d)",
                    g_indicator_slots[i].symbol, GetLastError());
      }

      ResetLastError();
      g_indicator_slots[i].handle_RSI_H1 = iRSI(g_indicator_slots[i].symbol, PERIOD_H1, 14, PRICE_CLOSE);
      if(g_indicator_slots[i].handle_RSI_H1 == INVALID_HANDLE)
      {
         PrintFormat("RPEA Indicators_Init: failed to create RSI14(H1) handle for %s (err=%d)",
                    g_indicator_slots[i].symbol, GetLastError());
      }
   }
}

// Refresh per-symbol derived stats and cache latest values
void Indicators_Refresh(const AppContext& ctx, const string symbol)
{
   int idx = Indicators_FindSlot(symbol);
   if(idx < 0)
      return;

   double value = 0.0;
   if(Indicators_CopyLatestValue(g_indicator_slots[idx].handle_ATR_D1, value))
   {
      g_indicator_slots[idx].atr_d1 = value;
      g_indicator_slots[idx].has_atr = true;
   }
   else if(!g_indicator_slots[idx].has_atr)
   {
      g_indicator_slots[idx].atr_d1 = 0.0;
      g_indicator_slots[idx].has_atr = false;
   }

   if(Indicators_CopyLatestValue(g_indicator_slots[idx].handle_MA20_H1, value))
   {
      g_indicator_slots[idx].ma20_h1 = value;
      g_indicator_slots[idx].has_ma = true;
   }
   else if(!g_indicator_slots[idx].has_ma)
   {
      g_indicator_slots[idx].ma20_h1 = 0.0;
      g_indicator_slots[idx].has_ma = false;
   }

   if(Indicators_CopyLatestValue(g_indicator_slots[idx].handle_RSI_H1, value))
   {
      g_indicator_slots[idx].rsi_h1 = value;
      g_indicator_slots[idx].has_rsi = true;
   }
   else if(!g_indicator_slots[idx].has_rsi)
   {
      g_indicator_slots[idx].rsi_h1 = 0.0;
      g_indicator_slots[idx].has_rsi = false;
   }

   // Copy yesterday's D1 OHLC (shift = 1)
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, PERIOD_D1, 0, 3, rates);
   if(copied >= 2)
   {
      g_indicator_slots[idx].open_d1_prev = rates[1].open;
      g_indicator_slots[idx].high_d1_prev = rates[1].high;
      g_indicator_slots[idx].low_d1_prev  = rates[1].low;
      g_indicator_slots[idx].close_d1_prev = rates[1].close;
      g_indicator_slots[idx].has_ohlc = true;
   }
   else if(!g_indicator_slots[idx].has_ohlc)
   {
      g_indicator_slots[idx].open_d1_prev = 0.0;
      g_indicator_slots[idx].high_d1_prev = 0.0;
      g_indicator_slots[idx].low_d1_prev  = 0.0;
      g_indicator_slots[idx].close_d1_prev = 0.0;
      g_indicator_slots[idx].has_ohlc = false;
   }

   g_indicator_slots[idx].last_refresh = TimeCurrent();
}

// Retrieve cached snapshot for consumers; returns true if slot exists
bool Indicators_GetSnapshot(const string symbol, IndicatorSnapshot &out_snapshot)
{
   int idx = Indicators_FindSlot(symbol);
   if(idx < 0)
   {
      out_snapshot.atr_d1 = 0.0;
      out_snapshot.ma20_h1 = 0.0;
      out_snapshot.rsi_h1 = 0.0;
      out_snapshot.open_d1_prev = 0.0;
      out_snapshot.high_d1_prev = 0.0;
      out_snapshot.low_d1_prev = 0.0;
      out_snapshot.close_d1_prev = 0.0;
      out_snapshot.last_refresh = 0;
      out_snapshot.has_atr = false;
      out_snapshot.has_ma = false;
      out_snapshot.has_rsi = false;
      out_snapshot.has_ohlc = false;
      return false;
   }

   out_snapshot.atr_d1 = g_indicator_slots[idx].atr_d1;
   out_snapshot.ma20_h1 = g_indicator_slots[idx].ma20_h1;
   out_snapshot.rsi_h1 = g_indicator_slots[idx].rsi_h1;
   out_snapshot.open_d1_prev = g_indicator_slots[idx].open_d1_prev;
   out_snapshot.high_d1_prev = g_indicator_slots[idx].high_d1_prev;
   out_snapshot.low_d1_prev = g_indicator_slots[idx].low_d1_prev;
   out_snapshot.close_d1_prev = g_indicator_slots[idx].close_d1_prev;
   out_snapshot.last_refresh = g_indicator_slots[idx].last_refresh;
   out_snapshot.has_atr = g_indicator_slots[idx].has_atr;
   out_snapshot.has_ma = g_indicator_slots[idx].has_ma;
   out_snapshot.has_rsi = g_indicator_slots[idx].has_rsi;
   out_snapshot.has_ohlc = g_indicator_slots[idx].has_ohlc;
   return true;
}

#endif // INDICATORS_MQH
