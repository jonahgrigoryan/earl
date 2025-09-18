diff --git a/MQL5/Include/RPEA/scheduler.mqh b/MQL5/Include/RPEA/scheduler.mqh
index 697705a0b5e4d0a9ce9e040b5513c768f3467771..ed04afa4ca85e9a76489b7aacd466ee2c7beac40 100644
--- a/MQL5/Include/RPEA/scheduler.mqh
+++ b/MQL5/Include/RPEA/scheduler.mqh
@@ -1,45 +1,59 @@
 // scheduler.mqh - RPEA Scheduler Module
 // References: finalspec.md sections on "Scheduler (OnTimer 30–60s)" and "Data Flow & Sequence (per trading window)"
 #ifndef SCHEDULER_MQH
 #define SCHEDULER_MQH
 
 struct AppContext;
 
 // Main tick orchestrator (logging-only in M1)
 void Scheduler_Tick(const AppContext& ctx)
 {
    // 1) Equity rooms
    EquityRooms rooms = Equity_ComputeRooms(ctx);
    bool floors_ok = Equity_CheckFloors(ctx);
 
    // 2) Iterate symbols: news + sessions
    for(int i=0;i<ctx.symbols_count;i++)
    {
       string sym = ctx.symbols[i];
       if(sym=="") continue;
 
+      IndicatorSnapshot ind_snap;
+      Indicators_GetSnapshot(sym, ind_snap);
+      string ind_note = StringFormat(
+         "{\"symbol\":\"%s\",\"atr\":%.6f,\"ma20_h1\":%.6f,\"rsi_h1\":%.2f,\"has_atr\":%s,\"has_ma\":%s,\"has_rsi\":%s,\"has_ohlc\":%s}",
+         sym,
+         ind_snap.atr_d1,
+         ind_snap.ma20_h1,
+         ind_snap.rsi_h1,
+         ind_snap.has_atr?"true":"false",
+         ind_snap.has_ma?"true":"false",
+         ind_snap.has_rsi?"true":"false",
+         ind_snap.has_ohlc?"true":"false");
+      LogDecision("Indicators", "REFRESH", ind_note);
+
       bool news_blocked = News_IsBlocked(sym);
       bool spread_ok = Liquidity_SpreadOK(sym);
 
       // Session predicates (London/NY OR) and OR window
       bool in_london = Sessions_InLondon(ctx, sym);
       bool in_ny     = Sessions_InNewYork(ctx, sym);
       bool in_session = (in_london || in_ny) && !Sessions_CutoffReached(ctx, sym);
       bool in_or = Sessions_InORWindow(ctx, sym);
 
       string note = StringFormat("{\"news\":%s,\"spread\":%s,\"in_session\":%s,\"in_or\":%s}",
                                  news_blocked?"true":"false",
                                  spread_ok?"true":"false",
                                  in_session?"true":"false",
                                  in_or?"true":"false");
 
       if(!floors_ok || news_blocked || !spread_ok || !in_session)
       {
          LogDecision("Scheduler", "GATED", note);
          continue;
       }
 
       // 3) Signal proposals (stubs return none)
       bool bw_has=false, mr_has=false; string bw_setup="None", mr_setup="None";
       int bw_sl=0,bw_tp=0,mr_sl=0,mr_tp=0; double bw_bias=0,bw_conf=0,mr_bias=0,mr_conf=0;
 
