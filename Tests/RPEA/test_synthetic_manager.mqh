#ifndef TEST_SYNTHETIC_MANAGER_MQH
#define TEST_SYNTHETIC_MANAGER_MQH
// test_synthetic_manager.mqh - Unit tests for Task 11 Synthetic Manager

#include <RPEA/config.mqh>
#include <RPEA/indicators.mqh>

#ifndef TEST_FRAMEWORK_DEFINED
extern int g_test_passed;
extern int g_test_failed;
extern string g_current_test;

#define ASSERT_TRUE(condition, message) \
   do { \
      if(condition) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s", g_current_test, message); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s", g_current_test, message); \
      } \
   } while(false)

#define ASSERT_FALSE(condition, message) ASSERT_TRUE(!(condition), message)

#define ASSERT_DOUBLE_NEAR(expected, actual, epsilon, message) \
   do { \
      double __diff = MathAbs((expected) - (actual)); \
      if(__diff <= (epsilon)) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%.6f, actual=%.6f)", g_current_test, message, (expected), (actual)); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%.6f, actual=%.6f, diff=%.6f)", g_current_test, message, (expected), (actual), __diff); \
      } \
   } while(false)
#endif // TEST_FRAMEWORK_DEFINED

// Provide configuration globals for SyntheticManager in test environment
int  SyntheticBarCacheSize = DEFAULT_SyntheticBarCacheSize;
bool ForwardFillGaps       = DEFAULT_ForwardFillGaps;
int  MaxGapBars            = DEFAULT_MaxGapBars;
int  QuoteMaxAgeMs         = DEFAULT_QuoteMaxAgeMs;

// Stub storage ---------------------------------------------------------

MqlTick g_stub_tick_xau;
MqlTick g_stub_tick_eur;
bool    g_stub_tick_xau_set = false;
bool    g_stub_tick_eur_set = false;

MqlRates g_stub_rates_xau_m1[];
MqlRates g_stub_rates_eur_m1[];
MqlRates g_stub_rates_xau_h1[];
MqlRates g_stub_rates_eur_h1[];
MqlRates g_stub_rates_xau_d1[];
MqlRates g_stub_rates_eur_d1[];

void SyntheticTest_ClearRates()
{
   ArrayResize(g_stub_rates_xau_m1, 0);
   ArrayResize(g_stub_rates_eur_m1, 0);
   ArrayResize(g_stub_rates_xau_h1, 0);
   ArrayResize(g_stub_rates_eur_h1, 0);
   ArrayResize(g_stub_rates_xau_d1, 0);
   ArrayResize(g_stub_rates_eur_d1, 0);
}

void SyntheticTest_SetTick(const string symbol, const double bid, const double ask, const double last, const datetime tick_time)
{
   MqlTick tick = {0};
   tick.bid = bid;
   tick.ask = ask;
   tick.last = last;
   tick.time = tick_time;
   tick.flags = TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST;
   if(symbol == SYNTH_LEG_XAUUSD)
   {
      g_stub_tick_xau = tick;
      g_stub_tick_xau_set = true;
   }
   else if(symbol == SYNTH_LEG_EURUSD)
   {
      g_stub_tick_eur = tick;
      g_stub_tick_eur_set = true;
   }
}

MqlRates SyntheticTest_MakeRate(const datetime stamp,
                                const double open,
                                const double high,
                                const double low,
                                const double close,
                                const long tick_volume)
{
   MqlRates rate;
   rate.time = stamp;
   rate.open = open;
   rate.high = high;
   rate.low = low;
   rate.close = close;
   rate.tick_volume = tick_volume;
   rate.spread = 0;
   rate.real_volume = 0;
   return rate;
}

void SyntheticTest_StoreRates(MqlRates &target[], const MqlRates &source[], const int count)
{
   ArrayResize(target, count);
   for(int i=0;i<count;i++)
      target[i] = source[count - 1 - i]; // CopyRates series order (index 0 = latest)
}

