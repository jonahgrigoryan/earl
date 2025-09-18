diff --git a/MQL5/Include/RPEA/indicators.mqh b/MQL5/Include/RPEA/indicators.mqh
index eb8cb346169224e43deb6e08ef8c4ea24a578139..5bbd656d66a547506d2795f0c14b54ad97cd5822 100644
--- a/MQL5/Include/RPEA/indicators.mqh
+++ b/MQL5/Include/RPEA/indicators.mqh
@@ -1,27 +1,331 @@
 #ifndef INDICATORS_MQH
 #define INDICATORS_MQH
-// indicators.mqh - Indicator handles and init (M1 stubs)
+// indicators.mqh - Indicator handles and init (M2 implementation)
 // References: finalspec.md (Session Statistics)
 
 struct AppContext;
 
-struct IndicatorsContext
+// Snapshot of indicator values available to downstream modules
+struct IndicatorSnapshot
 {
-   int handle_ATR_D1;
-   int handle_MA20_H1;
-   int handle_RSI_H1;
+   double atr_d1;
+   double ma20_h1;
+   double rsi_h1;
+   double open_d1_prev;
+   double high_d1_prev;
+   double low_d1_prev;
+   double close_d1_prev;
+   bool   has_atr;
+   bool   has_ma;
+   bool   has_rsi;
+   bool   has_d1;
 };
 
-// Initialize indicator handles (placeholders)
+// Internal per-symbol context
+struct IndicatorSymbolContext
+{
+   string symbol;
+   int    handle_atr_d1;
+   int    handle_ma20_h1;
+   int    handle_rsi_h1;
+   double atr_d1;
+   double ma20_h1;
+   double rsi_h1;
+   double open_d1_prev;
+   double high_d1_prev;
+   double low_d1_prev;
+   double close_d1_prev;
+   bool   has_atr;
+   bool   has_ma;
+   bool   has_rsi;
+   bool   has_d1;
+};
+
+// Internal store (mirrors ctx.symbols)
+static IndicatorSymbolContext g_indicator_symbols[];
+
+// Helper: clear cached values
+void Indicators_ResetValues(IndicatorSymbolContext &slot)
+{
+   slot.atr_d1 = 0.0;
+   slot.ma20_h1 = 0.0;
+   slot.rsi_h1 = 0.0;
+   slot.open_d1_prev = 0.0;
+   slot.high_d1_prev = 0.0;
+   slot.low_d1_prev = 0.0;
+   slot.close_d1_prev = 0.0;
+   slot.has_atr = false;
+   slot.has_ma = false;
+   slot.has_rsi = false;
+   slot.has_d1 = false;
+}
+
+// Helper: locate symbol index
+int Indicators_FindIndex(const string symbol)
+{
+   int total = ArraySize(g_indicator_symbols);
+   for(int i=0;i<total;i++)
+   {
+      if(g_indicator_symbols[i].symbol == symbol)
+         return i;
+   }
+   return -1;
+}
+
+// Helper: ensure handles exist for a slot (called on init/refresh)
+void Indicators_EnsureHandles(IndicatorSymbolContext &slot)
+{
+   if(slot.handle_atr_d1 == INVALID_HANDLE)
+   {
+      ResetLastError();
+      slot.handle_atr_d1 = iATR(slot.symbol, PERIOD_D1, 14);
+      if(slot.handle_atr_d1 == INVALID_HANDLE)
+      {
+         int err = GetLastError();
+         if(err != 0)
+            PrintFormat("RPEA Indicators: failed to create ATR(D1) handle for %s (err=%d)", slot.symbol, err);
+      }
+   }
+   if(slot.handle_ma20_h1 == INVALID_HANDLE)
+   {
+      ResetLastError();
+      slot.handle_ma20_h1 = iMA(slot.symbol, PERIOD_H1, 20, 0, MODE_EMA, PRICE_CLOSE);
+      if(slot.handle_ma20_h1 == INVALID_HANDLE)
+      {
+         int err = GetLastError();
+         if(err != 0)
+            PrintFormat("RPEA Indicators: failed to create EMA20(H1) handle for %s (err=%d)", slot.symbol, err);
+      }
+   }
+   if(slot.handle_rsi_h1 == INVALID_HANDLE)
+   {
+      ResetLastError();
+      slot.handle_rsi_h1 = iRSI(slot.symbol, PERIOD_H1, 14, PRICE_CLOSE);
+      if(slot.handle_rsi_h1 == INVALID_HANDLE)
+      {
+         int err = GetLastError();
+         if(err != 0)
+            PrintFormat("RPEA Indicators: failed to create RSI14(H1) handle for %s (err=%d)", slot.symbol, err);
+      }
+   }
+}
+
+// Initialize indicator handles per symbol
 void Indicators_Init(const AppContext& ctx)
 {
-   // TODO[M2]: create real handles, error handling
+   // Release previous handles if any (safety for re-init)
+   int existing = ArraySize(g_indicator_symbols);
+   for(int i=0;i<existing;i++)
+   {
+      if(g_indicator_symbols[i].handle_atr_d1 != INVALID_HANDLE)
+         IndicatorRelease(g_indicator_symbols[i].handle_atr_d1);
+      if(g_indicator_symbols[i].handle_ma20_h1 != INVALID_HANDLE)
+         IndicatorRelease(g_indicator_symbols[i].handle_ma20_h1);
+      if(g_indicator_symbols[i].handle_rsi_h1 != INVALID_HANDLE)
+         IndicatorRelease(g_indicator_symbols[i].handle_rsi_h1);
+   }
+   ArrayResize(g_indicator_symbols, 0);
+
+   for(int i=0;i<ctx.symbols_count;i++)
+   {
+      string sym = ctx.symbols[i];
+      if(sym == "")
+         continue;
+
+      int idx = ArraySize(g_indicator_symbols);
+      ArrayResize(g_indicator_symbols, idx+1);
+      g_indicator_symbols[idx].symbol = sym;
+      g_indicator_symbols[idx].handle_atr_d1 = INVALID_HANDLE;
+      g_indicator_symbols[idx].handle_ma20_h1 = INVALID_HANDLE;
+      g_indicator_symbols[idx].handle_rsi_h1 = INVALID_HANDLE;
+      Indicators_ResetValues(g_indicator_symbols[idx]);
+      Indicators_EnsureHandles(g_indicator_symbols[idx]);
+   }
 }
 
