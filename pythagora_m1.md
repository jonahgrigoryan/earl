# Pythagora.ai Prompt for RPEA M1 Skeleton Implementation

## Project Overview

Create the M1 (Skeleton) for the MT5 Expert Advisor (MQL5). No trading logic yet; compile-ready scaffolding only.

Context files Pythagora must read before generation:
- finalspec.md (authoritative requirements)
- prd.md (product context)
- rpea_structure.txt (exact file layout)
- README.md (setup & CSV schemas)

## Constraints (Pythagora)

*Do*
- Generate only MQL5 files (.mq5 /.mqh) and data folders under `MQL5/Files/RPEA`.
- Follow `rpea_structure.txt` exactly for paths and names.
- Implement minimal wiring so it compiles, runs a timer, and writes heartbeat CSV.

*Don’t*
- No trading or order functions (`OrderSend`, `PositionOpen`, etc.).
- No non-MQL code, web servers, React/Node scaffolds.
- No strategy logic (BWISC/MR) in M1.

### If using Cosine to generate the structure
- Use `cosine.txt` as the generation prompt.
- Cosine must create only the file tree and empty files with header guards; no function bodies or trading calls.
- Accept `.gitkeep` for empty directories and header-only `.mqh` files.

## M1 Definition of Done
- Builds in MetaEditor with **0 errors**.
- On attach: creates required `MQL5/Files/RPEA/*` subfolders & state files.
- `EventSetTimer(30)` fires; `OnTimer` writes heartbeat row every 30–60 s.
- `news.mqh` parses `calendar_high_impact.csv` if present and exposes `IsNewsBlocked()` stub.
- Clean `OnDeinit` (kills timer, flushes logs). CPU use negligible.

## CSV Schemas

Heartbeat (`logs/decisions_YYYYMMDD.csv`)
```
timestamp,account,symbol,baseline_today,room_today,room_overall,existing_risk,planned_risk,action,reason
```
Example row:
```
1717075200,12345678,,0,0,0,0,0,HEARTBEAT,INIT
```

News fallback (`news/calendar_high_impact.csv`)
```
timestamp,impact,countries,symbols
```

## Core Files (Must Create)
1. `RPEA.mq5`
2. `config.mqh`
3. `state.mqh`
4. `persistence.mqh`
5. `logging.mqh`
6. `timeutils.mqh`
7. `sessions.mqh`
8. `indicators.mqh`
9. `news.mqh`

## Technical Stack & Architecture

### Language & Platform
- **Language**: MQL5 (MetaTrader 5 language)
- **Platform**: MetaTrader 5 Expert Advisor
- **File Extension**: `.mq5` for main EA, `.mqh` for include files

### Project Structure (CRITICAL - Must Match Exactly)
```
MQL5/
├── Experts/FundingPips/
│   └── RPEA.mq5                    # Main EA entry point
├── Include/RPEA/
│   ├── config.mqh                  # Input parameters and constants
│   ├── state.mqh                   # Persistent state management
│   ├── timeutils.mqh               # DST-aware time handling
│   ├── sessions.mqh                # Session predicates and OR windows
│   ├── indicators.mqh              # ATR/RSI/MA handles
│   ├── persistence.mqh             # State persistence and recovery
│   ├── logging.mqh                 # CSV audit and telemetry
│   └── news.mqh                    # Calendar API and CSV fallback
└── Files/RPEA/                     # Data directory (created at runtime)
    ├── state/                      # Persistent state files
    ├── logs/                       # Audit trails and decisions
    ├── news/                       # CSV news fallback
    ├── emrt/                       # EMRT cache (future)
    ├── qtable/                     # Q-learning tables (future)
    ├── bandit/                     # Contextual bandit (future)
    ├── liquidity/                  # Market microstructure (future)
    ├── calibration/                # Rolling parameter calibration (future)
    ├── sets/                       # Strategy Tester configurations (future)
    └── reports/                    # Generated reports (future)
```

## Core Features to Implement

