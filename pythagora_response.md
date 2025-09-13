# RPEA M1 Skeleton - MetaTrader 5 Expert Advisor Application Specification

## Application Overview

The RPEA (RapidPass Expert Advisor) M1 Skeleton is a foundational MetaTrader 5 Expert Advisor that creates a complete infrastructure backbone for monitoring automated forex trading systems. This application focuses exclusively on building a compile-ready framework with comprehensive monitoring capabilities - it contains no actual trading functionality and makes no trading calls whatsoever.

## What This Application Does

The RPEA M1 Skeleton establishes a robust monitoring and infrastructure framework for future automated trading system development. It creates a comprehensive file organization system, persistent state management, and continuous system health monitoring without executing any trades or market orders.

### Core Application Capabilities

**Infrastructure Management**

* Automatically creates a complete directory structure following exact specifications on first run
* Establishes persistent state management that survives application restarts and platform shutdowns
* Sets up comprehensive logging system for continuous system monitoring and audit trails
* Maintains organized file structure for future feature expansion

**Continuous System Monitoring**

* Runs heartbeat monitoring every 30 seconds consistently
* Logs detailed system status to structured CSV files with predefined exact schema
* Tracks account information and system state without any trading actions or market interactions
* Creates daily rotating log files with standardized naming conventions

**News Calendar Framework**

* Parses high-impact economic news calendar data from CSV files when present
* Provides IsNewsBlocked() function framework that returns false (no enforcement in M1)
* Maintains news awareness infrastructure without any trading restrictions or enforcement
* Handles missing or malformed news data gracefully

**Time Management System**

* Handles server time to CEST conversion using manual offset configuration only
* Provides session management framework with interval-based session detection
* User-configurable time offset through input parameters (no automatic DST detection)
* Consistent timestamp handling using UNIX epoch format

## User Experience and Interface

### Initial Setup and Installation

**Getting Started**

1. User places the compiled RPEA.mq5 file in MetaTrader 5's `Experts/FundingPips/` directory
2. User opens MetaEditor and compiles the Expert Advisor (must achieve zero compilation errors)
3. User drags and drops the EA onto any chart in MetaTrader 5 platform
4. Application automatically creates the complete `MQL5/Files/RPEA/` directory structure silently
5. System displays confirmation messages in the MetaTrader 5 Experts tab

**First Run Experience**

* Upon first attachment, the application creates all required directories and subdirectories automatically
* System initializes `challenge_state.json` and `intents.json` files in the state directory with default values
* Heartbeat logging begins immediately with an INIT entry in the daily CSV log
* 30-second timer starts automatically for consistent monitoring cadence
* User sees real-time status updates in the MetaTrader 5 platform interface

### Daily Operation and Monitoring

**Continuous Background Operation**

* Every 30 seconds precisely, the system writes a heartbeat entry to the current daily CSV log file
* Log entries follow the exact schema: `timestamp,account,symbol,baseline_today,room_today,room_overall,existing_risk,planned_risk,action,reason`
* Example heartbeat entry: `1717075200,12345678,,0,0,0,0,0,HEARTBEAT,INIT` or `1717075200,12345678,,0,0,0,0,0,HEARTBEAT,TIMER`
* Daily log files use standardized naming: `decisions_YYYYMMDD.csv` with automatic date rotation
* Users can monitor system health through continuously updating log files

**Configuration and Settings**

* Users modify application parameters through MetaTrader 5's built-in input parameter interface
* Primary setting: `ServerToCEST_OffsetMinutes` for manual time zone offset configuration (no automatic DST)
* Risk management parameters available as input fields (display only, no enforcement in M1)
* Session timing parameters for future London/New York session management
* All parameter changes require EA restart to take effect

**File Organization and Access**

* System organizes all data under the main `MQL5/Files/RPEA/` directory structure
* Subdirectories created for logs, state files, news data, and future feature expansion
* State files maintain JSON format for easy manual inspection and debugging
* CSV log files compatible with spreadsheet applications for analysis and reporting

### System Monitoring and Maintenance

**Log File Management**

* Users access operational logs through the `MQL5/Files/RPEA/logs/` directory
* Each day automatically creates a new decision log file with timestamped heartbeat entries
* CSV format allows direct import into Excel, Google Sheets, or other analysis tools
* Historical logs preserved for long-term system monitoring and audit trails

