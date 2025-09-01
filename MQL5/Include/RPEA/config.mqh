#pragma once
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
