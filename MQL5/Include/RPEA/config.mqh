#ifndef CONFIG_MQH
#define CONFIG_MQH
// config.mqh - Public constants, enums, and type aliases
// References: finalspec.md (Inputs, News Compliance, Files & Folders)

// Version
#define RPEA_VERSION   "0.1.0"

// Base directories under MQL5/Files
#define RPEA_DIR                  "RPEA"
#define RPEA_STATE_DIR           (RPEA_DIR"/state")
#define RPEA_LOGS_DIR            (RPEA_DIR"/logs")
#define RPEA_REPORTS_DIR         (RPEA_DIR"/reports")
#define RPEA_NEWS_DIR            (RPEA_DIR"/news")
#define RPEA_EMRT_DIR            (RPEA_DIR"/emrt")
#define RPEA_QTABLE_DIR          (RPEA_DIR"/qtable")
#define RPEA_BANDIT_DIR          (RPEA_DIR"/bandit")
#define RPEA_LIQUIDITY_DIR       (RPEA_DIR"/liquidity")
#define RPEA_CALIBRATION_DIR     (RPEA_DIR"/calibration")
#define RPEA_SETS_DIR            (RPEA_DIR"/sets")
#define RPEA_TESTER_DIR          (RPEA_DIR"/strategy_tester")

// Aliases (backwards-compat macros as per M1 acceptance wording)
#define STATE_DIR       RPEA_STATE_DIR
#define LOGS_DIR        RPEA_LOGS_DIR
#define REPORTS_DIR     RPEA_REPORTS_DIR
#define NEWS_DIR        RPEA_NEWS_DIR
#define EMRT_DIR        RPEA_EMRT_DIR
#define QTABLE_DIR      RPEA_QTABLE_DIR
#define BANDIT_DIR      RPEA_BANDIT_DIR
#define LIQUIDITY_DIR   RPEA_LIQUIDITY_DIR
#define CALIBRATION_DIR RPEA_CALIBRATION_DIR
#define SETS_DIR        RPEA_SETS_DIR
#define TESTER_DIR      RPEA_TESTER_DIR

// Files
#define FILE_CHALLENGE_STATE     (RPEA_STATE_DIR"/challenge_state.json")
#define FILE_INTENTS             (RPEA_STATE_DIR"/intents.json")
#define FILE_QUEUE_ACTIONS       (RPEA_STATE_DIR"/queue_actions.csv")
#define FILE_SL_ENFORCEMENT      (RPEA_STATE_DIR"/sl_enforcement.json")
#define FILE_NEWS_FALLBACK       (RPEA_NEWS_DIR"/calendar_high_impact.csv")
#define FILE_EMRT_CACHE          (RPEA_EMRT_DIR"/emrt_cache.json")
#define FILE_EMRT_BETA_GRID      (RPEA_EMRT_DIR"/beta_grid.json")
#define FILE_QTABLE_BIN          (RPEA_QTABLE_DIR"/mr_qtable.bin")
#define FILE_BANDIT_POSTERIOR    (RPEA_BANDIT_DIR"/posterior.json")
#define FILE_LIQUIDITY_STATS     (RPEA_LIQUIDITY_DIR"/spread_slippage_stats.json")
#define FILE_CALIBRATION         (RPEA_CALIBRATION_DIR"/calibration.json")
#define FILE_SET_DEFAULT         (RPEA_SETS_DIR"/RPEA_10k_default.set")
#define FILE_OPT_RANGES          (RPEA_SETS_DIR"/RPEA_optimization_ranges.txt")
#define FILE_TESTER_INI          (RPEA_TESTER_DIR"/RPEA_10k_tester.ini")
#define FILE_AUDIT_REPORT        (RPEA_REPORTS_DIR"/audit_report.csv")

// Log levels
#define LOG_DEBUG 0
#define LOG_INFO  1
#define LOG_WARN  2
#define LOG_ERROR 3

//==============================================================================
// M3 - Order Engine and Synthetic Cross Support Configuration
//==============================================================================

// Order Engine Configuration
#define DEFAULT_MaxRetryAttempts              3
#define DEFAULT_InitialRetryDelayMs          300
#define DEFAULT_RetryBackoffMultiplier       2.0
#define DEFAULT_MaxSlippagePoints            10.0
#define DEFAULT_MinHoldSeconds               120
#define DEFAULT_EnableExecutionLock          true
#define DEFAULT_PendingExpiryGraceSeconds    60
#define DEFAULT_PendingExpirySeconds         2700
#define DEFAULT_AutoCancelOCOSibling         true
#define DEFAULT_OCOCancellationTimeoutMs     1000
#define DEFAULT_EnableRiskReductionSiblingCancel true
#define DEFAULT_EnableDetailedLogging        true
#define DEFAULT_AuditLogPath                 "RPEA/logs/"
#define DEFAULT_LogBufferSize                1000
#define DEFAULT_CorrelationFallbackRho       0.30
#define DEFAULT_MaxConsecutiveFailures       3
#define DEFAULT_FailureWindowSec             900
#define DEFAULT_CircuitBreakerCooldownSec    120
#define DEFAULT_SelfHealRetryWindowSec       300
#define DEFAULT_SelfHealMaxAttempts          2
#define DEFAULT_ErrorAlertThrottleSec        60
#define DEFAULT_BreakerProtectiveExitBypass  true

