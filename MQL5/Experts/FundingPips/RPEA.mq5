//+------------------------------------------------------------------+
//|                                                   RPEA.mq5      |
//| RapidPass Expert Advisor (M1 scaffolding)                        |
//| References: finalspec.md (SPEC-003), rpea_structure.txt          |
//+------------------------------------------------------------------+
// property & compilation
#property copyright "RPEA - FundingPips RapidPass EA"
#property version   "1.00"
#property strict

// Includes (explicit, no wildcards)
#include <RPEA/config.mqh>
#include <RPEA/app_context.mqh>
#include <RPEA/state.mqh>
#include <RPEA/timeutils.mqh>
#include <RPEA/indicators.mqh>
#include <RPEA/regime.mqh>
#include <RPEA/liquidity.mqh>
#include <RPEA/anomaly.mqh>
#include <RPEA/signals_bwisc.mqh>
#include <RPEA/signals_mr.mqh>
#include <RPEA/emrt.mqh>
#include <RPEA/rl_agent.mqh>
#include <RPEA/bandit.mqh>
#include <RPEA/meta_policy.mqh>
#include <RPEA/m7_helpers.mqh>
#include <RPEA/allocator.mqh>
#include <RPEA/adaptive.mqh>
#include <RPEA/risk.mqh>
#include <RPEA/equity_guardian.mqh>
#include <RPEA/order_engine.mqh>
#include <RPEA/synthetic.mqh>
#include <RPEA/news.mqh>
#include <RPEA/learning.mqh>
#include <RPEA/persistence.mqh>
#include <RPEA/logging.mqh>
#include <RPEA/telemetry.mqh>
#include <RPEA/evaluation_report.mqh>
#include <RPEA/slo_monitor.mqh>
// sessions.mqh and scheduler.mqh are included after AppContext is defined

// order_engine.mqh defines a default CutoffHour macro for unit tests; undefine so we can expose an input
#ifdef CutoffHour
#undef CutoffHour
#endif

//+------------------------------------------------------------------+
// Inputs (consolidated) - names and defaults per finalspec.md
// Risk & governance
input double DailyLossCapPct            = 4.0;
input double OverallLossCapPct          = 6.0;
input int    MinTradeDaysRequired       = 3;
input bool   TradingEnabledDefault      = true;
input double MarginLevelCritical        = 50.0;   // Margin level threshold for protective exits
input bool   EnableMarginProtection     = true;   // Enable margin level monitoring
input double MinRiskDollar              = 10.0;
input double OneAndDoneR                = 1.5;
input double NYGatePctOfDailyCap        = 0.50;

// Sessions & micro-mode
input bool   UseLondonOnly              = false;
input int    StartHourLO                = 7;
input int    StartHourNY                = 12;
input int    ORMinutes                  = 60;   // {30,45,60,75}
input int    CutoffHour                 = 16;   // server hour
input double RiskPct                    = 1.5;
input double MicroRiskPct               = 0.10; // 0.05-0.20
input int    MicroTimeStopMin           = 45;   // 30-60
input double GivebackCapDayPct          = 0.50; // 0.25-0.50
input double TargetProfitPct            = 10.0; // Challenge profit target percentage