-// Refresh per-symbol derived stats (placeholders)
+// Refresh per-symbol derived stats (ATR/EMA/RSI and yesterday D1 OHLC)
 void Indicators_Refresh(const AppContext& ctx, const string symbol)
 {
-   // TODO[M2]: compute OR, ATR, RSI; handle errors
+   int idx = Indicators_FindIndex(symbol);
+   if(idx < 0)
+      return;
+
+   IndicatorSymbolContext &slot = g_indicator_symbols[idx];
+   Indicators_EnsureHandles(slot);
+
+   // ATR D1
+   slot.has_atr = false;
+   if(slot.handle_atr_d1 != INVALID_HANDLE)
+   {
+      double values[];
+      ResetLastError();
+      int copied = CopyBuffer(slot.handle_atr_d1, 0, 0, 1, values);
+      if(copied > 0 && ArraySize(values) > 0)
+      {
+         double val = values[0];
+         if(MathIsValidNumber(val) && val != EMPTY_VALUE)
+         {
+            slot.atr_d1 = val;
+            slot.has_atr = true;
+         }
+      }
+   }
+   if(!slot.has_atr)
+      slot.atr_d1 = 0.0;
+
+   // EMA20 H1
+   slot.has_ma = false;
+   if(slot.handle_ma20_h1 != INVALID_HANDLE)
+   {
+      double values[];
+      ResetLastError();
+      int copied = CopyBuffer(slot.handle_ma20_h1, 0, 0, 1, values);
+      if(copied > 0 && ArraySize(values) > 0)
+      {
+         double val = values[0];
+         if(MathIsValidNumber(val) && val != EMPTY_VALUE)
+         {
+            slot.ma20_h1 = val;
+            slot.has_ma = true;
+         }
+      }
+   }
+   if(!slot.has_ma)
+      slot.ma20_h1 = 0.0;
+
+   // RSI14 H1
+   slot.has_rsi = false;
+   if(slot.handle_rsi_h1 != INVALID_HANDLE)
+   {
+      double values[];
+      ResetLastError();
+      int copied = CopyBuffer(slot.handle_rsi_h1, 0, 0, 1, values);
+      if(copied > 0 && ArraySize(values) > 0)
+      {
+         double val = values[0];
+         if(MathIsValidNumber(val) && val != EMPTY_VALUE)
+         {
+            slot.rsi_h1 = val;
+            slot.has_rsi = true;
+         }
+      }
+   }
+   if(!slot.has_rsi)
+      slot.rsi_h1 = 0.0;
+
+   // Yesterday's D1 OHLC
+   slot.has_d1 = false;
+   MqlRates rates[];
+   ResetLastError();
+   int copied_rates = CopyRates(slot.symbol, PERIOD_D1, 1, 1, rates);
+   if(copied_rates > 0 && ArraySize(rates) > 0)
+   {
+      slot.open_d1_prev = rates[0].open;
+      slot.high_d1_prev = rates[0].high;
+      slot.low_d1_prev  = rates[0].low;
+      slot.close_d1_prev = rates[0].close;
+      slot.has_d1 = (MathIsValidNumber(slot.open_d1_prev) &&
+                     MathIsValidNumber(slot.high_d1_prev) &&
+                     MathIsValidNumber(slot.low_d1_prev) &&
+                     MathIsValidNumber(slot.close_d1_prev));
+      if(!slot.has_d1)
+      {
+         slot.open_d1_prev = 0.0;
+         slot.high_d1_prev = 0.0;
+         slot.low_d1_prev = 0.0;
+         slot.close_d1_prev = 0.0;
+      }
+   }
+   else
+   {
+      slot.open_d1_prev = 0.0;
+      slot.high_d1_prev = 0.0;
+      slot.low_d1_prev = 0.0;
+      slot.close_d1_prev = 0.0;
+   }
+}
+
+// Accessors
+double Indicators_ATR_D1(const string symbol)
+{
+   int idx = Indicators_FindIndex(symbol);
+   if(idx < 0)
+      return 0.0;
+   return g_indicator_symbols[idx].atr_d1;
+}
+
+double Indicators_MA20_H1(const string symbol)
+{
+   int idx = Indicators_FindIndex(symbol);
+   if(idx < 0)
+      return 0.0;
+   return g_indicator_symbols[idx].ma20_h1;
+}
+
+double Indicators_RSI_H1(const string symbol)
+{
+   int idx = Indicators_FindIndex(symbol);
+   if(idx < 0)
+      return 0.0;
+   return g_indicator_symbols[idx].rsi_h1;
+}
+
+bool Indicators_GetD1Previous(const string symbol,
+                              double &open_price,
+                              double &high_price,
+                              double &low_price,
+                              double &close_price)
+{
+   int idx = Indicators_FindIndex(symbol);
+   if(idx < 0)
+   {
+      open_price = 0.0;
+      high_price = 0.0;
+      low_price = 0.0;
+      close_price = 0.0;
+      return false;
+   }
+
+   IndicatorSymbolContext &slot = g_indicator_symbols[idx];
+   open_price = slot.open_d1_prev;
+   high_price = slot.high_d1_prev;
+   low_price = slot.low_d1_prev;
+   close_price = slot.close_d1_prev;
+   return slot.has_d1;
+}
+
+bool Indicators_GetSnapshot(const string symbol, IndicatorSnapshot &snapshot)
+{
+   int idx = Indicators_FindIndex(symbol);
+   if(idx < 0)
+   {
+      snapshot.atr_d1 = 0.0;
+      snapshot.ma20_h1 = 0.0;
+      snapshot.rsi_h1 = 0.0;
+      snapshot.open_d1_prev = 0.0;
+      snapshot.high_d1_prev = 0.0;
+      snapshot.low_d1_prev = 0.0;
+      snapshot.close_d1_prev = 0.0;
+      snapshot.has_atr = false;
+      snapshot.has_ma = false;
+      snapshot.has_rsi = false;
+      snapshot.has_d1 = false;
+      return false;
+   }
+
+   IndicatorSymbolContext &slot = g_indicator_symbols[idx];
+   snapshot.atr_d1 = slot.atr_d1;
+   snapshot.ma20_h1 = slot.ma20_h1;
+   snapshot.rsi_h1 = slot.rsi_h1;
+   snapshot.open_d1_prev = slot.open_d1_prev;
+   snapshot.high_d1_prev = slot.high_d1_prev;
+   snapshot.low_d1_prev = slot.low_d1_prev;
+   snapshot.close_d1_prev = slot.close_d1_prev;
+   snapshot.has_atr = slot.has_atr;
+   snapshot.has_ma = slot.has_ma;
+   snapshot.has_rsi = slot.has_rsi;
+   snapshot.has_d1 = slot.has_d1;
+   return true;
 }
 
 #endif // INDICATORS_MQH