// Synthetic Manager Configuration (Task 11 acceptance §Synthetic Manager Interface)
#define DEFAULT_UseXAUEURProxy               true
#define DEFAULT_ReplicationMarginThreshold   0.6
#define DEFAULT_SyntheticBarCacheSize        1000
#define DEFAULT_ForwardFillGaps              true
#define DEFAULT_MaxGapBars                   5
#define DEFAULT_QuoteMaxAgeMs                5000
#define DEFAULT_ContractXAU                  100.0
#define DEFAULT_ContractFX                   100000.0
#define DEFAULT_DeltaTolerancePct            0.05
#define DEFAULT_MarginBufferPct              0.20
#define DEFAULT_ProxyRiskMultiplier          1.0
#define DEFAULT_EnableReplicationFallback    true

// Adaptive Risk Configuration (Post-M7 Phase 3)
#define DEFAULT_EnableAdaptiveRisk           false
#define DEFAULT_AdaptiveRiskMinMult          0.80
#define DEFAULT_AdaptiveRiskMaxMult          1.20

// News and Queue Configuration
#define DEFAULT_NewsCSVPath                  "RPEA/news/calendar_high_impact.csv"
#define DEFAULT_NewsCSVMaxAgeHours           24
#define DEFAULT_BudgetGateLockMs             1000
#define DEFAULT_RiskGateHeadroom             0.90
#define DEFAULT_MaxQueueSize                 1000
#define DEFAULT_QueueTTLMinutes              5
#define DEFAULT_EnableQueuePrioritization    true

// M4-Task01: Post-News Stabilization Configuration
#define DEFAULT_StabilizationBars            3
#define DEFAULT_StabilizationTimeoutMin      15
#define DEFAULT_SpreadStabilizationPct       60.0
#define DEFAULT_VolatilityStabilizationPct   70.0
#define DEFAULT_StabilizationLookbackBars    60
#define DEFAULT_NewsCalendarLookbackHours    6
#define DEFAULT_NewsCalendarLookaheadHours   24
#define DEFAULT_NewsAccountMode              0

// Liquidity Configuration (Task 22)
#define DEFAULT_SpreadMultATR                0.005

// Breakeven Configuration (Task 23)
// Performance and maintainability constants
#define BREAKEVEN_TRIGGER_R_MULTIPLE         0.5
#define EPS_SL_CHANGE                        1e-6
#define LEGACY_LOG_FLUSH_THRESHOLD           64
// Optional additive buffer (points) on top of live spread when moving SL to breakeven.
#define DEFAULT_BreakevenExtraPoints         0

// M4-Task03: Kill-Switch + Margin Protection Configuration
#define DEFAULT_MarginLevelCritical          50.0
#define DEFAULT_EnableMarginProtection       true
#define DEFAULT_TradingEnabledDefault        true

#ifdef __MQL5__
//==============================================================================
// M4-Task02: Micro-Mode + Hard-Stop Configuration (moved above for visibility)
//==============================================================================
// These are defined here so they're available before inline functions
#ifndef DEFAULT_TargetProfitPct
#define DEFAULT_TargetProfitPct              10.0
#endif
#ifndef DEFAULT_MicroRiskPct
#define DEFAULT_MicroRiskPct                 0.10
#endif
#ifndef DEFAULT_MicroTimeStopMin
#define DEFAULT_MicroTimeStopMin             45
#endif
#ifndef DEFAULT_GivebackCapDayPct
#define DEFAULT_GivebackCapDayPct            0.50
#endif
#ifndef DEFAULT_ServerToCEST_OffsetMinutes
#define DEFAULT_ServerToCEST_OffsetMinutes   0
#endif

//------------------------------------------------------------------------------
// M7-Task08: EnableMR test override for BWISC-only regression tests
//------------------------------------------------------------------------------
#ifdef RPEA_TEST_RUNNER
bool   g_test_enable_mr_override_active = false;
bool   g_test_enable_mr_override_value = true;
bool   g_test_enable_adaptive_override_active = false;
bool   g_test_enable_adaptive_override_value = DEFAULT_EnableAdaptiveRisk;
bool   g_test_adaptive_bounds_override_active = false;
double g_test_adaptive_min_mult_override = DEFAULT_AdaptiveRiskMinMult;
double g_test_adaptive_max_mult_override = DEFAULT_AdaptiveRiskMaxMult;

void Config_Test_SetEnableMROverride(bool active, bool value)
{
   g_test_enable_mr_override_active = active;
   g_test_enable_mr_override_value = value;
}

void Config_Test_ClearEnableMROverride()
{
   g_test_enable_mr_override_active = false;
}

void Config_Test_SetEnableAdaptiveRiskOverride(bool active, bool value)
{
   g_test_enable_adaptive_override_active = active;
   g_test_enable_adaptive_override_value = value;
}

void Config_Test_ClearEnableAdaptiveRiskOverride()
{
   g_test_enable_adaptive_override_active = false;
}

void Config_Test_SetAdaptiveRiskBoundsOverride(bool active,
                                               double min_multiplier,
                                               double max_multiplier)
{
   g_test_adaptive_bounds_override_active = active;
   g_test_adaptive_min_mult_override = min_multiplier;
   g_test_adaptive_max_mult_override = max_multiplier;
}