### 1. Main EA Entry Point (RPEA.mq5)
```mql5
// Key components needed:
- Standard EA structure with OnInit(), OnDeinit(), OnTimer()
- Input parameter declarations
- Timer-based scheduling (30-60 second intervals)
- Basic state management
- Directory structure creation
- Clean shutdown procedures
```

### 2. Configuration System (config.mqh)
```mql5
// Essential input parameters:
input double DailyLossCapPct = 4.0;         // FundingPips default
input double OverallLossCapPct = 6.0;       
input int MinTradeDaysRequired = 3;
input double RiskPct = 1.5;                 // BWISC risk per trade
input double MR_RiskPct_Default = 0.90;     // MR risk (lower than BWISC)
input double RtargetBC = 2.2;               // Burst Capture target
input double RtargetMSC = 2.0;              // Mean-Shift Capture target
input int NewsBufferS = 300;                // Master: ±300s, Eval: internal buffer
input int ServerToCEST_OffsetMinutes = 0;   // DST handling (CRITICAL)
input string InpSymbols = "EURUSD;XAUUSD";  // Trading symbols
input bool UseXAUEURProxy = true;           // Synthetic pair mode
```

### 3. State Management (state.mqh)
```mql5
// Core state structure:
struct ChallengeState {
    double initial_baseline;     // Challenge starting baseline
    int gDaysTraded;            // Count of distinct trading days
    datetime last_counted_server_date; // Last trade day timestamp
    bool trading_enabled;       // Global trading flag
    bool micro_mode;           // Post-target micro trading mode
    double day_peak_equity;    // Peak equity for giveback calculation
};
```

### 4. Persistence System (persistence.mqh)
```mql5
// File operations for:
- JSON state file read/write operations
- Directory creation utilities
- Restart-safe state recovery
- Idempotent initialization
```

### 5. Logging Framework (logging.mqh)
```mql5
// CSV audit system:
- Heartbeat logging every timer tick
- Decision audit trails
- Structured log format with timestamps
- File rotation by date (YYYYMMDD)
```

### 6. News Compliance Stub (news.mqh)
```mql5
// Basic news handling:
- CSV parser for calendar_high_impact.csv
- IsNewsBlocked(symbol) function stub
- Schema: timestamp,impact,countries,symbols
- Account type differentiation (Master vs Evaluation)
```

### 7. Time Utilities (timeutils.mqh) - CRITICAL DST Feature
```mql5
// DST-aware time handling:
- Server to CEST time conversion
- Configurable offset handling (ServerToCEST_OffsetMinutes)
- Session boundary calculations
- Automatic daylight saving time detection capabilities
```

## Critical Implementation Requirements

### 🚨 **Locked Constraints (IMMUTABLE)**
These 11 decisions are **LOCKED** and must be preserved:

1. **News Policy**: Master accounts ±300s window, Evaluation internal buffer
2. **Session Order**: London first, then New York evaluation
3. **NY Gate Rule**: Allow NY only if day loss ≤ 50% of daily cap
4. **Position Caps**: MaxOpenPositionsTotal=2, MaxOpenPerSymbol=1, MaxPendingsPerSymbol=2
5. **Trading Day Counting**: First DEAL_ENTRY_IN between server midnights
6. **Kill-switch Floors**: DailyFloor/OverallFloor with immediate closure
7. **Session Window**: Interval-based, no hour-equality check
8. **Micro-fallback**: Only in Micro-Mode (post-target), never pre-target
9. **R/Win Calculation**: Persist {entry, sl, type} on open
10. **Helper Functions**: IsNewsBlocked(), EquityRoomAllowsNextTrade(), etc.
11. **DST Handling**: ServerToCEST_OffsetMinutes configurable offset

### 🎯 **Project Specification Priorities**

#### DST-Aware Session Handling (PRIORITY 1)
- Implement automatic daylight saving time detection in timeutils.mqh
- Flexible session definitions to prevent timing misalignment
- Server-to-CEST mapping with configurable offset

