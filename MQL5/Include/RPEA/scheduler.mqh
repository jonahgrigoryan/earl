// scheduler.mqh - RPEA Scheduler Module
// References: finalspec.md sections on "Scheduler (OnTimer 30–60s)" and "Data Flow & Sequence (per trading window)"
#ifndef SCHEDULER_MQH
#define SCHEDULER_MQH

#include <RPEA/config.mqh>

struct AppContext;

//------------------------------------------------------------------------------
// M6-Task04: Performance Profiling State (module-scoped)
//------------------------------------------------------------------------------

struct SchedulerPerfStats
{
   ulong    total_ticks;
   ulong    total_us;
   ulong    max_us;
   datetime last_report_time;
   int      report_interval_sec;
};

SchedulerPerfStats g_sched_perf = {0, 0, 0, 0, 30};

void Scheduler_ReportPerfStats()
{
   if(g_sched_perf.total_ticks == 0)
      return;
   ulong avg_us = g_sched_perf.total_us / g_sched_perf.total_ticks;
   PrintFormat("[Perf] Scheduler: ticks=%llu avg=%lluus max=%lluus",
               g_sched_perf.total_ticks, avg_us, g_sched_perf.max_us);
   g_sched_perf.total_ticks = 0;
   g_sched_perf.total_us = 0;
   g_sched_perf.max_us = 0;
}

// Main tick orchestrator (logging-only in M1)
void Scheduler_Tick(const AppContext& ctx)
{
   // M6-Task04: Start profiling measurement (zero overhead when disabled)
   const bool profiling = Config_GetEnablePerfProfiling();
   ulong tick_start_us = 0;
   if(profiling)
      tick_start_us = GetMicrosecondCount();

   // 1) Equity rooms
   EquityRooms rooms = Equity_ComputeRooms(ctx);
   bool floors_ok = Equity_CheckFloors(ctx);

   // 2) Iterate symbols: news + sessions
   for(int i=0;i<ctx.symbols_count;i++)
   {
      string sym = ctx.symbols[i];
      if(sym=="") continue;

      // M6-Task04: Removed redundant Indicators_Refresh - already called in OnTimer

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
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      double spread_pts = (point > 0.0 ? spread_val / point : (double)SymbolInfoInteger(sym, SYMBOL_SPREAD));
      Liquidity_UpdateStats(sym, spread_pts, -1.0);

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
      string choice = MetaPolicy_Choose(ctx, sym, bw_has, bw_conf, mr_has, mr_conf);

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

   // M6-Task04: End profiling measurement and aggregate (throttled reporting)
   if(profiling)
   {
      ulong tick_end_us = GetMicrosecondCount();
      ulong elapsed_us = tick_end_us - tick_start_us;
      g_sched_perf.total_ticks++;
      g_sched_perf.total_us += elapsed_us;
      if(elapsed_us > g_sched_perf.max_us)
         g_sched_perf.max_us = elapsed_us;
      
      datetime now = TimeCurrent();
      if(g_sched_perf.last_report_time == 0)
         g_sched_perf.last_report_time = now;
      if(now - g_sched_perf.last_report_time >= g_sched_perf.report_interval_sec)
      {
         Scheduler_ReportPerfStats();
         g_sched_perf.last_report_time = now;
      }
   }
}

#endif // SCHEDULER_MQH
