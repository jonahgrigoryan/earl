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

// TODO[M1]: input range validation to be implemented in M6 (see finalspec.md)

//==============================================================================
// M3 - Order Engine and Synthetic Cross Support Configuration
//==============================================================================

// Order Engine Configuration
#define DEFAULT_MaxRetryAttempts              3
#define DEFAULT_InitialRetryDelayMs          300
#define DEFAULT_RetryBackoffMultiplier       2.0
#define DEFAULT_QueuedActionTTLMin           5
#define DEFAULT_MaxSlippagePoints            10.0
#define DEFAULT_MinHoldSeconds               120
#define DEFAULT_EnableExecutionLock          true
#define DEFAULT_PendingExpiryGraceSeconds    60
#define DEFAULT_AutoCancelOCOSibling         true
#define DEFAULT_OCOCancellationTimeoutMs     1000
#define DEFAULT_EnableRiskReductionSiblingCancel true
#define DEFAULT_EnableDetailedLogging        true
#define DEFAULT_AuditLogPath                 "Files/RPEA/logs/"
#define DEFAULT_LogBufferSize                1000

// Synthetic Manager Configuration
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

// News and Queue Configuration
#define DEFAULT_NewsCSVPath                  "Files/RPEA/news/calendar_high_impact.csv"
#define DEFAULT_NewsCSVMaxAgeHours           24
#define DEFAULT_BudgetGateLockMs             1000
#define DEFAULT_MaxQueueSize                 1000
#define DEFAULT_QueueTTLMinutes              5
#define DEFAULT_EnableQueuePrioritization    true

//==============================================================================
// M3 TODO: Implementation stubs for Order Engine interfaces
//==============================================================================

// TODO[M3]: Implement OrderEngine class with complete interface (see design.md)
// TODO[M3]: Implement SyntheticManager class with proxy/replication logic
// TODO[M3]: Implement RetryManager with MT5 error code mapping
// TODO[M3]: Implement AtomicOrderManager with counter-order rollback
// TODO[M3]: Implement PartialFillManager with OCO volume adjustment
// TODO[M3]: Implement BoundedQueueManager with news window queuing
// TODO[M3]: Implement BudgetGateManager with position snapshot locking
// TODO[M3]: Implement NewsCSVParser with schema validation
// TODO[M3]: Implement SyntheticPriceManager with quote staleness detection
// TODO[M3]: Implement ReplicationMarginCalculator with 20% buffer

#endif // CONFIG_MQH