void Config_Test_ClearAdaptiveRiskBoundsOverride()
{
   g_test_adaptive_bounds_override_active = false;
   g_test_adaptive_min_mult_override = DEFAULT_AdaptiveRiskMinMult;
   g_test_adaptive_max_mult_override = DEFAULT_AdaptiveRiskMaxMult;
}
#endif
//------------------------------------------------------------------------------
// Task 17 Resilience Config Helpers
//------------------------------------------------------------------------------

inline void Config_LogClampInt(const string key, const int invalid_value, const int fallback)
{
   PrintFormat("[Config] %s invalid (%d), clamping to %d", key, invalid_value, fallback);
}

inline int Config_GetMaxConsecutiveFailures()
{
   int configured = MaxConsecutiveFailures;
   if(configured <= 0)
   {
      Config_LogClampInt("MaxConsecutiveFailures", configured, DEFAULT_MaxConsecutiveFailures);
      configured = DEFAULT_MaxConsecutiveFailures;
   }
   return configured;
}

inline int Config_GetFailureWindowSec()
{
   int configured = FailureWindowSec;
   if(configured <= 0)
   {
      Config_LogClampInt("FailureWindowSec", configured, DEFAULT_FailureWindowSec);
      configured = DEFAULT_FailureWindowSec;
   }
   return configured;
}

inline int Config_GetCircuitBreakerCooldownSec()
{
   int configured = CircuitBreakerCooldownSec;
   if(configured <= 0)
   {
      Config_LogClampInt("CircuitBreakerCooldownSec", configured, DEFAULT_CircuitBreakerCooldownSec);
      configured = DEFAULT_CircuitBreakerCooldownSec;
   }
   return configured;
}

inline int Config_GetSelfHealRetryWindowSec()
{
   int configured = SelfHealRetryWindowSec;
   if(configured <= 0)
   {
      Config_LogClampInt("SelfHealRetryWindowSec", configured, DEFAULT_SelfHealRetryWindowSec);
      configured = DEFAULT_SelfHealRetryWindowSec;
   }
   return configured;
}

inline int Config_GetSelfHealMaxAttempts()
{
   int configured = SelfHealMaxAttempts;
   if(configured <= 0)
   {
      Config_LogClampInt("SelfHealMaxAttempts", configured, DEFAULT_SelfHealMaxAttempts);
      configured = DEFAULT_SelfHealMaxAttempts;
   }
   return configured;
}

inline int Config_GetErrorAlertThrottleSec()
{
   int configured = ErrorAlertThrottleSec;
   if(configured <= 0)
   {
      Config_LogClampInt("ErrorAlertThrottleSec", configured, DEFAULT_ErrorAlertThrottleSec);
      configured = DEFAULT_ErrorAlertThrottleSec;
   }
   return configured;
}

inline bool Config_GetBreakerProtectiveExitBypass()
{
   bool configured = BreakerProtectiveExitBypass;
   return configured;
}

//------------------------------------------------------------------------------
// M6-Task04: Performance Profiling Config Helper
//------------------------------------------------------------------------------

#ifndef DEFAULT_EnablePerfProfiling
#define DEFAULT_EnablePerfProfiling false
#endif

inline bool Config_GetEnablePerfProfiling()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef EnablePerfProfiling
      return EnablePerfProfiling;
   #else
      return DEFAULT_EnablePerfProfiling;
   #endif
#else
   return EnablePerfProfiling;
#endif
}

//------------------------------------------------------------------------------
// Task 22 Liquidity Config Helper
//------------------------------------------------------------------------------

inline double Config_ClampSpreadMultATRValue(const double value)
{
   if(!MathIsValidNumber(value) || value <= 0.0)
      return DEFAULT_SpreadMultATR;
   return value;
}

inline double Config_GetSpreadMultATR()
{
#ifdef RPEA_TEST_RUNNER
   // In test runner, inputs are defined as macros.
   // Guard against missing macro definition.
   #ifdef SpreadMultATR
      return Config_ClampSpreadMultATRValue(SpreadMultATR);
   #else
      return DEFAULT_SpreadMultATR;
   #endif
#else
   // In EA, inputs are global variables visible to included files.
   return Config_ClampSpreadMultATRValue(SpreadMultATR);
#endif
}

//------------------------------------------------------------------------------
// Task 23 Breakeven Config Helper
//------------------------------------------------------------------------------

inline double Config_GetBreakevenExtraPoints()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef BreakevenExtraPoints
      return BreakevenExtraPoints;
   #else
      return DEFAULT_BreakevenExtraPoints;
   #endif
#else
   #ifdef BreakevenExtraPoints
      return BreakevenExtraPoints;
   #else
      return DEFAULT_BreakevenExtraPoints;
   #endif
#endif
}

//==============================================================================
// M6-Task01: Parameter Validation Helpers
//==============================================================================

//------------------------------------------------------------------------------
// Logging helpers for validation
//------------------------------------------------------------------------------

inline void Config_LogClampDouble(const string key, const double invalid_value, const double fallback)
{
   PrintFormat("[Config] %s invalid (%.6f), clamping to %.6f", key, invalid_value, fallback);
}

inline void Config_LogFatal(const string key, const string reason)
{
   PrintFormat("[Config] FATAL: %s %s", key, reason);
}