**State File Management**

* System maintains challenge state in `challenge_state.json` file with persistent storage
* Intent tracking stored in `intents.json` file for future decision-making capabilities
* JSON format enables easy manual inspection, backup, and debugging
* State information includes account tracking and operational parameters

**News Calendar Integration**

* Users can optionally place `calendar_high_impact.csv` file in `MQL5/Files/RPEA/news/` directory
* System automatically detects and parses news data using built-in CSV parser
* `IsNewsBlocked()` function provides framework foundation (returns false in M1, no enforcement)
* Graceful handling of missing news files or malformed data

## Core Application Features

### Infrastructure and File System Management

* **Automatic Directory Creation**: Complete folder structure creation on first application run
* **File System Initialization**: Creates all required state and configuration files with proper defaults
* **Robust Error Handling**: Comprehensive file system operations with proper error checking and recovery
* **Clean Application Lifecycle**: Ensures all components initialize and shutdown correctly

### Heartbeat Monitoring System

* **Precise Timer Operation**: Consistent 30-second intervals using EventSetTimer(30) for regular monitoring
* **Structured Data Logging**: Exact CSV schema compliance with predefined column headers
* **Account Information Tracking**: Logs account number and comprehensive system state information
* **Minimal Resource Usage**: Optimized operations designed for negligible performance impact

### Persistent State Management

* **Challenge State Tracking**: Maintains trading challenge progress and configuration information
* **JSON Data Format**: Human-readable state files for easy inspection and debugging
* **Automatic State Recovery**: Loads existing state information on application restart
* **Data Integrity Validation**: Validates state data consistency on load and save operations

### News Calendar Infrastructure

* **CSV Data Parser**: Processes high-impact economic calendar data from structured files
* **Symbol-Aware Processing**: Links news events to specific trading symbols and timeframes
* **Time-Based Query Framework**: `IsNewsBlocked()` function foundation for future implementation
* **Fallback System Design**: Handles missing, corrupted, or malformed news data gracefully

### Time Management Utilities

* **Manual Offset Configuration**: User-configurable `ServerToCEST_OffsetMinutes` parameter (no automatic DST)
* **Time Zone Conversion**: Server time to CEST conversion utilities with manual offset only
* **Session Detection Framework**: InSession(t0, ORMinutes) interval-based session management
* **Consistent Timestamp Formatting**: Standardized UNIX epoch timestamp handling throughout

### Configuration and Parameter System

* **MetaTrader 5 Input Interface**: Native platform input parameter interface for user settings
* **Risk Management Parameters**: Daily loss caps, risk percentages (input display only, no enforcement)
* **Trading Constraint Framework**: Position limits, minimum days (framework preparation only)
* **News Integration Settings**: Buffer periods and blocking parameters (no enforcement in M1)

## Required Application Structure

### Expert Advisor File Location

* `Experts/FundingPips/RPEA.mq5` - Main Expert Advisor application file

### Include Files Organization

* `Include/RPEA/config.mqh` - Configuration management and parameter handling
* `Include/RPEA/state.mqh` - State persistence and JSON file management
* `Include/RPEA/timeutils.mqh` - Time conversion utilities and session management
* `Include/RPEA/sessions.mqh` - Session detection and timing framework
* `Include/RPEA/indicators.mqh` - Technical indicator framework preparation
* `Include/RPEA/persistence.mqh` - File I/O operations and data management
* `Include/RPEA/logging.mqh` - Logging system implementation and CSV handling
* `Include/RPEA/news.mqh` - News calendar parsing and IsNewsBlocked() framework

### Data Directory Structure

* `Files/RPEA/state/` - Challenge state and intent JSON files
* `Files/RPEA/logs/` - Daily decision logs and heartbeat monitoring files
* `Files/RPEA/news/` - Economic calendar data files (optional user-provided)
* `Files/RPEA/emrt/` - Future EMRT model data storage
* `Files/RPEA/qtable/` - Future Q-learning table storage
* `Files/RPEA/bandit/` - Future multi-armed bandit algorithm data
* `Files/RPEA/liquidity/` - Future liquidity analysis data storage
* `Files/RPEA/calibration/` - Future model calibration data
* `Files/RPEA/sets/` - Future strategy parameter sets
* `Files/RPEA/strategy_tester/` - Future backtesting data storage
* `Files/RPEA/reports/` - Future performance reports and analytics

