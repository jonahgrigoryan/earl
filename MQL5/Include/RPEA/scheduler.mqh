// scheduler.mqh - RPEA Scheduler Module
// References: finalspec.md sections on "Scheduler (OnTimer 30–60s)" and "Data Flow & Sequence (per trading window)"
#ifndef SCHEDULER_MQH
#define SCHEDULER_MQH

#include <RPEA/config.mqh>
#include <RPEA/order_engine.mqh>

struct AppContext;
extern OrderEngine g_order_engine;

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

// Main tick orchestrator
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

      if(choice == "Skip")
      {
         string skip_fields = StringFormat("{\"symbol\":\"%s\",\"choice\":\"%s\",\"bw_conf\":%.2f,\"mr_conf\":%.2f,\"reason\":\"policy_skip\"}",
                                           sym,
                                           choice,
                                           bw_conf,
                                           mr_conf);
         LogDecision("Scheduler", "EVAL", skip_fields);
         continue;
      }

      // 5) Build allocator plan and execute through order engine
      int slPoints = (choice=="BWISC")?bw_sl:mr_sl;
      int tpPoints = (choice=="BWISC")?bw_tp:mr_tp;
      double conf  = (choice=="BWISC")?bw_conf:mr_conf;
      OrderPlan plan = Allocator_BuildOrderPlan(ctx, choice, sym, slPoints, tpPoints, conf);

      if(!plan.valid)
      {
         string reject_fields = StringFormat("{\"symbol\":\"%s\",\"choice\":\"%s\",\"bw_conf\":%.2f,\"mr_conf\":%.2f,\"reason\":\"%s\"}",
                                             sym,
                                             choice,
                                             bw_conf,
                                             mr_conf,
                                             plan.rejection_reason);
         LogDecision("Scheduler", "PLAN_REJECT", reject_fields);
         LogDecision("Scheduler", "EVAL", reject_fields);
         continue;
      }

      OrderRequest request;
      ZeroMemory(request);
      request.symbol = plan.symbol;
      request.type = plan.order_type;
      request.volume = plan.volume;
      request.price = plan.price;
      request.sl = plan.sl;
      request.tp = plan.tp;
      request.magic = plan.magic;
      request.comment = plan.comment;
      request.is_oco_primary = false;
      request.oco_sibling_ticket = 0;
      request.expiry = 0;
      request.signal_symbol = plan.signal_symbol;
      request.is_protective = false;
      request.is_proxy = plan.is_proxy;
      request.proxy_rate = plan.proxy_rate;
      request.proxy_context = plan.proxy_context;

      OrderResult result = g_order_engine.PlaceOrder(request);

      string eval_fields = StringFormat("{\"symbol\":\"%s\",\"choice\":\"%s\",\"setup\":\"%s\",\"bw_conf\":%.2f,\"mr_conf\":%.2f,\"plan_valid\":true,\"order_sent\":%s}",
                                        sym,
                                        choice,
                                        plan.setup_type,
                                        bw_conf,
                                        mr_conf,
                                        result.success ? "true" : "false");
      LogDecision("Scheduler", "EVAL", eval_fields);

      string place_err = result.error_message;
      StringReplace(place_err, "\"", "'");
      string place_fields = StringFormat("{\"symbol\":\"%s\",\"choice\":\"%s\",\"setup\":\"%s\",\"ticket\":%llu,\"retcode\":%d,\"error\":\"%s\"}",
                                         sym,
                                         choice,
                                         plan.setup_type,
                                         result.ticket,
                                         result.last_retcode,
                                         place_err);
      if(result.success)
         LogDecision("Scheduler", "PLACE_OK", place_fields);
      else
         LogDecision("Scheduler", "PLACE_FAIL", place_fields);
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