void SyntheticTest_SetRates(const string symbol, const ENUM_TIMEFRAMES tf, const MqlRates &source[], const int count)
{
   if(symbol == SYNTH_LEG_XAUUSD)
   {
      if(tf == PERIOD_M1)
         SyntheticTest_StoreRates(g_stub_rates_xau_m1, source, count);
      else if(tf == PERIOD_H1)
         SyntheticTest_StoreRates(g_stub_rates_xau_h1, source, count);
      else if(tf == PERIOD_D1)
         SyntheticTest_StoreRates(g_stub_rates_xau_d1, source, count);
   }
   else if(symbol == SYNTH_LEG_EURUSD)
   {
      if(tf == PERIOD_M1)
         SyntheticTest_StoreRates(g_stub_rates_eur_m1, source, count);
      else if(tf == PERIOD_H1)
         SyntheticTest_StoreRates(g_stub_rates_eur_h1, source, count);
      else if(tf == PERIOD_D1)
         SyntheticTest_StoreRates(g_stub_rates_eur_d1, source, count);
   }
}

bool SyntheticTest_TickProvider(const string symbol, MqlTick &out_tick)
{
   if(symbol == SYNTH_LEG_XAUUSD && g_stub_tick_xau_set)
   {
      out_tick = g_stub_tick_xau;
      return true;
   }
   if(symbol == SYNTH_LEG_EURUSD && g_stub_tick_eur_set)
   {
      out_tick = g_stub_tick_eur;
      return true;
   }
   return false;
}

int SyntheticTest_CopySeries(const MqlRates &source[], MqlRates &dest[], const int count)
{
   int available = ArraySize(source);
   int to_copy = (count < available ? count : available);
   ArrayResize(dest, to_copy);
   for(int i=0;i<to_copy;i++)
      dest[i] = source[i];
   return to_copy;
}

int SyntheticTest_RatesProvider(const string symbol,
                                const ENUM_TIMEFRAMES timeframe,
                                const int start_pos,
                                const int requested,
                                MqlRates &rates[])
{
   // start_pos ignored in stub - always returns latest bars
   if(symbol == SYNTH_LEG_XAUUSD)
   {
      if(timeframe == PERIOD_M1)
         return SyntheticTest_CopySeries(g_stub_rates_xau_m1, rates, requested);
      if(timeframe == PERIOD_H1)
         return SyntheticTest_CopySeries(g_stub_rates_xau_h1, rates, requested);
      if(timeframe == PERIOD_D1)
         return SyntheticTest_CopySeries(g_stub_rates_xau_d1, rates, requested);
   }
   else if(symbol == SYNTH_LEG_EURUSD)
   {
      if(timeframe == PERIOD_M1)
         return SyntheticTest_CopySeries(g_stub_rates_eur_m1, rates, requested);
      if(timeframe == PERIOD_H1)
         return SyntheticTest_CopySeries(g_stub_rates_eur_h1, rates, requested);
      if(timeframe == PERIOD_D1)
         return SyntheticTest_CopySeries(g_stub_rates_eur_d1, rates, requested);
   }
   ArrayResize(rates, 0);
   return 0;
}

int SyntheticTest_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool SyntheticTest_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s", g_current_test);
   return ok;
}

void SyntheticTest_ResetEnvironment()
{
   g_stub_tick_xau_set = false;
   g_stub_tick_eur_set = false;
   SyntheticTest_ClearRates();
   g_synthetic_manager.Clear();
   g_synthetic_manager.ResetProviders();
   SyntheticBarCacheSize = DEFAULT_SyntheticBarCacheSize;
   ForwardFillGaps = DEFAULT_ForwardFillGaps;
   MaxGapBars = DEFAULT_MaxGapBars;
   QuoteMaxAgeMs = DEFAULT_QuoteMaxAgeMs;
}

// Test cases -----------------------------------------------------------

bool SyntheticPrice_ComputesXAUEUR()
{
   SyntheticTest_ResetEnvironment();
   int failures_before = SyntheticTest_Begin("SyntheticPrice_ComputesXAUEUR");

   datetime now = TimeCurrent();
   SyntheticTest_SetTick(SYNTH_LEG_XAUUSD, 2000.00, 2000.30, 2000.15, now);
   SyntheticTest_SetTick(SYNTH_LEG_EURUSD, 1.1000, 1.1003, 1.1001, now);
   g_synthetic_manager.SetTickProvider(SyntheticTest_TickProvider);

   double expected = 2000.15 / 1.1001;
   double price = g_synthetic_manager.GetSyntheticPrice(SYNTH_SYMBOL_XAUEUR, PRICE_CLOSE);
   ASSERT_DOUBLE_NEAR(expected, price, 1e-6, "XAUEUR price computed from ticks");

   SyntheticTest_ResetEnvironment();
   return SyntheticTest_End(failures_before);
}