// Compliance
input int    NewsBufferS                = 300;
input int    MaxSpreadPoints            = 40;
input int    MaxSlippagePoints          = 10;
input double SpreadMultATR              = 0.005; // Max spread as fraction of Daily ATR
input int    MinHoldSeconds             = 120;
input int    QueueTTLMinutes           = DEFAULT_QueueTTLMinutes;
input int    MaxQueueSize               = DEFAULT_MaxQueueSize;
input bool   EnableQueuePrioritization  = DEFAULT_EnableQueuePrioritization;
input bool   EnableDetailedLogging      = DEFAULT_EnableDetailedLogging;
input int    LogBufferSize              = DEFAULT_LogBufferSize;
input string AuditLogPath               = DEFAULT_AuditLogPath;
input string NewsCSVPath                = DEFAULT_NewsCSVPath;
input int    NewsCSVMaxAgeHours         = DEFAULT_NewsCSVMaxAgeHours;
input int    BudgetGateLockMs           = 1000;
input double RiskGateHeadroom           = 0.90;
input int    StabilizationBars          = DEFAULT_StabilizationBars;
input int    StabilizationTimeoutMin    = DEFAULT_StabilizationTimeoutMin;
input double SpreadStabilizationPct     = DEFAULT_SpreadStabilizationPct;
input double VolatilityStabilizationPct = DEFAULT_VolatilityStabilizationPct;
input int    StabilizationLookbackBars  = DEFAULT_StabilizationLookbackBars;
input int    NewsCalendarLookbackHours  = DEFAULT_NewsCalendarLookbackHours;
input int    NewsCalendarLookaheadHours = DEFAULT_NewsCalendarLookaheadHours;
input int    NewsAccountMode            = DEFAULT_NewsAccountMode;
// Resilience / error handling
input int    MaxConsecutiveFailures     = DEFAULT_MaxConsecutiveFailures;
input int    FailureWindowSec           = DEFAULT_FailureWindowSec;
input int    CircuitBreakerCooldownSec  = DEFAULT_CircuitBreakerCooldownSec;
input int    SelfHealRetryWindowSec     = DEFAULT_SelfHealRetryWindowSec;
input int    SelfHealMaxAttempts        = DEFAULT_SelfHealMaxAttempts;
input int    ErrorAlertThrottleSec      = DEFAULT_ErrorAlertThrottleSec;
input bool   BreakerProtectiveExitBypass = DEFAULT_BreakerProtectiveExitBypass;

// M6-Task04: Performance profiling (off by default, low overhead when disabled)
input bool   EnablePerfProfiling        = false;

// Timezone
input bool   UseServerMidnightBaseline  = true;
input int    ServerToCEST_OffsetMinutes = 0;

// Symbols & leverage
input string InpSymbols                 = "EURUSD;XAUUSD";
input bool   UseXAUEURProxy             = true;
input int    LeverageOverrideFX         = 50;   // 0 = use account
input int    LeverageOverrideMetals     = 20;

// Synthetic manager (Task 11 acceptance Synthetic Manager Interface)
input int    SyntheticBarCacheSize      = DEFAULT_SyntheticBarCacheSize;
input bool   ForwardFillGaps            = DEFAULT_ForwardFillGaps;
input int    MaxGapBars                 = DEFAULT_MaxGapBars;
input int    QuoteMaxAgeMs              = DEFAULT_QuoteMaxAgeMs;

// Targets & mechanics
input double RtargetBC                  = 2.2;
input double RtargetMSC                 = 2.0;
input double SLmult                     = 1.0;
input double TrailMult                  = 0.8;
input int    EntryBufferPoints          = 3;
input int    MinStopPoints              = 1;
input long   MagicBase                  = 990200;

// Position / order caps
input int    MaxOpenPositionsTotal      = 2;
input int    MaxOpenPerSymbol           = 1;
input int    MaxPendingsPerSymbol       = 2;

// MR/Ensemble Inputs
input bool   EnableMR                   = true;    // Enable MR strategy
input bool   EnableMRBypassOnRLUnloaded = DEFAULT_EnableMRBypassOnRLUnloaded; // Diagnostic bypass when Q-table is unavailable
input bool   UseBanditMetaPolicy        = true;    // Enable contextual bandit for strategy selection
input bool   BanditShadowMode           = true;    // Log bandit decisions without executing
input bool   EnableAnomalyDetector      = DEFAULT_EnableAnomalyDetector;      // Enable anomaly shock detector
input bool   AnomalyShadowMode          = DEFAULT_AnomalyShadowMode;          // Shadow-only (log intent) rollout mode
input double AnomalyShockSigmaThreshold = DEFAULT_AnomalyShockSigmaThreshold; // Trigger threshold in sigma units
input double AnomalyEWMAAlpha           = DEFAULT_AnomalyEWMAAlpha;           // EWMA smoothing factor (0.01-1.0)
input int    AnomalyMinSamples          = DEFAULT_AnomalyMinSamples;          // Warmup samples before live decisions
input double BWISC_ConfCut              = 0.70;
input double MR_ConfCut                 = 0.80;
input double MR_EMRTWeight              = 0.60;    // Confidence weight on EMRT fastness
input int    EMRT_FastThresholdPct      = 40;
input double CorrelationFallbackRho     = 0.50;    // Assumed correlation if unknown
input double MR_RiskPct_Default         = 0.90;
input bool   EnableAdaptiveRisk         = false;   // Enable adaptive risk multiplier
input double AdaptiveRiskMinMult        = DEFAULT_AdaptiveRiskMinMult;    // Min multiplier (0.08-8.0)
input double AdaptiveRiskMaxMult        = DEFAULT_AdaptiveRiskMaxMult;    // Max multiplier (0.12-12.0)
input int    MR_TimeStopMin             = 60;
input int    MR_TimeStopMax             = 90;
input bool   MR_LongOnly                = false;
input bool   MR_UseLogRatio             = true;    // Use log-ratio for XAUEUR spread
input double EMRT_ExtremeThresholdMult  = 2.0;
input double EMRT_VarCapMult            = 2.5;
input double EMRT_BetaGridMin           = -2.0;
input double EMRT_BetaGridMax           = 2.0;

