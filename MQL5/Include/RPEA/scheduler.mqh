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

      Indicators_Refresh(ctx, sym);

      IndicatorSnapshot ind_snap;
      Indicators_GetSnapshot(sym, ind_snap);
      string ind_note = StringFormat(
         "{\"symbol\":\"%s\",\"atr\":%.6f,\"ma20_h1\":%.6f,\"rsi_h1\":%.2f,\"has_atr\":%s,\"has_ma\":%s,\"has_rsi\":%s,\"has_ohlc\":%s}",
         sym,
         ind_snap.atr_d1,
         ind_snap.ma20_h1,
         ind_snap.rsi_h1,
         ind_snap.has_atr?"true":"false",
         ind_snap.has_ma?"true":"false",
         ind_snap.has_rsi?"true":"false",
         ind_snap.has_ohlc?"true":"false");
      LogDecision("Indicators", "SNAPSHOT", ind_note);
      bool news_blocked = News_IsBlocked(sym);

      // Task 22: ATR-based spread filtering with detailed output
      double spread_val = 0.0;
      double spread_thresh = 0.0;
      bool spread_ok = Liquidity_SpreadOK(sym, spread_val, spread_thresh);

      // Session predicates (London/NY OR) and OR window
      bool in_london = Sessions_InLondon(ctx, sym);
      bool in_ny     = Sessions_InNewYork(ctx, sym);
      bool in_session = (in_london || in_ny) && !Sessions_CutoffReached(ctx, sym);
      bool in_or = Sessions_InORWindow(ctx, sym);

      string note = StringFormat("{\"news\":%s,\"spread_ok\":%s,\"spread\":%.5f,\"spread_thresh\":%.5f,\"in_session\":%s,\"in_or\":%s}",
                                 news_blocked?"true":"false",
                                 spread_ok?"true":"false",
                                 spread_val,
                                 spread_thresh,
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

      SignalsBWISC_Propose(ctx, sym, bw_has, bw_setup, bw_sl, bw_tp, bw_bias, bw_conf);
      SignalsMR_Propose(ctx, sym, mr_has, mr_setup, mr_sl, mr_tp, mr_bias, mr_conf);

      // 4) Meta-policy
      string choice = MetaPolicy_Choose(bw_has, bw_conf, mr_has, mr_conf);

      // 5) Allocator plan (no-op)
      int slPoints = (choice=="BWISC")?bw_sl:mr_sl;
      int tpPoints = (choice=="BWISC")?bw_tp:mr_tp;
      double conf  = (choice=="BWISC")?bw_conf:mr_conf;
      OrderPlan plan = Allocator_BuildOrderPlan(ctx, choice, sym, slPoints, tpPoints, conf);

      // 6) Log decision only
      string fields = StringFormat("{\"symbol\":\"%s\",\"choice\":\"%s\",\"bw_conf\":%.2f,\"mr_conf\":%.2f}", sym, choice, bw_conf, mr_conf);
      LogDecision("Scheduler", "EVAL", fields);
   }

   // Heartbeat audit
   LogAuditRow("SCHED_TICK", "Scheduler", 1, "heartbeat", "{}");
}

#endif // SCHEDULER_MQH