bool SyntheticBars_BuildsWithForwardFill()
{
   SyntheticTest_ResetEnvironment();
   int failures_before = SyntheticTest_Begin("SyntheticBars_BuildsWithForwardFill");

   g_synthetic_manager.SetTickProvider(SyntheticTest_TickProvider);
   g_synthetic_manager.SetRatesProvider(SyntheticTest_RatesProvider);

   datetime base = TimeCurrent() - 120;
   MqlRates xau_rates[3];
   MqlRates eur_rates[2];

   xau_rates[0] = SyntheticTest_MakeRate(base, 2000, 2002, 1998, 2001, 100);
   xau_rates[1] = SyntheticTest_MakeRate(base + 60, 2001, 2004, 1999, 2003, 120);
   xau_rates[2] = SyntheticTest_MakeRate(base + 120, 2003, 2005, 2001, 2004, 110);

   eur_rates[0] = SyntheticTest_MakeRate(base, 1.10, 1.11, 1.09, 1.105, 90);
   eur_rates[1] = SyntheticTest_MakeRate(base + 120, 1.11, 1.12, 1.10, 1.115, 95);

   SyntheticTest_SetRates(SYNTH_LEG_XAUUSD, PERIOD_M1, xau_rates, 3);
   SyntheticTest_SetRates(SYNTH_LEG_EURUSD, PERIOD_M1, eur_rates, 2);

   bool built = g_synthetic_manager.BuildSyntheticBars(SYNTH_SYMBOL_XAUEUR, PERIOD_M1, 3);
   ASSERT_TRUE(built, "Build succeeds with forward fill");

   SyntheticBar bars[];
   ASSERT_TRUE(g_synthetic_manager.GetCachedBars(SYNTH_SYMBOL_XAUEUR, PERIOD_M1, bars, 3), "Cached bars retrieved");
   ASSERT_TRUE(ArraySize(bars) == 3, "Three synthetic bars returned");

   double expected_fill_close = xau_rates[1].close / eur_rates[0].close;
   ASSERT_DOUBLE_NEAR(expected_fill_close, bars[1].close, 1e-6, "Forward-filled bar uses previous EURUSD close");

   SyntheticTest_ResetEnvironment();
   return SyntheticTest_End(failures_before);
}

bool SyntheticBars_RejectsLargeGaps()
{
   SyntheticTest_ResetEnvironment();
   int failures_before = SyntheticTest_Begin("SyntheticBars_RejectsLargeGaps");

   g_synthetic_manager.SetRatesProvider(SyntheticTest_RatesProvider);

   MaxGapBars = 1;

   datetime base = TimeCurrent() - 180;
   MqlRates xau_rates[3];
   MqlRates eur_rates[2];

   xau_rates[0] = SyntheticTest_MakeRate(base, 2000, 2001, 1999, 2000.5, 80);
   xau_rates[1] = SyntheticTest_MakeRate(base + 60, 2000.5, 2001.5, 1999.5, 2001, 85);
   xau_rates[2] = SyntheticTest_MakeRate(base + 120, 2001, 2002, 2000, 2001.5, 90);

   eur_rates[0] = SyntheticTest_MakeRate(base, 1.10, 1.11, 1.09, 1.105, 70);
   eur_rates[1] = SyntheticTest_MakeRate(base + 180, 1.12, 1.13, 1.11, 1.125, 75);

   SyntheticTest_SetRates(SYNTH_LEG_XAUUSD, PERIOD_M1, xau_rates, 3);
   SyntheticTest_SetRates(SYNTH_LEG_EURUSD, PERIOD_M1, eur_rates, 2);

   bool built = g_synthetic_manager.BuildSyntheticBars(SYNTH_SYMBOL_XAUEUR, PERIOD_M1, 3);
   ASSERT_FALSE(built, "Build fails when gap exceeds MaxGapBars");

   SyntheticTest_ResetEnvironment();
   return SyntheticTest_End(failures_before);
}

