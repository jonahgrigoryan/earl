#!/bin/bash
set -euo pipefail

echo "==> RPEA Environment Maintenance"

EARL_ROOT="${EARL_ROOT:-/workspace/earl}"

# Check if we're in validation-only mode
if [ -f "${EARL_ROOT}/.env" ]; then
    # shellcheck disable=SC1090
    source "${EARL_ROOT}/.env"
    
    if [ "${VALIDATION_ONLY_MODE:-false}" = "true" ]; then
        reason=${VALIDATION_REASON:-"Wine/MT5 not available"}
        echo ""
        echo "⚠️  Running in VALIDATION-ONLY mode"
        echo "    Reason: ${reason}"
        echo "    Architecture: ${ARCH:-unknown}"
        echo "    Compilation: Not available (requires x86_64)"
        echo ""
        
        # Set basic environment variables
        export EARL_ROOT="${EARL_ROOT}"

        cat >> ~/.bashrc <<EOF
export EARL_ROOT=${EARL_ROOT}
export VALIDATION_ONLY_MODE=true
EOF
        
        echo "✅ Maintenance complete (validation-only mode)"
        echo ""
        echo "Available commands:"
        echo "  ./scripts/compile_rpea.sh  - Validate code structure (no actual compilation)"
        echo ""
        exit 0
    fi
fi

# Full Wine environment maintenance
export WINEPREFIX=/workspace/.wine-mt5
export WINEARCH=win64
export EARL_ROOT="${EARL_ROOT}"
export MT5_TERMINAL_PATH=/workspace/mt5/terminal

# Persist for other commands in this session
cat >> ~/.bashrc <<EOF
export WINEPREFIX=/workspace/.wine-mt5
export WINEARCH=win64
export EARL_ROOT=${EARL_ROOT}
export MT5_TERMINAL_PATH=/workspace/mt5/terminal
EOF

# Verify Wine is working
if ! wine --version &>/dev/null; then
    echo "⚠️  Wine not responding, may need re-initialization"
    wineboot --init || true
fi

# Find MetaEditor
METAEDITOR_PATHS=(
  "/workspace/mt5/terminal/metaeditor64.exe"
  "/workspace/mt5/MetaTrader 5/metaeditor64.exe"
  "/workspace/.wine-mt5/drive_c/Program Files/MetaTrader 5/metaeditor64.exe"
)

METAEDITOR_FOUND=""
for path in "${METAEDITOR_PATHS[@]}"; do
  if [ -f "$path" ]; then
    METAEDITOR_FOUND="$path"
    echo "✅ Found MetaEditor: $path"
    break
  fi
done

if [ -z "$METAEDITOR_FOUND" ]; then
  echo "⚠️  MetaEditor not found in expected locations"
  echo "   Searching..."
  find /workspace -name "metaeditor*.exe" 2>/dev/null | head -3
fi

# Clean old build artifacts
echo "==> Cleaning build artifacts..."
rm -f "${EARL_ROOT}"/build/*.log 2>/dev/null || true

# Show current branch
cd "${EARL_ROOT}"
echo "==> Current branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"

echo "✅ Maintenance complete!"
echo ""
echo "Environment ready:"
echo "  WINEPREFIX: $WINEPREFIX"
echo "  EARL_ROOT: $EARL_ROOT"
echo "  MT5_TERMINAL_PATH: $MT5_TERMINAL_PATH"