inline void Config_LogWarn(const string key, const string msg)
{
   PrintFormat("[Config] %s: %s", key, msg);
}

//------------------------------------------------------------------------------
// ORMinutes: must be one of {30, 45, 60, 75}
//------------------------------------------------------------------------------

inline int Config_NearestORMinutes(const int value)
{
   // Find nearest allowed value
   int allowed[] = {30, 45, 60, 75};
   int nearest = 60; // default
   int min_dist = 9999;
   for(int i = 0; i < 4; i++)
   {
      int dist = MathAbs(value - allowed[i]);
      if(dist < min_dist)
      {
         min_dist = dist;
         nearest = allowed[i];
      }
   }
   return nearest;
}

inline int Config_GetORMinutes()
{
#ifdef RPEA_TEST_RUNNER
   return ORMinutes; // Test runner uses macro, assume valid
#else
   int val = ORMinutes;
   if(val != 30 && val != 45 && val != 60 && val != 75)
      return Config_NearestORMinutes(val);
   return val;
#endif
}

//------------------------------------------------------------------------------
// Risk caps: effective daily cap (clamped if overall < daily)
//------------------------------------------------------------------------------

inline double Config_GetEffectiveDailyLossCapPct()
{
#ifdef RPEA_TEST_RUNNER
   return DailyLossCapPct;
#else
   double daily = DailyLossCapPct;
   double overall = OverallLossCapPct;
   if(overall > 0 && daily > 0 && overall < daily)
      return overall; // Clamp daily down to overall
   return daily;
#endif
}

//------------------------------------------------------------------------------
// Session hours: clamp to [0, 23]
//------------------------------------------------------------------------------

inline int Config_ClampHour(const int hour)
{
   if(hour < 0) return 0;
   if(hour > 23) return 23;
   return hour;
}

inline int Config_GetStartHourLO()
{
#ifdef RPEA_TEST_RUNNER
   return StartHourLO;
#else
   return Config_ClampHour(StartHourLO);
#endif
}

inline int Config_GetStartHourNY()
{
#ifdef RPEA_TEST_RUNNER
   return StartHourNY;
#else
   return Config_ClampHour(StartHourNY);
#endif
}

inline int Config_GetCutoffHour()
{
#ifdef RPEA_TEST_RUNNER
   return CutoffHour;
#else
   return Config_ClampHour(CutoffHour);
#endif
}

//------------------------------------------------------------------------------
// MinTradeDaysRequired: clamp to >= 1
//------------------------------------------------------------------------------

inline int Config_GetMinTradeDaysRequired()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef MinTradeDaysRequired
      return (MinTradeDaysRequired < 1) ? 1 : MinTradeDaysRequired;
   #else
      return 3; // Default
   #endif
#else
   int val = MinTradeDaysRequired;
   return (val < 1) ? 1 : val;
#endif
}

//------------------------------------------------------------------------------
// Risk percentages: clamp to finalspec ranges
// RiskPct: [0.8, 2.0]
// MicroRiskPct: [0.05, 0.20]
//------------------------------------------------------------------------------

inline double Config_GetRiskPct()
{
#ifdef RPEA_TEST_RUNNER
   return RiskPct;
#else
   double val = RiskPct;
   if(val < 0.8) return 0.8;
   if(val > 2.0) return 2.0;
   return val;
#endif
}

inline double Config_GetMicroRiskPct()
{
#ifdef RPEA_TEST_RUNNER
   return MicroRiskPct;
#else
   double val = MicroRiskPct;
   if(val < 0.05) return 0.05;
   if(val > 0.20) return 0.20;
   return val;
#endif
}

//------------------------------------------------------------------------------
// R-targets and multipliers: clamp to finalspec ranges
// RtargetBC: [1.8, 2.6], RtargetMSC: [1.6, 2.4]
// SLmult: [0.7, 1.3], TrailMult: [0.6, 1.2]
// GivebackCapDayPct: [0.25, 0.50], OneAndDoneR: [0.5, 5.0]
//------------------------------------------------------------------------------

inline double Config_GetRtargetBC()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef RtargetBC
      return RtargetBC;
   #else
      return 2.2;
   #endif
#else
   double val = RtargetBC;
   if(val < 1.8) return 1.8;
   if(val > 2.6) return 2.6;
   return val;
#endif
}

inline double Config_GetRtargetMSC()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef RtargetMSC
      return RtargetMSC;
   #else
      return 2.0;
   #endif
#else
   double val = RtargetMSC;
   if(val < 1.6) return 1.6;
   if(val > 2.4) return 2.4;
   return val;
#endif
}

inline double Config_GetSLmult()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef SLmult
      return SLmult;
   #else
      return 1.0;
   #endif
#else
   double val = SLmult;
   if(val < 0.7) return 0.7;
   if(val > 1.3) return 1.3;
   return val;
#endif
}

inline double Config_GetTrailMult()
{
#ifdef RPEA_TEST_RUNNER
   return TrailMult;
#else
   double val = TrailMult;
   if(val < 0.6) return 0.6;
   if(val > 1.2) return 1.2;
   return val;
#endif
}

inline double Config_GetGivebackCapDayPct()
{
#ifdef RPEA_TEST_RUNNER
   return GivebackCapDayPct;
#else
   double val = GivebackCapDayPct;
   if(val < 0.25) return 0.25;
   if(val > 0.50) return 0.50;
   return val;
#endif
}