bool SyntheticQuotes_StalenessCheck()
{
   SyntheticTest_ResetEnvironment();
   int failures_before = SyntheticTest_Begin("SyntheticQuotes_StalenessCheck");

   g_synthetic_manager.SetTickProvider(SyntheticTest_TickProvider);

   datetime now = TimeCurrent();
   SyntheticTest_SetTick(SYNTH_LEG_XAUUSD, 2000, 2000.2, 2000.1, now - 20);
   SyntheticTest_SetTick(SYNTH_LEG_EURUSD, 1.10, 1.1002, 1.1001, now - 20);

   QuoteMaxAgeMs = 5000;
   bool stale = g_synthetic_manager.AreQuotesStale(SYNTH_LEG_XAUUSD, SYNTH_LEG_EURUSD);
   ASSERT_TRUE(stale, "Quotes older than threshold reported stale");

   SyntheticTest_SetTick(SYNTH_LEG_XAUUSD, 2000, 2000.2, 2000.1, now);
   SyntheticTest_SetTick(SYNTH_LEG_EURUSD, 1.10, 1.1002, 1.1001, now);
   stale = g_synthetic_manager.AreQuotesStale(SYNTH_LEG_XAUUSD, SYNTH_LEG_EURUSD);
   ASSERT_FALSE(stale, "Fresh quotes pass staleness check");

   SyntheticTest_ResetEnvironment();
   return SyntheticTest_End(failures_before);
}

bool SyntheticCache_ReusesData()
{
   SyntheticTest_ResetEnvironment();
   int failures_before = SyntheticTest_Begin("SyntheticCache_ReusesData");

   g_synthetic_manager.SetRatesProvider(SyntheticTest_RatesProvider);

   datetime base = TimeCurrent() - 60;
   MqlRates xau_initial[2];
   MqlRates eur_initial[2];

   xau_initial[0] = SyntheticTest_MakeRate(base - 60, 2000, 2001, 1999, 2000.2, 50);
   xau_initial[1] = SyntheticTest_MakeRate(base, 2000.2, 2001.2, 1999.8, 2000.6, 55);
   eur_initial[0] = SyntheticTest_MakeRate(base - 60, 1.10, 1.11, 1.09, 1.105, 40);
   eur_initial[1] = SyntheticTest_MakeRate(base, 1.105, 1.115, 1.095, 1.11, 45);

   SyntheticTest_SetRates(SYNTH_LEG_XAUUSD, PERIOD_M1, xau_initial, 2);
   SyntheticTest_SetRates(SYNTH_LEG_EURUSD, PERIOD_M1, eur_initial, 2);

   ASSERT_TRUE(g_synthetic_manager.BuildSyntheticBars(SYNTH_SYMBOL_XAUEUR, PERIOD_M1, 2), "Initial build succeeds");

   SyntheticBar cached[];
   ASSERT_TRUE(g_synthetic_manager.GetCachedBars(SYNTH_SYMBOL_XAUEUR, PERIOD_M1, cached, 2), "Cached bars retrieved");
   double first_close = cached[1].close;

   // Modify underlying data but do not rebuild
   xau_initial[0].close = 2100.0;
   xau_initial[1].close = 2110.0;
   SyntheticTest_SetRates(SYNTH_LEG_XAUUSD, PERIOD_M1, xau_initial, 2);

   SyntheticBar cached_again[];
   ASSERT_TRUE(g_synthetic_manager.GetCachedBars(SYNTH_SYMBOL_XAUEUR, PERIOD_M1, cached_again, 2), "Cache reused before rebuild");
   ASSERT_DOUBLE_NEAR(first_close, cached_again[1].close, 1e-6, "Cache returned old synthetic values");

   ASSERT_TRUE(g_synthetic_manager.BuildSyntheticBars(SYNTH_SYMBOL_XAUEUR, PERIOD_M1, 2), "Rebuild after data change");
   ASSERT_TRUE(g_synthetic_manager.GetCachedBars(SYNTH_SYMBOL_XAUEUR, PERIOD_M1, cached_again, 2), "Cache updated after rebuild");
   ASSERT_TRUE(MathAbs(first_close - cached_again[1].close) > 1e-4, "Rebuild refreshed cached values");

   SyntheticTest_ResetEnvironment();
   return SyntheticTest_End(failures_before);
}