// Q-Learning training parameters
input double QL_LearningRate            = 0.10;
input double QL_DiscountFactor          = 0.99;
input double QL_EpsilonTrain            = 0.10;
input int    QL_TrainingEpisodes        = 10000;
input int    QL_SimulationPaths         = 1000;

// Global context
AppContext g_ctx;
OrderEngine g_order_engine;

// Now that AppContext is defined, include session and scheduler modules
#include <RPEA/sessions.mqh>
#include <RPEA/scheduler.mqh>

// M6-Task04: OnTimer profiling stats (aggregated, throttled output)
struct OnTimerPerfStats
{
   ulong   tick_count;          // Total OnTimer calls
   ulong   total_us;            // Cumulative microseconds
   ulong   max_us;              // Worst-case single tick
   ulong   equity_checks_us;    // Time in equity checks
   ulong   indicator_refresh_us;// Time in indicator refresh
   ulong   order_engine_us;     // Time in order engine tick + queue
   ulong   scheduler_us;        // Time in scheduler tick
   datetime last_report_time;   // Throttle: last report timestamp
   int     report_interval_sec; // Reporting interval (default 30s)
};
OnTimerPerfStats g_timer_perf = {0, 0, 0, 0, 0, 0, 0, 0, 30};

void OnTimer_ReportPerfStats()
{
   if(!Config_GetEnablePerfProfiling()) return;
   if(g_timer_perf.tick_count == 0) return;
   
   datetime now = TimeCurrent();
   if(now - g_timer_perf.last_report_time < g_timer_perf.report_interval_sec) return;
   
   double avg_us = (double)g_timer_perf.total_us / (double)g_timer_perf.tick_count;
   double avg_eq = (double)g_timer_perf.equity_checks_us / (double)g_timer_perf.tick_count;
   double avg_ind = (double)g_timer_perf.indicator_refresh_us / (double)g_timer_perf.tick_count;
   double avg_oe = (double)g_timer_perf.order_engine_us / (double)g_timer_perf.tick_count;
   double avg_sch = (double)g_timer_perf.scheduler_us / (double)g_timer_perf.tick_count;
   
   PrintFormat("[Perf] OnTimer: ticks=%llu avg=%.0fus max=%lluus | eq=%.0fus ind=%.0fus oe=%.0fus sch=%.0fus",
               g_timer_perf.tick_count, avg_us, g_timer_perf.max_us,
               avg_eq, avg_ind, avg_oe, avg_sch);
   
   g_timer_perf.last_report_time = now;
}

// Helper: split symbols
int SplitSymbols(const string src, string &dst[])
{
   return StringSplit(src, ';', dst);
}