#### Parameter Stability Foundation
- Automated parameter validation and bounds checking
- Stability testing framework setup
- Rolling calibration preparation

### 🔧 **Technical Implementation Details**

#### File Organization Standards
- Use **#include** statements for modular architecture
- Follow MQL5 naming conventions (CamelCase for functions, snake_case for variables)
- Include proper header guards in .mqh files
- Use structured comments for function documentation

#### Error Handling Patterns
```mql5
// Implement retry/backoff for file operations
// Fail gracefully with meaningful error messages
// Log all initialization steps for debugging
```

#### Performance Requirements
- Timer frequency: 30-60 seconds
- CPU usage: <1% during skeleton phase
- Memory: Stable footprint, no memory leaks
- File I/O: Minimize during timer operations

## Sample Implementation Structure

### Main EA Template (RPEA.mq5)
```mql5
//+------------------------------------------------------------------+
//| RPEA.mq5 - FundingPips 10K RapidPass EA                        |
//| M1 Skeleton Implementation                                       |
//+------------------------------------------------------------------+

#include <RPEA/config.mqh>
#include <RPEA/state.mqh>
#include <RPEA/persistence.mqh>
#include <RPEA/logging.mqh>
#include <RPEA/timeutils.mqh>
#include <RPEA/news.mqh>

// Global state
ChallengeState g_challenge_state;
int g_timer_period = 30; // seconds

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Create directory structure
    // Load persistent state
    // Initialize logging system
    // Set up timer
    // Validate configuration
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Save state
    // Clean shutdown
    // Kill timer
}

//+------------------------------------------------------------------+
//| Timer function (main scheduler)                                 |
//+------------------------------------------------------------------+
void OnTimer() {
    // Write heartbeat log
    // Check news blocks
    // Update time-based state
    // No trading actions in M1
}
```

## Expected Deliverables

### Core Files (Must Create)
1. **RPEA.mq5** - Main Expert Advisor entry point
2. **config.mqh** - All input parameters and constants
3. **state.mqh** - Challenge state structure and management
4. **persistence.mqh** - File I/O and state persistence
5. **logging.mqh** - CSV audit logging system
6. **timeutils.mqh** - DST-aware time utilities
7. **news.mqh** - News compliance foundation

### Runtime Behavior
- Creates `MQL5/Files/RPEA/` directory tree on first run
- Initializes `state/challenge_state.json` with default values
- Writes heartbeat to `logs/decisions_YYYYMMDD.csv` every 30-60 seconds
- Parses `news/calendar_high_impact.csv` (if exists) without errors
- Handles EA attach/detach cycles gracefully

### Validation Criteria
- Compiles without errors in MetaEditor
- Passes Strategy Tester initialization
- Creates proper directory structure
- Maintains stable timer operation
- Logs structured audit data
- No trading operations executed

## Important Notes for Pythagora

1. **This is NOT a web application** - it's a MetaTrader 5 Expert Advisor using MQL5 language
2. **No React/Node.js** - Use MQL5 syntax and MT5 platform conventions
3. **File structure is critical** - Must match the specified MQL5 directory layout exactly
4. **Focus on foundation** - No complex trading logic in M1, just robust infrastructure
5. **DST awareness is mandatory** - This is a session-based trading system requiring precise timing
6. **Correlation monitoring preparation** - Set up framework for future synthetic pair correlation tracking
7. **All 11 locked constraints must be preserved** - These are immutable requirements

## Success Metrics

### M1 Complete When:
- ✅ All files compile successfully in MetaEditor
- ✅ Directory structure created automatically on first run
- ✅ State persistence works across EA restart cycles
- ✅ Timer operates consistently every 30-60 seconds
- ✅ Logging produces structured CSV audit trails
- ✅ News CSV parser handles basic schema without errors
- ✅ DST-aware time utilities provide configurable offset handling
- ✅ Zero trading actions executed (skeleton phase only)

This M1 skeleton will serve as the foundation for implementing the full BWISC+MR ensemble trading system with adaptive risk management, regime detection, and correlation monitoring in subsequent phases.