inline double Config_GetOneAndDoneR()
{
#ifdef RPEA_TEST_RUNNER
   return OneAndDoneR;
#else
   double val = OneAndDoneR;
   if(val < 0.5) return 0.5;
   if(val > 5.0) return 5.0;
   return val;
#endif
}

//------------------------------------------------------------------------------
// Time windows: clamp to >= 0
//------------------------------------------------------------------------------

inline int Config_ClampNonNegativeInt(const int val)
{
   return (val < 0) ? 0 : val;
}

inline int Config_GetMicroTimeStopMin()
{
#ifdef RPEA_TEST_RUNNER
   return MicroTimeStopMin;
#else
   int val = MicroTimeStopMin;
   if(val < 30) return 30;
   if(val > 60) return 60;
   return val;
#endif
}

inline int Config_GetMinHoldSeconds()
{
#ifdef RPEA_TEST_RUNNER
   return MinHoldSeconds;
#else
   return Config_ClampNonNegativeInt(MinHoldSeconds);
#endif
}

inline int Config_GetNewsBufferS()
{
#ifdef RPEA_TEST_RUNNER
   return NewsBufferS;
#else
   return Config_ClampNonNegativeInt(NewsBufferS);
#endif
}

inline int Config_GetQueueTTLMinutes()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef QueueTTLMinutes
      return QueueTTLMinutes;
   #else
      return DEFAULT_QueueTTLMinutes;
   #endif
#else
   return Config_ClampNonNegativeInt(QueueTTLMinutes);
#endif
}

inline int Config_GetStabilizationTimeoutMin()
{
#ifdef RPEA_TEST_RUNNER
   return StabilizationTimeoutMin;
#else
   return Config_ClampNonNegativeInt(StabilizationTimeoutMin);
#endif
}

inline int Config_GetStabilizationBars()
{
#ifdef RPEA_TEST_RUNNER
   return StabilizationBars;
#else
   int val = StabilizationBars;
   return (val < 1) ? 1 : val;
#endif
}

inline int Config_GetStabilizationLookbackBars()
{
#ifdef RPEA_TEST_RUNNER
   return StabilizationLookbackBars;
#else
   int val = StabilizationLookbackBars;
   return (val < 1) ? 1 : val;
#endif
}

inline int Config_GetNewsCalendarLookbackHours()
{
#ifdef RPEA_TEST_RUNNER
   return NewsCalendarLookbackHours;
#else
   return Config_ClampNonNegativeInt(NewsCalendarLookbackHours);
#endif
}

inline int Config_GetNewsCalendarLookaheadHours()
{
#ifdef RPEA_TEST_RUNNER
   return NewsCalendarLookaheadHours;
#else
   int val = NewsCalendarLookaheadHours;
   return (val < 1) ? 1 : val;
#endif
}

//------------------------------------------------------------------------------
// Spread/slippage: clamp to >= 0
//------------------------------------------------------------------------------

inline int Config_GetMaxSlippagePoints()
{
#ifdef RPEA_TEST_RUNNER
   return MaxSlippagePoints;
#else
   return Config_ClampNonNegativeInt(MaxSlippagePoints);
#endif
}

inline int Config_GetMaxSpreadPoints()
{
#ifdef RPEA_TEST_RUNNER
   return MaxSpreadPoints;
#else
   return Config_ClampNonNegativeInt(MaxSpreadPoints);
#endif
}

//------------------------------------------------------------------------------
// Queue/logging sizes: clamp to >= 1
//------------------------------------------------------------------------------

inline int Config_GetMaxQueueSize()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef MaxQueueSize
      return MaxQueueSize;
   #else
      return DEFAULT_MaxQueueSize;
   #endif
#else
   int val = MaxQueueSize;
   return (val < 1) ? DEFAULT_MaxQueueSize : val;
#endif
}

inline int Config_GetLogBufferSize()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef LogBufferSize
      return LogBufferSize;
   #else
      return DEFAULT_LogBufferSize;
   #endif
#else
   int val = LogBufferSize;
   return (val < 1) ? DEFAULT_LogBufferSize : val;
#endif
}

//------------------------------------------------------------------------------
// Leverage overrides: 0 = use account, otherwise [1, 1000]
//------------------------------------------------------------------------------

inline int Config_GetLeverageOverrideFX()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef LeverageOverrideFX
      return LeverageOverrideFX;
   #else
      return 50;
   #endif
#else
   int val = LeverageOverrideFX;
   if(val == 0) return 0; // Use account leverage
   if(val < 1) return 1;
   if(val > 1000) return 1000;
   return val;
#endif
}

inline int Config_GetLeverageOverrideMetals()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef LeverageOverrideMetals
      return LeverageOverrideMetals;
   #else
      return 20;
   #endif
#else
   int val = LeverageOverrideMetals;
   if(val == 0) return 0; // Use account leverage
   if(val < 1) return 1;
   if(val > 1000) return 1000;
   return val;
#endif
}

//------------------------------------------------------------------------------
// Position/order caps: >= 0 (0 = unlimited)
//------------------------------------------------------------------------------

inline int Config_GetMaxOpenPositionsTotal()
{
#ifdef RPEA_TEST_RUNNER
   return MaxOpenPositionsTotal;
#else
   int val = MaxOpenPositionsTotal;
   return (val < 0) ? 0 : val;
#endif
}

