#ifndef INDICATORS_MQH
#define INDICATORS_MQH
// indicators.mqh - Indicator handles and init (M1 stubs)
// References: finalspec.md (Session Statistics)

#include <RPEA/synthetic.mqh>

struct AppContext;

struct IndicatorsContext
{
   int handle_ATR_D1;
   int handle_MA20_H1;
   int handle_RSI_H1;
};

// Storage structure for per-symbol indicator data
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

// Snapshot structure for consumers
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

// Static storage sized by Symbols list during init
IndicatorSymbolSlot g_indicator_slots[];

bool Indicators_GetSyntheticBars(const ENUM_TIMEFRAMES tf, const int count, SyntheticBar &out[])
{
   if(count <= 0)
      return false;

   if(g_synthetic_manager.GetCachedBars(SYNTH_SYMBOL_XAUEUR, tf, out, count))
      return true;

   if(!g_synthetic_manager.BuildSyntheticBars(SYNTH_SYMBOL_XAUEUR, tf, count))
      return false;

   return g_synthetic_manager.GetCachedBars(SYNTH_SYMBOL_XAUEUR, tf, out, count);
}

double Indicators_ComputeATRFromBars(const SyntheticBar &bars[], const int count, const int period)
{
   if(period <= 0 || count <= period)
      return 0.0;

   double sum = 0.0;
   for(int i=count - period;i<count;i++)
   {
      int prev = i - 1;
      if(prev < 0)
         return 0.0;
      double high = bars[i].high;
      double low = bars[i].low;
      double prev_close = bars[prev].close;
      double tr1 = high - low;
      double tr2 = MathAbs(high - prev_close);
      double tr3 = MathAbs(low - prev_close);
      double tr = MathMax(tr1, MathMax(tr2, tr3));
      sum += tr;
   }

   return sum / period;
}

double Indicators_ComputeEMAFromBars(const SyntheticBar &bars[], const int count, const int period)
{
   if(period <= 0 || count < period)
      return 0.0;

   double multiplier = 2.0 / (period + 1.0);
   int start = count - period;

   double ema = 0.0;
   for(int i=start;i<count;i++)
      ema += bars[i].close;
   ema /= (double)period;

   for(int j=start + 1;j<count;j++)
   {
      double price = bars[j].close;
      ema = (price - ema) * multiplier + ema;
   }

   return ema;
}

double Indicators_ComputeRSIFromBars(const SyntheticBar &bars[], const int count, const int period)
{
   if(period <= 0 || count <= period)
      return 0.0;

   double gain = 0.0;
   double loss = 0.0;
   int start = count - period;

   for(int i=start;i<count;i++)
   {
      int prev = i - 1;
      if(prev < 0)
         continue;
      double change = bars[i].close - bars[prev].close;
      if(change > 0.0)
         gain += change;
      else
         loss -= change;
   }

   gain /= (double)period;
   loss /= (double)period;

   if(loss == 0.0)
      return 100.0;
   if(gain == 0.0)
      return 0.0;

   double rs = gain / loss;
   return 100.0 - (100.0 / (1.0 + rs));
}