bool SyntheticDistance_ScalesWithEURUSD()
{
   SyntheticTest_ResetEnvironment();
   int failures_before = SyntheticTest_Begin("SyntheticDistance_ScalesWithEURUSD");

   double scaled = g_synthetic_manager.ScaleSyntheticDistance(50.0, 1.08);
   ASSERT_DOUBLE_NEAR(54.0, scaled, 1e-6, "Distance scaling multiplies by EURUSD rate");

   SyntheticTest_ResetEnvironment();
   return SyntheticTest_End(failures_before);
}

bool SyntheticBWISC_IndicatorCompatibility()
{
   SyntheticTest_ResetEnvironment();
   int failures_before = SyntheticTest_Begin("SyntheticBWISC_IndicatorCompatibility");

   g_synthetic_manager.SetRatesProvider(SyntheticTest_RatesProvider);

   const int daily_count = 16;
   MqlRates xau_d1[daily_count];
   MqlRates eur_d1[daily_count];
   datetime now = TimeCurrent();
   datetime day_base = now - daily_count * 86400;
   for(int i=0;i<daily_count;i++)
   {
      double x_price = 2000.0 + i*2.0;
      double e_price = 1.10 + i*0.001;
      datetime stamp = day_base + i*86400;
      xau_d1[i] = SyntheticTest_MakeRate(stamp, x_price, x_price + 5.0, x_price - 5.0, x_price + 2.0, 100 + i);
      eur_d1[i] = SyntheticTest_MakeRate(stamp, e_price, e_price + 0.002, e_price - 0.002, e_price + 0.001, 90 + i);
   }

   const int hourly_count = 30;
   MqlRates xau_h1[hourly_count];
   MqlRates eur_h1[hourly_count];
   datetime hour_base = now - hourly_count * 3600;
   for(int j=0;j<hourly_count;j++)
   {
      double x_price_h = 2000.0 + j * 0.5;
      double e_price_h = 1.10 + j * 0.0005;
      datetime stamp = hour_base + j*3600;
      xau_h1[j] = SyntheticTest_MakeRate(stamp, x_price_h, x_price_h + 1.0, x_price_h - 1.0, x_price_h + 0.25, 60 + j);
      eur_h1[j] = SyntheticTest_MakeRate(stamp, e_price_h, e_price_h + 0.001, e_price_h - 0.001, e_price_h + 0.0004, 50 + j);
   }

   SyntheticTest_SetRates(SYNTH_LEG_XAUUSD, PERIOD_D1, xau_d1, daily_count);
   SyntheticTest_SetRates(SYNTH_LEG_EURUSD, PERIOD_D1, eur_d1, daily_count);
   SyntheticTest_SetRates(SYNTH_LEG_XAUUSD, PERIOD_H1, xau_h1, hourly_count);
   SyntheticTest_SetRates(SYNTH_LEG_EURUSD, PERIOD_H1, eur_h1, hourly_count);

   IndicatorSymbolSlot slot;
   slot.symbol = SYNTH_SYMBOL_XAUEUR;
   slot.has_atr = false;
   slot.has_ma = false;
   slot.has_rsi = false;
   slot.has_ohlc = false;

   bool ok = Indicators_RefreshSyntheticXAUEURSlot(slot);
   ASSERT_TRUE(ok, "Synthetic indicator refresh succeeded");
   ASSERT_TRUE(slot.has_atr, "ATR computed for synthetic bars");
   ASSERT_TRUE(slot.has_ma, "EMA computed for synthetic bars");
   ASSERT_TRUE(slot.has_rsi, "RSI computed for synthetic bars");
   ASSERT_TRUE(slot.has_ohlc, "Previous D1 OHLC available");

   SyntheticTest_ResetEnvironment();
   return SyntheticTest_End(failures_before);
}

bool TestSyntheticManager_RunAll()
{
   bool all_passed = true;
   all_passed &= SyntheticPrice_ComputesXAUEUR();
   all_passed &= SyntheticBars_BuildsWithForwardFill();
   all_passed &= SyntheticBars_RejectsLargeGaps();
   all_passed &= SyntheticQuotes_StalenessCheck();
   all_passed &= SyntheticCache_ReusesData();
   all_passed &= SyntheticDistance_ScalesWithEURUSD();
   all_passed &= SyntheticBWISC_IndicatorCompatibility();
   return all_passed;
}

#endif // TEST_SYNTHETIC_MANAGER_MQH