inline int Config_GetMaxOpenPerSymbol()
{
#ifdef RPEA_TEST_RUNNER
   return MaxOpenPerSymbol;
#else
   int val = MaxOpenPerSymbol;
   return (val < 0) ? 0 : val;
#endif
}

inline int Config_GetMaxPendingsPerSymbol()
{
#ifdef RPEA_TEST_RUNNER
   return MaxPendingsPerSymbol;
#else
   int val = MaxPendingsPerSymbol;
   return (val < 0) ? 0 : val;
#endif
}

//==============================================================================
// M6-Task01: Main Validation Function
// Called early in OnInit before any trading logic.
// Returns false on fatal errors (fail-fast), true otherwise.
// Logs all clamping actions with [Config] prefix.
//==============================================================================

#ifndef RPEA_TEST_RUNNER
inline bool Config_ValidateInputs()
{
   bool valid = true;
   
   //==========================================================================
   // FAIL-FAST CHECKS: Return INIT_FAILED if any of these fail
   //==========================================================================
   
   // InpSymbols must not be empty
   if(StringLen(InpSymbols) == 0)
   {
      Config_LogFatal("InpSymbols", "is empty - at least one symbol required");
      valid = false;
   }
   
   // DailyLossCapPct must be > 0
   if(DailyLossCapPct <= 0)
   {
      Config_LogFatal("DailyLossCapPct", StringFormat("must be > 0 (got %.4f)", DailyLossCapPct));
      valid = false;
   }
   
   // OverallLossCapPct must be > 0
   if(OverallLossCapPct <= 0)
   {
      Config_LogFatal("OverallLossCapPct", StringFormat("must be > 0 (got %.4f)", OverallLossCapPct));
      valid = false;
   }
   
   // TargetProfitPct must be > 0
   if(TargetProfitPct <= 0)
   {
      Config_LogFatal("TargetProfitPct", StringFormat("must be > 0 (got %.4f)", TargetProfitPct));
      valid = false;
   }

   // NewsAccountMode must be 0 (auto), 1 (master), or 2 (eval)
   if(NewsAccountMode < 0 || NewsAccountMode > 2)
   {
      Config_LogFatal("NewsAccountMode", StringFormat("invalid value %d (expected 0, 1, or 2)", NewsAccountMode));
      valid = false;
   }
   
   // Early exit if critical failures
   if(!valid)
      return false;
   
   //==========================================================================
   // CLAMP WARNINGS: Log all values that will be clamped at runtime
   //==========================================================================
   
   // ORMinutes must be one of {30, 45, 60, 75}
   if(ORMinutes != 30 && ORMinutes != 45 && ORMinutes != 60 && ORMinutes != 75)
   {
      int nearest = Config_NearestORMinutes(ORMinutes);
      Config_LogWarn("ORMinutes", StringFormat("%d not in {30,45,60,75}, will use %d", ORMinutes, nearest));
   }
   
   // OverallLossCapPct < DailyLossCapPct: clamp daily down
   if(OverallLossCapPct < DailyLossCapPct)
   {
      Config_LogWarn("DailyLossCapPct", StringFormat("%.2f > OverallLossCapPct %.2f, will clamp daily to %.2f",
                     DailyLossCapPct, OverallLossCapPct, OverallLossCapPct));
   }
   
   // MinTradeDaysRequired >= 1
   if(MinTradeDaysRequired < 1)
   {
      Config_LogClampInt("MinTradeDaysRequired", MinTradeDaysRequired, 1);
   }
   
   // RiskPct range [0.8, 2.0]
   if(RiskPct < 0.8 || RiskPct > 2.0)
   {
      double clamped = (RiskPct < 0.8) ? 0.8 : 2.0;
      Config_LogClampDouble("RiskPct", RiskPct, clamped);
   }

   // MicroRiskPct range [0.05, 0.20]
   if(MicroRiskPct < 0.05 || MicroRiskPct > 0.20)
   {
      double clamped = (MicroRiskPct < 0.05) ? 0.05 : 0.20;
      Config_LogClampDouble("MicroRiskPct", MicroRiskPct, clamped);
   }

   // RtargetBC range [1.8, 2.6]
   if(RtargetBC < 1.8 || RtargetBC > 2.6)
   {
      double clamped = (RtargetBC < 1.8) ? 1.8 : 2.6;
      Config_LogClampDouble("RtargetBC", RtargetBC, clamped);
   }

   // RtargetMSC range [1.6, 2.4]
   if(RtargetMSC < 1.6 || RtargetMSC > 2.4)
   {
      double clamped = (RtargetMSC < 1.6) ? 1.6 : 2.4;
      Config_LogClampDouble("RtargetMSC", RtargetMSC, clamped);
   }

   // SLmult range [0.7, 1.3]
   if(SLmult < 0.7 || SLmult > 1.3)
   {
      double clamped = (SLmult < 0.7) ? 0.7 : 1.3;
      Config_LogClampDouble("SLmult", SLmult, clamped);
   }

   // TrailMult range [0.6, 1.2]
   if(TrailMult < 0.6 || TrailMult > 1.2)
   {
      double clamped = (TrailMult < 0.6) ? 0.6 : 1.2;
      Config_LogClampDouble("TrailMult", TrailMult, clamped);
   }

   // GivebackCapDayPct range [0.25, 0.50]
   if(GivebackCapDayPct < 0.25 || GivebackCapDayPct > 0.50)
   {
      double clamped = (GivebackCapDayPct < 0.25) ? 0.25 : 0.50;
      Config_LogClampDouble("GivebackCapDayPct", GivebackCapDayPct, clamped);
   }
   
   // OneAndDoneR range [0.5, 5.0]
   if(OneAndDoneR < 0.5 || OneAndDoneR > 5.0)
   {
      double clamped = (OneAndDoneR < 0.5) ? 0.5 : 5.0;
      Config_LogClampDouble("OneAndDoneR", OneAndDoneR, clamped);
   }
   
   // Session hours [0, 23]
   if(StartHourLO < 0 || StartHourLO > 23)
   {
      Config_LogClampInt("StartHourLO", StartHourLO, Config_ClampHour(StartHourLO));
   }
   if(StartHourNY < 0 || StartHourNY > 23)
   {
      Config_LogClampInt("StartHourNY", StartHourNY, Config_ClampHour(StartHourNY));
   }
   if(CutoffHour < 0 || CutoffHour > 23)
   {
      Config_LogClampInt("CutoffHour", CutoffHour, Config_ClampHour(CutoffHour));
   }
   
   // MicroTimeStopMin range [30, 60]
   if(MicroTimeStopMin < 30 || MicroTimeStopMin > 60)
   {
      int clamped = (MicroTimeStopMin < 30) ? 30 : 60;
      Config_LogClampInt("MicroTimeStopMin", MicroTimeStopMin, clamped);
   }
   
   // Time windows >= 0
   if(MinHoldSeconds < 0)
      Config_LogClampInt("MinHoldSeconds", MinHoldSeconds, 0);
   if(NewsBufferS < 0)
      Config_LogClampInt("NewsBufferS", NewsBufferS, 0);
   if(QueueTTLMinutes < 0)
      Config_LogClampInt("QueueTTLMinutes", QueueTTLMinutes, 0);
   if(StabilizationTimeoutMin < 0)
      Config_LogClampInt("StabilizationTimeoutMin", StabilizationTimeoutMin, 0);
   if(StabilizationBars < 1)
      Config_LogClampInt("StabilizationBars", StabilizationBars, 1);
   if(StabilizationLookbackBars < 1)
      Config_LogClampInt("StabilizationLookbackBars", StabilizationLookbackBars, 1);
   if(NewsCalendarLookbackHours < 0)
      Config_LogClampInt("NewsCalendarLookbackHours", NewsCalendarLookbackHours, 0);
   if(NewsCalendarLookaheadHours < 1)
      Config_LogClampInt("NewsCalendarLookaheadHours", NewsCalendarLookaheadHours, 1);
   
   // Spread/slippage >= 0
   if(MaxSlippagePoints < 0)
      Config_LogClampInt("MaxSlippagePoints", MaxSlippagePoints, 0);
   if(MaxSpreadPoints < 0)
      Config_LogClampInt("MaxSpreadPoints", MaxSpreadPoints, 0);
   if(!MathIsValidNumber(SpreadMultATR) || SpreadMultATR <= 0.0)
      Config_LogClampDouble("SpreadMultATR", SpreadMultATR, DEFAULT_SpreadMultATR);
   
   // Queue/logging >= 1
   if(MaxQueueSize < 1)
      Config_LogClampInt("MaxQueueSize", MaxQueueSize, DEFAULT_MaxQueueSize);
   if(LogBufferSize < 1)
      Config_LogClampInt("LogBufferSize", LogBufferSize, DEFAULT_LogBufferSize);
   
   // Leverage overrides: 0 or [1, 1000]
   if(LeverageOverrideFX != 0 && (LeverageOverrideFX < 1 || LeverageOverrideFX > 1000))
   {
      int clamped = (LeverageOverrideFX < 1) ? 1 : 1000;
      Config_LogClampInt("LeverageOverrideFX", LeverageOverrideFX, clamped);
   }
   if(LeverageOverrideMetals != 0 && (LeverageOverrideMetals < 1 || LeverageOverrideMetals > 1000))
   {
      int clamped = (LeverageOverrideMetals < 1) ? 1 : 1000;
      Config_LogClampInt("LeverageOverrideMetals", LeverageOverrideMetals, clamped);
   }
   
   // Position/order caps >= 0
   if(MaxOpenPositionsTotal < 0)
      Config_LogClampInt("MaxOpenPositionsTotal", MaxOpenPositionsTotal, 0);
   if(MaxOpenPerSymbol < 0)
      Config_LogClampInt("MaxOpenPerSymbol", MaxOpenPerSymbol, 0);
   if(MaxPendingsPerSymbol < 0)
      Config_LogClampInt("MaxPendingsPerSymbol", MaxPendingsPerSymbol, 0);
   
   return true;
}
#endif // !RPEA_TEST_RUNNER