//+------------------------------------------------------------------+
// OnInit: initialize state, timer, indicators, logs
int OnInit()
{
   // M6-Task01: Parameter validation (must run first, before any trading logic)
   if(!Config_ValidateInputs())
   {
      Print("[RPEA] ERROR: Input validation failed - see [Config] logs above");
      return(INIT_FAILED);
   }
   
   // 1) Prepare context
   g_ctx.symbols_count = SplitSymbols(InpSymbols, g_ctx.symbols);
   g_ctx.current_server_time = TimeCurrent();
   g_ctx.session_london = false;
   g_ctx.session_newyork = false;
   g_ctx.trading_paused = false;
   g_ctx.permanently_disabled = false;
   g_ctx.timer_last_check = 0;

   bool has_xaueur = false;
   for(int i = 0; i < g_ctx.symbols_count; i++)
   {
      if(StringCompare(g_ctx.symbols[i], "XAUEUR") == 0)
      {
         has_xaueur = true;
         break;
      }
   }

   if(has_xaueur)
   {
      if(!UseXAUEURProxy)
      {
         Print("[RPEA] ERROR: XAUEUR requires UseXAUEURProxy=true in proxy mode");
         return(INIT_FAILED);
      }
      if(!SymbolSelect("XAUUSD", true) || !SymbolSelect("EURUSD", true))
      {
         Print("[RPEA] ERROR: XAUEUR requires XAUUSD and EURUSD symbols to be available");
         return(INIT_FAILED);
      }
      Print("[RPEA] XAUEUR signal mapping enabled (XAUEUR -> XAUUSD proxy)");
   }

   // 2) Load persisted challenge state (M4-Task04: validates, migrates, recovers)
   Persistence_LoadChallengeState();
   ChallengeState s = State_Get();
   
   // M4-Task04 FR-06: If disabled_permanent is true, set g_ctx.permanently_disabled
   if(s.disabled_permanent)
      g_ctx.permanently_disabled = true;

   // 3) Populate context from persisted state
   g_ctx.initial_baseline = (s.initial_baseline>0.0? s.initial_baseline : AccountInfoDouble(ACCOUNT_EQUITY));
   g_ctx.baseline_today   = (s.baseline_today>0.0? s.baseline_today : g_ctx.initial_baseline);
   g_ctx.equity_snapshot  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_ctx.server_midnight_ts = s.server_midnight_ts;
   g_ctx.baseline_today_e0 = s.baseline_today_e0;
   g_ctx.baseline_today_b0 = s.baseline_today_b0;

    // 4) Initialize indicators
    Indicators_Init(g_ctx);
    g_synthetic_manager.Clear();

   // 5) Ensure folders/logs exist and write boot line
   Persistence_EnsureFolders();
   Persistence_EnsurePlaceholderFiles();
   AuditLogger_Init(AuditLogPath, Config_GetLogBufferSize(), EnableDetailedLogging);

   // 5a) Load EMRT cache (rank/p50/beta)
   bool emrt_loaded = EMRT_LoadCache(FILE_EMRT_CACHE);
   if(!emrt_loaded)
      Print("[EMRT] Cache not loaded (using defaults): ", FILE_EMRT_CACHE);
   else
      Print("[EMRT] Cache loaded: ", FILE_EMRT_CACHE);

   // 5b) Load RL artifacts (Q-table + thresholds)
   bool qtable_loaded = RL_LoadQTable(FILE_QTABLE_BIN);
   if(!qtable_loaded)
      Print("[RL] Q-table not loaded (using defaults): ", FILE_QTABLE_BIN);
   else
      Print("[RL] Q-table loaded: ", FILE_QTABLE_BIN);

   bool thresholds_loaded = RL_LoadThresholds();
   if(!thresholds_loaded)
      Print("[RL] Thresholds not loaded or stale (using defaults)");
   else
      Print("[RL] Thresholds loaded");

   // 5c) Initialize SLO monitoring (M7 Task 08)
   SLO_OnInit();
   Print("[SLO] Metrics initialized");
   Telemetry_InitKpis();
   Print("[Telemetry] KPI metrics initialized");
   Learning_LoadCalibration();
   Print("[Learning] Calibration loaded");

   // M4-Task01: Initialize News Stabilization
   string news_symbols[];
   int news_count = News_BuildStabilizationSymbols(g_ctx.symbols, g_ctx.symbols_count, news_symbols);
   News_InitStabilization(news_symbols, news_count);
   for(int i = 0; i < news_count; i++)
      News_EnsureSymbolSelected(news_symbols[i]);
   News_LoadEvents();

   LogAuditRow("BOOT", "RPEA", 1, "EA boot", "{}");
   EvaluationReport_Init(g_ctx);

    // 6) Initialize Order Engine (M3 Task 1)
    if(!g_order_engine.Init())
    {
       Print("[OrderEngine] Failed to initialize Order Engine");
       return(INIT_FAILED);
    }
    g_order_engine.LoadSLEnforcementState();
    if(!g_order_engine.ReconcileOnStartup())
    {
       Print("[OrderEngine] Failed to reconcile state on startup");
       return(INIT_FAILED);
    }

    // 7) Restore queue/trailing state
   OrderEngine_RestoreStateOnInit(Config_GetQueueTTLMinutes(),
                                   Config_GetMaxQueueSize(),
                                   EnableQueuePrioritization);

   // M4-Task03: If kill-switch flags are active, retry protective exits on restart
   ChallengeState resume_state = State_Get();
   if((resume_state.disabled_permanent || resume_state.daily_floor_breached) &&
      (PositionsTotal() > 0 || OrdersTotal() > 0))
   {
      Equity_ExecuteProtectiveExits("killswitch_resume");
   }

   // 8) Initialize timer (30s)
   EventSetTimer(30);

   // 9) M4-Task02: Initialize peak tracking and check hard-stop state
   ChallengeState init_st = State_Get();
   if(init_st.day_peak_equity <= 0.0)
   {
      init_st.day_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      init_st.overall_peak_equity = init_st.day_peak_equity;
      State_Set(init_st);
   }
   
   // Check if already hard-stopped from previous session
   if(Equity_IsHardStopped())
   {
      g_ctx.permanently_disabled = true;
      PrintFormat("[RPEA] EA is hard-stopped: %s", State_Get().hard_stop_reason);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
// OnDeinit: flush, stop timer, log shutdown
void OnDeinit(const int reason)
{
    g_order_engine.OnShutdown();

   g_synthetic_manager.Clear();

   EventKillTimer();
   Persistence_Flush();
   EvaluationReport_WriteArtifacts(g_ctx, reason);
   LogAuditRow("SHUTDOWN", "RPEA", 1, "EA deinit", "{}");
   AuditLogger_Shutdown();
}

//+------------------------------------------------------------------+
// OnTimer: orchestration via Scheduler_Tick; server-day rollover
void OnTimer()
{
   // M6-Task04: Profiling start (zero overhead when disabled)
   bool profiling = Config_GetEnablePerfProfiling();
   ulong t_start = 0, t_eq_start = 0, t_eq_end = 0;
   ulong t_ind_start = 0, t_ind_end = 0, t_oe_start = 0, t_oe_end = 0;
   ulong t_sch_start = 0, t_sch_end = 0;
   if(profiling) t_start = GetMicrosecondCount();

   g_ctx.current_server_time = TimeCurrent();

   // Server-day rollover handling
   datetime last_check = g_ctx.timer_last_check;
   if(TimeUtils_IsNewServerDay(last_check))
   {
      // compute anchors and reset baselines in persisted state
      ChallengeState st = State_Get();
      st.server_midnight_ts = TimeUtils_ServerMidnight(g_ctx.current_server_time);
      State_ResetDailyBaseline(st);
      State_Set(st);
      // mirror into context
      g_ctx.server_midnight_ts = st.server_midnight_ts;
      g_ctx.baseline_today     = st.baseline_today;
      g_ctx.baseline_today_e0  = st.baseline_today_e0;
      g_ctx.baseline_today_b0  = st.baseline_today_b0;

      // Persist and log rollover
      Persistence_Flush();
      LogAuditRow("ROLLOVER", "Scheduler", 1, "New server day baseline anchored", "{}");

      // Day-count handled in OnTradeTransaction on first DEAL_ENTRY_IN (per spec)
      
      // M4-Task02: Server-day rollover handling
      Equity_OnServerDayRollover();
   }
   g_ctx.timer_last_check = g_ctx.current_server_time;
   
   // --- Equity checks section ---
   if(profiling) t_eq_start = GetMicrosecondCount();
   
   // M4-Task03: Kill-switch floors and margin protection
   Equity_CheckAndExecuteKillswitch(g_ctx);
   Equity_CheckMarginProtection();
   
   // M4-Task02: Update peak tracking
   Equity_UpdatePeakTracking();
   
   // M4-Task02: Check Micro-Mode activation (target hit but days remaining)
   Equity_CheckMicroMode(g_ctx);
   
   // M4-Task02: Check giveback protection (Micro-Mode only)
   Equity_CheckGivebackProtection();
   
   // M4-Task02: Check hard-stop conditions (floor breach or challenge complete)
   Equity_CheckHardStopConditions(g_ctx);
   EvaluationReport_Update(g_ctx);
   EvaluationReport_MaybeWriteTesterSnapshot(g_ctx);
   
   if(profiling) t_eq_end = GetMicrosecondCount();

   // --- Indicator refresh section ---
   if(profiling) t_ind_start = GetMicrosecondCount();
   
    // Refresh indicators per symbol (lightweight in M1)
    int synth_idx = Indicators_FindSlot(SYNTH_SYMBOL_XAUEUR);
    if(synth_idx >= 0)
    {
       SyntheticBar warmup[];
        const int daily_required = 15;
        const int hourly_required = 40;
        if(!g_synthetic_manager.GetCachedBars(SYNTH_SYMBOL_XAUEUR, PERIOD_D1, warmup, daily_required))
           g_synthetic_manager.BuildSyntheticBars(SYNTH_SYMBOL_XAUEUR, PERIOD_D1, daily_required);
        ArrayResize(warmup, 0);
        if(!g_synthetic_manager.GetCachedBars(SYNTH_SYMBOL_XAUEUR, PERIOD_H1, warmup, hourly_required))
           g_synthetic_manager.BuildSyntheticBars(SYNTH_SYMBOL_XAUEUR, PERIOD_H1, hourly_required);
    }

   for(int i=0;i<g_ctx.symbols_count;i++)
   {
      string sym = g_ctx.symbols[i];
      if(sym=="") continue;
      Indicators_Refresh(g_ctx, sym);
   }
   
   if(profiling) t_ind_end = GetMicrosecondCount();

   // --- Order engine section ---
   if(profiling) t_oe_start = GetMicrosecondCount();
   
    // M3 Task 1: Order Engine timer tick (AFTER transaction processing)
    g_order_engine.OnTimerTick(g_ctx.current_server_time);

    // Task 12/13 queue + trailing processing
    OrderEngine_ProcessQueueAndTrailing();

   // Master SL enforcement tracking
   g_order_engine.CheckPendingSLEnforcement();
   
   if(profiling) t_oe_end = GetMicrosecondCount();

   // --- Scheduler section ---
   if(profiling) t_sch_start = GetMicrosecondCount();
   
   // Delegate to scheduler (logging-only in M1)
   Scheduler_Tick(g_ctx);
   
   // M4-Task01: Update news blocking and stabilization state
   News_OnTimer();
   
   if(profiling) t_sch_end = GetMicrosecondCount();
   
   // M6-Task04: Aggregate and report stats (throttled)
   if(profiling)
   {
      ulong elapsed = GetMicrosecondCount() - t_start;
      g_timer_perf.tick_count++;
      g_timer_perf.total_us += elapsed;
      if(elapsed > g_timer_perf.max_us) g_timer_perf.max_us = elapsed;
      g_timer_perf.equity_checks_us += (t_eq_end - t_eq_start);
      g_timer_perf.indicator_refresh_us += (t_ind_end - t_ind_start);
      g_timer_perf.order_engine_us += (t_oe_end - t_oe_start);
      g_timer_perf.scheduler_us += (t_sch_end - t_sch_start);
      OnTimer_ReportPerfStats();
   }
}

//+------------------------------------------------------------------+
// OnTick: lightweight price monitoring and validation
void OnTick()
{
   g_ctx.current_server_time = TimeCurrent();
   // M4-Task03: Fast kill-switch response on live ticks (avoid heavy logging unless breached)
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double daily_floor = Equity_GetDailyFloor();
   double overall_floor = Equity_GetOverallFloor();
   if((daily_floor > 0.0 && current_equity <= daily_floor) ||
      (overall_floor > 0.0 && current_equity <= overall_floor))
   {
      Equity_CheckAndExecuteKillswitch(g_ctx);
   }
   EvaluationReport_Update(g_ctx);
   EvaluationReport_MaybeWriteTesterSnapshot(g_ctx);
   g_order_engine.OnTick();
}

//+------------------------------------------------------------------+
// OnTradeTransaction: CRITICAL - Process fills immediately before timer
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // M3 Task 1: Process transaction BEFORE any timer housekeeping
   OrderEngine_OnTradeTxn(trans, request, result);

   // Count trading day on first DEAL_ENTRY_IN of the server day
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
   {
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
      {
         // M4-Task02: Use explicit server timestamp for deterministic tracking
         datetime deal_time = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
         if(deal_time <= 0)
            deal_time = TimeCurrent();
         State_MarkTradeDayServer(deal_time);
         
         // M4-Task02: Track Micro-Mode entry usage per day
         if(Equity_IsMicroModeActive())
            State_MarkMicroEntryServer(deal_time);

         // M7-Phase0: Track session entries for meta-policy session cap
         long deal_magic = (long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         ulong position_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
         string deal_symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
         if(deal_symbol == "") deal_symbol = trans.symbol;
         if(deal_symbol == "") deal_symbol = "XAUUSD";
         string deal_comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);

         if(OrderEngine_IsOurMagic(deal_magic))
         {
            double entry_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
            double entry_volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
            double sl_price = HistoryDealGetDouble(trans.deal, DEAL_SL);
            double tp_price = HistoryDealGetDouble(trans.deal, DEAL_TP);

            if(position_id > 0 && PositionSelectByTicket(position_id))
            {
               if(sl_price <= 0.0)
                  sl_price = PositionGetDouble(POSITION_SL);
               if(tp_price <= 0.0)
                  tp_price = PositionGetDouble(POSITION_TP);
            }

            Telemetry_OnPositionEntryDetailed(position_id,
                                              deal_comment,
                                              deal_time,
                                              deal_symbol,
                                              entry_price,
                                              sl_price,
                                              tp_price,
                                              entry_volume);
         }

         if(M7_ShouldCountEntry(position_id, deal_magic))
         {
            AppContext ctx = g_ctx;
            ctx.current_server_time = deal_time;

            M7_GetEntriesThisSession(ctx, deal_symbol);  // Updates session label
            M7_IncrementEntries();

            LogDecision("M7", "ENTRY_COUNTED",
               StringFormat("{\"position\":%I64u,\"entries\":%d}",
                  position_id, M7_GetEntriesThisSession(ctx, deal_symbol)));
         }
      }
      else if(entry == DEAL_ENTRY_OUT)
      {
         long deal_magic = (long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         if(OrderEngine_IsOurMagic(deal_magic))
         {
            datetime deal_time = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
            if(deal_time <= 0)
               deal_time = TimeCurrent();

            ulong position_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
            string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
            double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            double swap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
            double commission = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
            double net_outcome = profit + swap + commission;

            bool position_closed = true;
            if(position_id > 0 && PositionSelectByTicket(position_id))
            {
               double remaining_volume = PositionGetDouble(POSITION_VOLUME);
               position_closed = (remaining_volume <= 1e-8);
            }

            string telemetry_strategy = "";
            double telemetry_outcome = 0.0;
            int telemetry_hold_minutes = 0;
            double telemetry_friction_r = 0.0;
            bool telemetry_emitted = Telemetry_OnPositionExitWithTheory(position_id,
                                                                        comment,
                                                                        net_outcome,
                                                                        0.0,
                                                                        deal_time,
                                                                        position_closed,
                                                                        telemetry_strategy,
                                                                        telemetry_outcome,
                                                                        telemetry_hold_minutes,
                                                                        telemetry_friction_r);
            if(telemetry_emitted)
            {
               SLO_OnTradeClosed(trans.deal,
                                 position_id,
                                 telemetry_strategy,
                                 telemetry_outcome,
                                 telemetry_hold_minutes,
                                 telemetry_friction_r,
                                 deal_time);
               Bandit_RecordTradeOutcome(telemetry_strategy, telemetry_outcome);
               Learning_Update();
            }
         }
      }
   }

   g_ctx.current_server_time = TimeCurrent();
   EvaluationReport_Update(g_ctx);
   EvaluationReport_MaybeWriteTesterSnapshot(g_ctx);
}
