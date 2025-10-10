#!/bin/bash
set -euo pipefail

echo "==> RPEA Environment Maintenance"

# Set environment variables
export WINEPREFIX=/workspace/.wine-mt5
export WINEARCH=win64
export EARL_ROOT=/workspace/earl
export MT5_TERMINAL_PATH=/workspace/mt5/terminal

# Persist for other commands in this session
cat >> ~/.bashrc <<'EOF'
export WINEPREFIX=/workspace/.wine-mt5
export WINEARCH=win64
export EARL_ROOT=/workspace/earl
export MT5_TERMINAL_PATH=/workspace/mt5/terminal
EOF

# Verify Wine is working
if ! wine --version &>/dev/null; then
    echo "⚠️  Wine not responding, may need re-initialization"
    wineboot --init || true
fi

# Find MetaEditor (it may be in different locations)
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
rm -f /workspace/earl/build/*.log 2>/dev/null || true

# Show current branch
cd /workspace/earl
echo "==> Current branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"

echo "✅ Maintenance complete!"
echo ""
echo "Environment ready:"
echo "  WINEPREFIX: $WINEPREFIX"
echo "  EARL_ROOT: $EARL_ROOT"
echo "  MT5_TERMINAL_PATH: $MT5_TERMINAL_PATH"


