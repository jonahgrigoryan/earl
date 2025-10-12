#!/bin/bash
set -euo pipefail

REPO_ROOT="${EARL_ROOT:-/workspace/earl}"
if [ -f "${REPO_ROOT}/.env" ]; then
    # shellcheck disable=SC1090
    source "${REPO_ROOT}/.env"
fi

MQ5_FILE="${1:-${REPO_ROOT}/MQL5/Experts/FundingPips/RPEA.mq5}"

if [ ! -f "$MQ5_FILE" ]; then
    echo "❌ File not found: $MQ5_FILE"
    exit 1
fi

DEFAULT_WINEPREFIX="/workspace/.wine-mt5"
DEFAULT_MT5_TERMINAL="/workspace/mt5/terminal"

VALIDATION_ONLY="${VALIDATION_ONLY_MODE:-false}"
WINE_AVAILABLE_FLAG="${WINE_AVAILABLE:-unknown}"
ARCHITECTURE="${ARCH:-$(uname -m)}"

resolve_metaeditor() {
    if [ -n "${METAEDITOR_PATH:-}" ] && [ -f "$METAEDITOR_PATH" ]; then
        echo "$METAEDITOR_PATH"
        return 0
    fi

    local mt5_root="${MT5_TERMINAL_PATH:-$DEFAULT_MT5_TERMINAL}"
    local candidates=(
        "$mt5_root/metaeditor64.exe"
        "$mt5_root/metaeditor.exe"
        "/workspace/mt5/MetaTrader 5/metaeditor64.exe"
        "/workspace/.wine-mt5/drive_c/Program Files/MetaTrader 5/metaeditor64.exe"
    )

    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

run_validation_only() {
    local reason="$1"
    echo "⚠️  Running in VALIDATION-ONLY mode (${reason})"
    echo "    Actual compilation requires MetaEditor + Wine (x86_64)"
    echo ""
    echo "Performing static code validation instead..."
    echo ""

    echo "✅ File exists: $MQ5_FILE"
    echo ""
    echo "==> Checking MQL5 syntax patterns..."

    local errors=0
    local open_braces close_braces
    open_braces=$(grep -o '{' "$MQ5_FILE" | wc -l)
    close_braces=$(grep -o '}' "$MQ5_FILE" | wc -l)
    if [ "$open_braces" -ne "$close_braces" ]; then
        echo "❌ Brace mismatch: $open_braces open, $close_braces close"
        errors=$((errors + 1))
    else
        echo "✅ Braces balanced: $open_braces pairs"
    fi

    local required_includes=("config.mqh" "state.mqh" "order_engine.mqh")
    for inc in "${required_includes[@]}"; do
        if grep -q "#include.*$inc" "$MQ5_FILE"; then
            echo "✅ Found include: $inc"
        else
            echo "⚠️  Missing include: $inc"
        fi
    done

    local event_handlers=("OnInit" "OnDeinit" "OnTimer" "OnTradeTransaction")
    for handler in "${event_handlers[@]}"; do
        if grep -q "^void $handler\|^int $handler" "$MQ5_FILE" "$REPO_ROOT"/MQL5/Include/RPEA/*.mqh 2>/dev/null; then
            echo "✅ Found handler: $handler"
        else
            echo "⚠️  Handler not found: $handler"
        fi
    done

    echo ""
    if [ $errors -eq 0 ]; then
        echo "✅ Validation passed (syntax checks only)"
        echo ""
        echo "To compile for real:" \
             " ensure Wine + MetaEditor are installed and rerun the script."
        exit 0
    else
        echo "❌ Validation found $errors issue(s)"
        exit 1
    fi
}

if [ "$VALIDATION_ONLY" = "true" ]; then
    run_validation_only "VALIDATION_ONLY_MODE=true"
fi

if [ "$ARCHITECTURE" != "x86_64" ]; then
    run_validation_only "Unsupported architecture: $ARCHITECTURE"
fi

if ! command -v wine >/dev/null 2>&1; then
    run_validation_only "Wine binary not available"
fi

if [ "$WINE_AVAILABLE_FLAG" = "false" ]; then
    run_validation_only "Wine reported unavailable"
fi

METAEDITOR=$(resolve_metaeditor || true)
if [ -z "$METAEDITOR" ]; then
    run_validation_only "MetaEditor executable not found"
fi

export WINEPREFIX="${WINEPREFIX:-$DEFAULT_WINEPREFIX}"
export MT5_TERMINAL_PATH="${MT5_TERMINAL_PATH:-$DEFAULT_MT5_TERMINAL}"

echo "==> Compiling with MetaEditor"
echo "    MQ5: $MQ5_FILE"
echo "    Wine prefix: $WINEPREFIX"
echo "    MetaEditor: $METAEDITOR"

WINDOWS_MQ5="E:${MQ5_FILE#${REPO_ROOT}}"
WINDOWS_MQ5=${WINDOWS_MQ5//\//\\}

BUILD_DIR="${REPO_ROOT}/build"
mkdir -p "$BUILD_DIR"
LOG_FILE="${BUILD_DIR}/RPEA_compile.log"
WINDOWS_LOG="E:${LOG_FILE#${REPO_ROOT}}"
WINDOWS_LOG=${WINDOWS_LOG//\//\\}

wine "$METAEDITOR" \
    /portable \
    /compile:"$WINDOWS_MQ5" \
    /log:"$WINDOWS_LOG"

if [ ! -f "$LOG_FILE" ]; then
    echo "❌ MetaEditor log not found at $LOG_FILE"
    exit 1
fi

echo "==> MetaEditor output"
tail -n 20 "$LOG_FILE"

if grep -q "error\(s\): 0" "$LOG_FILE" && grep -q "warning\(s\): 0" "$LOG_FILE"; then
    echo "✅ Compilation succeeded"
    exit 0
fi

if grep -qi "error" "$LOG_FILE"; then
    echo "❌ Compilation failed"
    exit 1
fi

echo "⚠️  Compilation completed with warnings"
exit 0
