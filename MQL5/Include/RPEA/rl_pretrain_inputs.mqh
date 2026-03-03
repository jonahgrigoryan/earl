#ifndef RPEA_RL_PRETRAIN_INPUTS_MQH
#define RPEA_RL_PRETRAIN_INPUTS_MQH
// Defaults for input variables referenced by config.mqh when compiling scripts.

#ifndef DailyLossCapPct
#define DailyLossCapPct 4.0
#endif
#ifndef OverallLossCapPct
#define OverallLossCapPct 6.0
#endif
#ifndef MinTradeDaysRequired
#define MinTradeDaysRequired 3
#endif
#ifndef TradingEnabledDefault
#define TradingEnabledDefault true
#endif
#ifndef MarginLevelCritical
#define MarginLevelCritical 50.0
#endif
#ifndef EnableMarginProtection
#define EnableMarginProtection true
#endif
#ifndef MinRiskDollar
#define MinRiskDollar 10.0
#endif
#ifndef OneAndDoneR
#define OneAndDoneR 1.5
#endif
#ifndef NYGatePctOfDailyCap
#define NYGatePctOfDailyCap 0.50
#endif
#ifndef UseLondonOnly
#define UseLondonOnly false
#endif
#ifndef StartHourLO
#define StartHourLO 7
#endif
#ifndef StartHourNY
#define StartHourNY 12
#endif
#ifndef ORMinutes
#define ORMinutes 60
#endif
#ifndef CutoffHour
#define CutoffHour 16
#endif
#ifndef RiskPct
#define RiskPct 1.5
#endif
#ifndef MicroRiskPct
#define MicroRiskPct 0.10
#endif
#ifndef MicroTimeStopMin
#define MicroTimeStopMin 45
#endif
#ifndef GivebackCapDayPct
#define GivebackCapDayPct 0.50
#endif
#ifndef TargetProfitPct
#define TargetProfitPct 10.0
#endif
#ifndef NewsBufferS
#define NewsBufferS 300
#endif
#ifndef MaxSpreadPoints
#define MaxSpreadPoints 40
#endif
#ifndef MaxSlippagePoints
#define MaxSlippagePoints 10
#endif
#ifndef SpreadMultATR
#define SpreadMultATR 0.005
#endif
#ifndef MinHoldSeconds
#define MinHoldSeconds 120
#endif
#ifndef QueueTTLMinutes
#define QueueTTLMinutes 5
#endif
#ifndef MaxQueueSize
#define MaxQueueSize 1000
#endif
#ifndef EnableQueuePrioritization
#define EnableQueuePrioritization true
#endif
#ifndef EnableDetailedLogging
#define EnableDetailedLogging true
#endif
#ifndef LogBufferSize
#define LogBufferSize 1000
#endif
#ifndef AuditLogPath
#define AuditLogPath "RPEA/logs/"
#endif
#ifndef NewsCSVPath
#define NewsCSVPath "RPEA/news/calendar_high_impact.csv"
#endif
#ifndef NewsCSVMaxAgeHours
#define NewsCSVMaxAgeHours 24
#endif
#ifndef BudgetGateLockMs
#define BudgetGateLockMs 1000
#endif
#ifndef RiskGateHeadroom
#define RiskGateHeadroom 0.90
#endif
#ifndef StabilizationBars
#define StabilizationBars 3
#endif
#ifndef StabilizationTimeoutMin
#define StabilizationTimeoutMin 15
#endif
#ifndef SpreadStabilizationPct
#define SpreadStabilizationPct 60.0
#endif
#ifndef VolatilityStabilizationPct
#define VolatilityStabilizationPct 70.0
#endif
#ifndef StabilizationLookbackBars
#define StabilizationLookbackBars 60
#endif
#ifndef NewsCalendarLookbackHours
#define NewsCalendarLookbackHours 6
#endif
#ifndef NewsCalendarLookaheadHours
#define NewsCalendarLookaheadHours 24
#endif
#ifndef NewsAccountMode
#define NewsAccountMode 0
#endif
#ifndef MaxConsecutiveFailures
#define MaxConsecutiveFailures 3
#endif
#ifndef FailureWindowSec
#define FailureWindowSec 900
#endif
#ifndef CircuitBreakerCooldownSec
#define CircuitBreakerCooldownSec 120
#endif
#ifndef SelfHealRetryWindowSec
#define SelfHealRetryWindowSec 300
#endif
#ifndef SelfHealMaxAttempts
#define SelfHealMaxAttempts 2
#endif
#ifndef ErrorAlertThrottleSec
#define ErrorAlertThrottleSec 60
#endif
#ifndef BreakerProtectiveExitBypass
#define BreakerProtectiveExitBypass true
#endif
#ifndef EnablePerfProfiling
#define EnablePerfProfiling false
#endif
#ifndef UseServerMidnightBaseline
#define UseServerMidnightBaseline true
#endif
#ifndef ServerToCEST_OffsetMinutes
#define ServerToCEST_OffsetMinutes 0
#endif
#ifndef InpSymbols
#define InpSymbols "EURUSD;XAUUSD"
#endif
#ifndef UseXAUEURProxy
#define UseXAUEURProxy true
#endif
#ifndef LeverageOverrideFX
#define LeverageOverrideFX 50
#endif
#ifndef LeverageOverrideMetals
#define LeverageOverrideMetals 20
#endif
#ifndef SyntheticBarCacheSize
#define SyntheticBarCacheSize 1000
#endif
#ifndef ForwardFillGaps
#define ForwardFillGaps true
#endif
#ifndef MaxGapBars
#define MaxGapBars 5
#endif
#ifndef QuoteMaxAgeMs
#define QuoteMaxAgeMs 5000
#endif
#ifndef RtargetBC
#define RtargetBC 2.2
#endif
#ifndef RtargetMSC
#define RtargetMSC 2.0
#endif
#ifndef SLmult
#define SLmult 1.0
#endif
#ifndef TrailMult
#define TrailMult 0.8
#endif
#ifndef EntryBufferPoints
#define EntryBufferPoints 3
#endif
#ifndef MinStopPoints
#define MinStopPoints 1
#endif
#ifndef MagicBase
#define MagicBase 990200
#endif
#ifndef MaxOpenPositionsTotal
#define MaxOpenPositionsTotal 2
#endif
#ifndef MaxOpenPerSymbol
#define MaxOpenPerSymbol 1
#endif
#ifndef MaxPendingsPerSymbol
#define MaxPendingsPerSymbol 2
#endif
#ifndef EnableMR
#define EnableMR true
#endif
#ifndef EnableMRBypassOnRLUnloaded
#define EnableMRBypassOnRLUnloaded false
#endif
#ifndef UseBanditMetaPolicy
#define UseBanditMetaPolicy true
#endif
#ifndef BanditShadowMode
#define BanditShadowMode true
#endif
#ifndef EnableAnomalyDetector
#define EnableAnomalyDetector true
#endif
#ifndef AnomalyShadowMode
#define AnomalyShadowMode true
#endif
#ifndef AnomalyShockSigmaThreshold
#define AnomalyShockSigmaThreshold 5.5
#endif
#ifndef AnomalyEWMAAlpha
#define AnomalyEWMAAlpha 0.20
#endif
#ifndef AnomalyMinSamples
#define AnomalyMinSamples 20
#endif
#ifndef EnableAdaptiveRisk
#define EnableAdaptiveRisk false
#endif
#ifndef AdaptiveRiskMinMult
#define AdaptiveRiskMinMult 0.80
#endif
#ifndef AdaptiveRiskMaxMult
#define AdaptiveRiskMaxMult 1.20
#endif
#ifndef BWISC_ConfCut
#define BWISC_ConfCut 0.70
#endif
#ifndef MR_ConfCut
#define MR_ConfCut 0.80
#endif
#ifndef EMRT_FastThresholdPct
#define EMRT_FastThresholdPct 40
#endif
#ifndef CorrelationFallbackRho
#define CorrelationFallbackRho 0.50
#endif
#ifndef MR_RiskPct_Default
#define MR_RiskPct_Default 0.90
#endif
#ifndef MR_TimeStopMin
#define MR_TimeStopMin 60
#endif
#ifndef MR_TimeStopMax
#define MR_TimeStopMax 90
#endif
#ifndef MR_LongOnly
#define MR_LongOnly false
#endif
#ifndef MR_UseLogRatio
#define MR_UseLogRatio true
#endif
#ifndef EMRT_ExtremeThresholdMult
#define EMRT_ExtremeThresholdMult 2.0
#endif
#ifndef EMRT_VarCapMult
#define EMRT_VarCapMult 2.5
#endif
#ifndef EMRT_BetaGridMin
#define EMRT_BetaGridMin -2.0
#endif
#ifndef EMRT_BetaGridMax
#define EMRT_BetaGridMax 2.0
#endif
#ifndef QL_LearningRate
#define QL_LearningRate 0.10
#endif
#ifndef QL_DiscountFactor
#define QL_DiscountFactor 0.99
#endif
#ifndef QL_EpsilonTrain
#define QL_EpsilonTrain 0.10
#endif
#ifndef QL_TrainingEpisodes
#define QL_TrainingEpisodes 10000
#endif
#ifndef QL_SimulationPaths
#define QL_SimulationPaths 1000
#endif

#endif // RPEA_RL_PRETRAIN_INPUTS_MQH