//------------------------------------------------------------------------------
// M7-Phase0: MR/Ensemble Config Getters
//------------------------------------------------------------------------------

inline bool Config_GetEnableMR()
{
#ifdef RPEA_TEST_RUNNER
   if(g_test_enable_mr_override_active)
      return g_test_enable_mr_override_value;
   #ifdef EnableMR
      return EnableMR;
   #else
      return true; // default enabled
   #endif
#else
   return EnableMR;
#endif
}

inline bool Config_GetUseBanditMetaPolicy()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef UseBanditMetaPolicy
      return UseBanditMetaPolicy;
   #else
      return true; // default enabled
   #endif
#else
   return UseBanditMetaPolicy;
#endif
}

inline bool Config_GetBanditShadowMode()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef BanditShadowMode
      return BanditShadowMode;
   #else
      return true; // default enabled (shadow mode on per workflow)
   #endif
#else
   return BanditShadowMode;
#endif
}

inline double Config_ClampAdaptiveRiskMultiplier(const double value, const double fallback)
{
   if(!MathIsValidNumber(value) || value <= 0.0)
      return fallback;

   double clamped = value;
   if(clamped < 0.25)
      clamped = 0.25;
   if(clamped > 2.50)
      clamped = 2.50;
   return clamped;
}

