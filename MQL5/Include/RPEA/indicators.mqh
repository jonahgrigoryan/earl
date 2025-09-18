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
static IndicatorSymbolSlot g_indicator_slots[];

// Helper: release indicator handles for a slot
static void Indicators_ReleaseSlot(IndicatorSymbolSlot &slot)
{
   if(slot.handle_ATR_D1 != INVALID_HANDLE)
   {
      IndicatorRelease(slot.handle_ATR_D1);
      slot.handle_ATR_D1 = INVALID_HANDLE;
   }
   if(slot.handle_MA20_H1 != INVALID_HANDLE)
   {
      IndicatorRelease(slot.handle_MA20_H1);
      slot.handle_MA20_H1 = INVALID_HANDLE;
   }
   if(slot.handle_RSI_H1 != INVALID_HANDLE)
   {
      IndicatorRelease(slot.handle_RSI_H1);
      slot.handle_RSI_H1 = INVALID_HANDLE;
   }
}

// Helper: find slot index for symbol
static int Indicators_FindSlot(const string symbol)
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
static bool Indicators_CopyLatestValue(const int handle, double &out_value)
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
      Indicators_ReleaseSlot(g_indicator_slots[i]);
   }

   ArrayResize(g_indicator_slots, ctx.symbols_count);

   for(int i=0;i<ctx.symbols_count;i++)
   {
      IndicatorSymbolSlot &slot = g_indicator_slots[i];
      slot.symbol = ctx.symbols[i];
      slot.handle_ATR_D1 = INVALID_HANDLE;
      slot.handle_MA20_H1 = INVALID_HANDLE;
      slot.handle_RSI_H1 = INVALID_HANDLE;
      slot.atr_d1 = 0.0;
      slot.ma20_h1 = 0.0;
      slot.rsi_h1 = 0.0;
      slot.open_d1_prev = 0.0;
      slot.high_d1_prev = 0.0;
      slot.low_d1_prev = 0.0;
      slot.close_d1_prev = 0.0;
      slot.last_refresh = 0;
      slot.has_atr = false;
      slot.has_ma = false;
      slot.has_rsi = false;
      slot.has_ohlc = false;

      if(slot.symbol == "")
         continue;

      ResetLastError();
      slot.handle_ATR_D1 = iATR(slot.symbol, PERIOD_D1, 14);
      if(slot.handle_ATR_D1 == INVALID_HANDLE)
      {
         PrintFormat("RPEA Indicators_Init: failed to create ATR(D1) handle for %s (err=%d)",
                    slot.symbol, GetLastError());
      }

      ResetLastError();
      slot.handle_MA20_H1 = iMA(slot.symbol, PERIOD_H1, 20, 0, MODE_EMA, PRICE_CLOSE);
      if(slot.handle_MA20_H1 == INVALID_HANDLE)
      {
         PrintFormat("RPEA Indicators_Init: failed to create EMA20(H1) handle for %s (err=%d)",
                    slot.symbol, GetLastError());
      }

      ResetLastError();
      slot.handle_RSI_H1 = iRSI(slot.symbol, PERIOD_H1, 14, PRICE_CLOSE);
      if(slot.handle_RSI_H1 == INVALID_HANDLE)
      {
         PrintFormat("RPEA Indicators_Init: failed to create RSI14(H1) handle for %s (err=%d)",
                    slot.symbol, GetLastError());
      }
   }
}

// Refresh per-symbol derived stats and cache latest values
void Indicators_Refresh(const AppContext& ctx, const string symbol)
{
   int idx = Indicators_FindSlot(symbol);
   if(idx < 0)
      return;

   IndicatorSymbolSlot &slot = g_indicator_slots[idx];

   double value = 0.0;
   if(Indicators_CopyLatestValue(slot.handle_ATR_D1, value))
   {
      slot.atr_d1 = value;
      slot.has_atr = true;
   }
   else if(!slot.has_atr)
   {
      slot.atr_d1 = 0.0;
      slot.has_atr = false;
   }

   if(Indicators_CopyLatestValue(slot.handle_MA20_H1, value))
   {
      slot.ma20_h1 = value;
      slot.has_ma = true;
   }
   else if(!slot.has_ma)
   {
      slot.ma20_h1 = 0.0;
      slot.has_ma = false;
   }

   if(Indicators_CopyLatestValue(slot.handle_RSI_H1, value))
   {
      slot.rsi_h1 = value;
      slot.has_rsi = true;
   }
   else if(!slot.has_rsi)
   {
      slot.rsi_h1 = 0.0;
      slot.has_rsi = false;
   }

   // Copy yesterday's D1 OHLC (shift = 1)
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, PERIOD_D1, 0, 3, rates);
   if(copied >= 2)
   {
      slot.open_d1_prev = rates[1].open;
      slot.high_d1_prev = rates[1].high;
      slot.low_d1_prev  = rates[1].low;
      slot.close_d1_prev = rates[1].close;
      slot.has_ohlc = true;
   }
   else if(!slot.has_ohlc)
   {
      slot.open_d1_prev = 0.0;
      slot.high_d1_prev = 0.0;
      slot.low_d1_prev  = 0.0;
      slot.close_d1_prev = 0.0;
      slot.has_ohlc = false;
   }

   slot.last_refresh = TimeCurrent();
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

   const IndicatorSymbolSlot &slot = g_indicator_slots[idx];
   out_snapshot.atr_d1 = slot.atr_d1;
   out_snapshot.ma20_h1 = slot.ma20_h1;
   out_snapshot.rsi_h1 = slot.rsi_h1;
   out_snapshot.open_d1_prev = slot.open_d1_prev;
   out_snapshot.high_d1_prev = slot.high_d1_prev;
   out_snapshot.low_d1_prev = slot.low_d1_prev;
   out_snapshot.close_d1_prev = slot.close_d1_prev;
   out_snapshot.last_refresh = slot.last_refresh;
   out_snapshot.has_atr = slot.has_atr;
   out_snapshot.has_ma = slot.has_ma;
   out_snapshot.has_rsi = slot.has_rsi;
   out_snapshot.has_ohlc = slot.has_ohlc;
   return true;
}

#endif // INDICATORS_MQH