bool Indicators_RefreshSyntheticXAUEURSlot(IndicatorSymbolSlot &slot)
{
   const int daily_period = 14;
   const int daily_required = daily_period + 1;
   SyntheticBar daily_bars[];

   if(!Indicators_GetSyntheticBars(PERIOD_D1, daily_required, daily_bars))
   {
      Print("[Synthetic] XAUEUR unavailable (D1 bars)");
      slot.atr_d1 = 0.0;
      slot.has_atr = false;
      slot.open_d1_prev = 0.0;
      slot.high_d1_prev = 0.0;
      slot.low_d1_prev = 0.0;
      slot.close_d1_prev = 0.0;
      slot.has_ohlc = false;
      return false;
   }

   int daily_count = ArraySize(daily_bars);
   slot.atr_d1 = Indicators_ComputeATRFromBars(daily_bars, daily_count, daily_period);
   slot.has_atr = (slot.atr_d1 > 0.0);

   if(daily_count >= 2)
   {
      int prev_idx = daily_count - 2;
      slot.open_d1_prev = daily_bars[prev_idx].open;
      slot.high_d1_prev = daily_bars[prev_idx].high;
      slot.low_d1_prev = daily_bars[prev_idx].low;
      slot.close_d1_prev = daily_bars[prev_idx].close;
      slot.has_ohlc = true;
   }
   else
   {
      slot.open_d1_prev = 0.0;
      slot.high_d1_prev = 0.0;
      slot.low_d1_prev = 0.0;
      slot.close_d1_prev = 0.0;
      slot.has_ohlc = false;
   }

   const int ma_period = 20;
   const int rsi_period = 14;
   int hourly_required = MathMax(ma_period, rsi_period) + 10;
   SyntheticBar hourly_bars[];

   if(!Indicators_GetSyntheticBars(PERIOD_H1, hourly_required, hourly_bars))
   {
      Print("[Synthetic] XAUEUR unavailable (H1 bars)");
      slot.ma20_h1 = 0.0;
      slot.has_ma = false;
      slot.rsi_h1 = 0.0;
      slot.has_rsi = false;
      return false;
   }

   int hourly_count = ArraySize(hourly_bars);
   slot.ma20_h1 = Indicators_ComputeEMAFromBars(hourly_bars, hourly_count, ma_period);
   slot.has_ma = (slot.ma20_h1 > 0.0);

   slot.rsi_h1 = Indicators_ComputeRSIFromBars(hourly_bars, hourly_count, rsi_period);
   slot.has_rsi = (slot.rsi_h1 >= 0.0 && slot.rsi_h1 <= 100.0);

   slot.last_refresh = TimeCurrent();
   return (slot.has_atr && slot.has_ma && slot.has_rsi && slot.has_ohlc);
}

// Helper: release indicator handles for a slot index
void Indicators_ReleaseSlot(const int idx)
{
   if(idx < 0 || idx >= ArraySize(g_indicator_slots))
      return;

   if(g_indicator_slots[idx].handle_ATR_D1 != INVALID_HANDLE)
   {
      IndicatorRelease(g_indicator_slots[idx].handle_ATR_D1);
      g_indicator_slots[idx].handle_ATR_D1 = INVALID_HANDLE;
   }
   if(g_indicator_slots[idx].handle_MA20_H1 != INVALID_HANDLE)
   {
      IndicatorRelease(g_indicator_slots[idx].handle_MA20_H1);
      g_indicator_slots[idx].handle_MA20_H1 = INVALID_HANDLE;
   }
   if(g_indicator_slots[idx].handle_RSI_H1 != INVALID_HANDLE)
   {
      IndicatorRelease(g_indicator_slots[idx].handle_RSI_H1);
      g_indicator_slots[idx].handle_RSI_H1 = INVALID_HANDLE;
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
void Indicators_Init(const AppContext &ctx)
{
   // Release any existing handles before reinitializing
   int existing = ArraySize(g_indicator_slots);
   for(int i=0;i<existing;i++)
   {
      Indicators_ReleaseSlot(i);
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

        if(g_indicator_slots[i].symbol == SYNTH_SYMBOL_XAUEUR)
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
void Indicators_Refresh(const AppContext &ctx, const string symbol)
{
   if(ctx.symbols_count <= 0)
      return;
   int idx = Indicators_FindSlot(symbol);
   if(idx < 0)
      return;

    if(symbol == SYNTH_SYMBOL_XAUEUR)
    {
       if(!Indicators_RefreshSyntheticXAUEURSlot(g_indicator_slots[idx]))
          Print("[Synthetic] XAUEUR unavailable for indicator refresh");
       return;
    }

   double value = 0.0;
   if(Indicators_CopyLatestValue(g_indicator_slots[idx].handle_ATR_D1, value))
   {
      g_indicator_slots[idx].atr_d1 = value;
      g_indicator_slots[idx].has_atr = true;
   }
   else
   {
      g_indicator_slots[idx].atr_d1 = 0.0;
      g_indicator_slots[idx].has_atr = false;
   }

   if(Indicators_CopyLatestValue(g_indicator_slots[idx].handle_MA20_H1, value))
   {
      g_indicator_slots[idx].ma20_h1 = value;
      g_indicator_slots[idx].has_ma = true;
   }
   else
   {
      g_indicator_slots[idx].ma20_h1 = 0.0;
      g_indicator_slots[idx].has_ma = false;
   }

   if(Indicators_CopyLatestValue(g_indicator_slots[idx].handle_RSI_H1, value))
   {
      g_indicator_slots[idx].rsi_h1 = value;
      g_indicator_slots[idx].has_rsi = true;
   }
   else
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
   else
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