inline bool Config_GetEnableAdaptiveRisk()
{
#ifdef RPEA_TEST_RUNNER
   if(g_test_enable_adaptive_override_active)
      return g_test_enable_adaptive_override_value;
   #ifdef EnableAdaptiveRisk
      return EnableAdaptiveRisk;
   #else
      return DEFAULT_EnableAdaptiveRisk;
   #endif
#else
   return EnableAdaptiveRisk;
#endif
}

inline double Config_GetAdaptiveRiskMinMult()
{
#ifdef RPEA_TEST_RUNNER
   if(g_test_adaptive_bounds_override_active)
      return Config_ClampAdaptiveRiskMultiplier(g_test_adaptive_min_mult_override,
                                                DEFAULT_AdaptiveRiskMinMult);
   #ifdef AdaptiveRiskMinMult
      return Config_ClampAdaptiveRiskMultiplier(AdaptiveRiskMinMult,
                                                DEFAULT_AdaptiveRiskMinMult);
   #else
      return DEFAULT_AdaptiveRiskMinMult;
   #endif
#else
   return Config_ClampAdaptiveRiskMultiplier(AdaptiveRiskMinMult,
                                             DEFAULT_AdaptiveRiskMinMult);
#endif
}

inline double Config_GetAdaptiveRiskMaxMult()
{
#ifdef RPEA_TEST_RUNNER
   double configured_max = 0.0;
   if(g_test_adaptive_bounds_override_active)
      configured_max = g_test_adaptive_max_mult_override;
   else
   {
      #ifdef AdaptiveRiskMaxMult
         configured_max = AdaptiveRiskMaxMult;
      #else
         configured_max = DEFAULT_AdaptiveRiskMaxMult;
      #endif
   }
#else
   double configured_max = AdaptiveRiskMaxMult;
#endif

   double min_mult = Config_GetAdaptiveRiskMinMult();
   double max_mult = Config_ClampAdaptiveRiskMultiplier(configured_max,
                                                        DEFAULT_AdaptiveRiskMaxMult);
   if(max_mult < min_mult)
      max_mult = min_mult;
   return max_mult;
}

inline double Config_GetBWISCConfCut()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef BWISC_ConfCut
      return BWISC_ConfCut;
   #else
      return 0.70; // default
   #endif
#else
   return BWISC_ConfCut;
#endif
}

inline double Config_GetMRConfCut()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef MR_ConfCut
      return MR_ConfCut;
   #else
      return 0.80; // default
   #endif
#else
   return MR_ConfCut;
#endif
}

inline int Config_GetEMRTFastThresholdPct()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef EMRT_FastThresholdPct
      return EMRT_FastThresholdPct;
   #else
      return 40; // default
   #endif
#else
   return EMRT_FastThresholdPct;
#endif
}

inline double Config_GetCorrelationFallbackRho()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef CorrelationFallbackRho
      return CorrelationFallbackRho;
   #else
      return 0.50; // default per workflow
   #endif
#else
   return CorrelationFallbackRho;
#endif
}

inline double Config_GetMRRiskPctDefault()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef MR_RiskPct_Default
      double val = MR_RiskPct_Default;
   #else
      double val = 0.90;
   #endif
#else
   double val = MR_RiskPct_Default;
#endif
   // Clamp to [0.8, 1.0] per finalspec
   if(val < 0.8) return 0.8;
   if(val > 1.0) return 1.0;
   return val;
}

inline int Config_GetMRTimeStopMin()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef MR_TimeStopMin
      return MR_TimeStopMin;
   #else
      return 60; // default
   #endif
#else
   return MR_TimeStopMin;
#endif
}

inline int Config_GetMRTimeStopMax()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef MR_TimeStopMax
      return MR_TimeStopMax;
   #else
      return 90; // default
   #endif
#else
   return MR_TimeStopMax;
#endif
}

inline bool Config_GetMRLongOnly()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef MR_LongOnly
      return MR_LongOnly;
   #else
      return false; // default
   #endif
#else
   return MR_LongOnly;
#endif
}

inline bool Config_GetUseXAUEURProxy()
{
#ifdef RPEA_TEST_RUNNER
   #ifdef UseXAUEURProxy
      return UseXAUEURProxy;
   #else
      return true; // default
   #endif
#else
   return UseXAUEURProxy;
#endif
}

#endif // __MQL5__

#endif // CONFIG_MQH
