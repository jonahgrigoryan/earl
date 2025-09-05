//+------------------------------------------------------------------+
//|                                                   RPEA.mq5      |
//| RapidPass Expert Advisor (M1 scaffolding)                        |
//| References: finalspec.md (SPEC-003), rpea_structure.txt          |
//+------------------------------------------------------------------+
// property & compilation
#property copyright "RPEA - FundingPips RapidPass EA"
#property version   "0.1.0"
#property strict

// Includes (explicit, no wildcards)
#include <RPEA/config.mqh>
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
// sessions.mqh and scheduler.mqh are included after AppContext is defined

//+------------------------------------------------------------------+
// Inputs (consolidated) — names and defaults per finalspec.md
// Risk & governance
input double DailyLossCapPct            = 4.0;
input double OverallLossCapPct          = 6.0;
input int    MinTradeDaysRequired       = 3;
input bool   TradingEnabledDefault      = true;
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
input double MicroRiskPct               = 0.10; // 0.05–0.20
input int    MicroTimeStopMin           = 45;   // 30–60
input double GivebackCapDayPct          = 0.50; // 0.25–0.50

// Compliance
input int    NewsBufferS                = 300;
input int    MaxSpreadPoints            = 40;
input int    MaxSlippagePoints          = 10;
input int    MinHoldSeconds             = 120;
input int    QueuedActionTTLMin         = 5;

// Timezone
input bool   UseServerMidnightBaseline  = true;
input int    ServerToCEST_OffsetMinutes = 0;

// Symbols & leverage
input string InpSymbols                 = "EURUSD;XAUUSD";
input bool   UseXAUEURProxy             = true;
input int    LeverageOverrideFX         = 50;   // 0 → use account
input int    LeverageOverrideMetals     = 20;

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
input double BWISC_ConfCut              = 0.70;
input double MR_ConfCut                 = 0.80;
input int    EMRT_FastThresholdPct      = 40;
input double CorrelationFallbackRho     = 0.50;
input double MR_RiskPct_Default         = 0.90;
input int    MR_TimeStopMin             = 60;
input int    MR_TimeStopMax             = 90;
input bool   MR_LongOnly                = false;
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

//+------------------------------------------------------------------+
// AppContext - runtime context for scheduler and modules
struct AppContext
{
   datetime current_server_time;
   string   symbols[];
   int      symbols_count;
   // session flags (updated by scheduler)
   bool     session_london;
   bool     session_newyork;
   // baselines
   double   initial_baseline;
   double   baseline_today;
   double   equity_snapshot;
   // anchors for the current day
   double   baseline_today_e0; // equity at midnight
   double   baseline_today_b0; // balance at midnight
   // governance flags
   bool     trading_paused;
   bool     permanently_disabled;
   // persistence anchors
   datetime server_midnight_ts;
};

// Global context
static AppContext g_ctx;

// Now that AppContext is defined, include session and scheduler modules
#include <RPEA/sessions.mqh>
#include <RPEA/scheduler.mqh>

// Helper: split symbols
int SplitSymbols(const string src, string &dst[])
{
   return StringSplit(src, ';', dst);
}

//+------------------------------------------------------------------+
// OnInit: initialize state, timer, indicators, logs
int OnInit()
{
   // 1) Prepare context
   g_ctx.symbols_count = SplitSymbols(InpSymbols, g_ctx.symbols);
   g_ctx.current_server_time = TimeCurrent();
   g_ctx.session_london = false;
   g_ctx.session_newyork = false;
   g_ctx.trading_paused = false;
   g_ctx.permanently_disabled = false;

   // 2) Load persisted challenge state
   Persistence_LoadChallengeState();
   ChallengeState s = State_Get();

   // 3) Populate context from persisted state
   g_ctx.initial_baseline = (s.initial_baseline>0.0? s.initial_baseline : AccountInfoDouble(ACCOUNT_EQUITY));
   g_ctx.baseline_today   = (s.baseline_today>0.0? s.baseline_today : g_ctx.initial_baseline);
   g_ctx.equity_snapshot  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_ctx.server_midnight_ts = s.server_midnight_ts;
   g_ctx.baseline_today_e0 = s.baseline_today_e0;
   g_ctx.baseline_today_b0 = s.baseline_today_b0;

   // 4) Initialize indicators
   Indicators_Init(g_ctx);

   // 5) Ensure folders/logs exist and write boot line
   Persistence_EnsureFolders();
   Persistence_EnsurePlaceholderFiles();
   // Load news CSV fallback if present
   News_LoadCsvFallback();
   LogAuditRow("BOOT", "RPEA", 1, "EA boot", "{}");

   // 6) Initialize timer (30s)
   EventSetTimer(30);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
// OnDeinit: flush, stop timer, log shutdown
void OnDeinit(const int reason)
{
   EventKillTimer();
   Persistence_Flush();
   LogAuditRow("SHUTDOWN", "RPEA", 1, "EA deinit", "{}");
}

//+------------------------------------------------------------------+
// OnTimer: orchestration via Scheduler_Tick; server-day rollover
void OnTimer()
{
   g_ctx.current_server_time = TimeCurrent();

   // Server-day rollover handling
   static datetime last_check = 0;
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

      // TODO[M1]: Wire server-day day-count hook to first DEAL_ENTRY_IN later milestones
      State_MarkTradeDayOnce(); // placeholder marking per spec
   }
   last_check = g_ctx.current_server_time;

   // Refresh indicators per symbol (lightweight in M1)
   for(int i=0;i<g_ctx.symbols_count;i++)
   {
      string sym = g_ctx.symbols[i];
      if(sym=="") continue;
      Indicators_Refresh(g_ctx, sym);
   }

   // Delegate to scheduler (logging-only in M1)
   Scheduler_Tick(g_ctx);
}

//+------------------------------------------------------------------+
// OnTradeTransaction: forward to OrderEngine hook (no-op now)
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   OrderEngine_OnTradeTxn(trans, request, result);
}