## Technical Implementation Requirements

### MetaTrader 5 Platform Compliance

* Must compile with zero errors in MetaEditor environment
* Full compatibility with Strategy Tester environment for future features
* Proper handling of EA lifecycle events (OnInit, OnTimer, OnDeinit)
* Clean initialization and shutdown procedures with resource management

### Performance and Stability Standards

* Negligible CPU usage during continuous operation
* Stable memory footprint during extended runtime periods
* Efficient file I/O operations with minimal disk access overhead
* Responsive timer-based operations maintaining consistent 30-second intervals

### Data Format and Standards Compliance

* CSV files must follow exact schema specification with precise column headers
* JSON state files maintain consistent formatting and structure
* UNIX epoch timestamps for all time-based data throughout the application
* Standardized file naming conventions with date-based rotation

### Core Application Wiring Requirements

* **OnInit Function**: Ensure all directories exist, load or create state files, initialize logging system, start 30-second timer with EventSetTimer(30)
* **OnTimer Function**: Append heartbeat row to current daily CSV log file with exact schema compliance
* **OnDeinit Function**: Stop timer, flush all log buffers, perform clean shutdown procedures

## Third-Party Technologies and Tools

### MetaTrader 5 Trading Platform

**Purpose**: Primary application platform and development environment

* **MetaEditor IDE**: Integrated development environment for MQL5 code compilation and debugging
* **Expert Advisor Framework**: Standard EA lifecycle management system with event handling
* **File System Access**: MQL5/Files directory structure for organized data storage and retrieval
* **Timer System**: Platform-provided EventSetTimer functionality for scheduled monitoring operations
* **Input Parameter Interface**: Built-in user interface system for configuration management and settings

### MQL5 Programming Language

**Purpose**: Native MetaTrader 5 programming language and runtime environment

* **Include System**: Modular code organization through .mqh header files and libraries
* **File I/O Functions**: Built-in FileOpen, FileWrite, FileRead, FileClose capabilities for data management
* **Time Management Functions**: Platform time utilities and conversion functions for timestamp handling
* **Event Handling System**: OnInit, OnTimer, OnDeinit event system for application lifecycle management
* **String Processing**: Built-in string manipulation functions for CSV parsing and data processing

### CSV Data Format Standard

**Purpose**: Structured data storage for monitoring logs and news calendar integration

* **Decision Log Format**: Standardized schema for heartbeat monitoring and system status tracking
* **News Calendar Format**: High-impact economic events in structured CSV format for parsing
* **Schema Compliance**: Exact column definitions ensuring data consistency and compatibility
* **Spreadsheet Compatibility**: Direct import capability into Excel, Google Sheets, and similar applications

### JSON Data Format Standard

**Purpose**: State persistence and configuration storage with human-readable format

* **Challenge State Storage**: Trading challenge progress, parameters, and configuration data
* **Intent File Management**: Future decision-making state storage and tracking capabilities
* **Human-Readable Format**: Easy manual inspection, debugging, and configuration management
* **Cross-Platform Compatibility**: Standard format for data exchange, backup, and restoration

## Application Completion Criteria

The M1 Skeleton application is considered complete and ready for use when:

1. **Zero Compilation Errors**: RPEA.mq5 compiles successfully with zero errors in MetaEditor
2. **Automatic Directory Creation**: All `Files/RPEA/*` directories and subdirectories created automatically on first attachment
3. **Consistent Heartbeat Logging**: Heartbeat entries appear in daily CSV files every 30 seconds with exact schema compliance
4. **News Integration Framework**: `news.mqh` parses CSV files without errors and `IsNewsBlocked()` function compiles and returns false
5. **Optimal Performance**: CPU usage remains negligible during continuous operation with stable memory usage
6. **Clean Application Lifecycle**: EA performs proper initialization and clean deinitialization when attached or removed from charts
7. **State Persistence**: Challenge state and intent files created and maintained correctly across application restarts
8. **No Trading Functionality**: Confirmed absence of any OrderSend, OrderSendAsync, PositionOpen, OrderCheck, or similar trading calls

This M1 Skeleton provides a complete infrastructure foundation for future development phases while maintaining strict focus on monitoring, framework establishment, and system health tracking without any trading functionality or market interaction capabilities.