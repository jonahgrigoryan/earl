#!/bin/bash
set -euo pipefail

echo "==> RPEA MT5 Environment Setup"
echo "    Workspace: $(pwd)"

ARCH=$(uname -m)
REPO_ROOT="${EARL_ROOT:-/workspace/earl}"
SCRIPTS_DIR="${REPO_ROOT}/scripts"

echo "==> Detected architecture: $ARCH"

cleanup_xvfb() {
    if [ -n "${XVFB_PID:-}" ]; then
        kill "$XVFB_PID" 2>/dev/null || true
        unset XVFB_PID
    fi
}

enable_validation_only_mode() {
    local reason="$1"

    echo ""
    echo "⚠️  VALIDATION-ONLY MODE ENABLED"
    if [ -n "$reason" ]; then
        echo "    Reason: $reason"
    fi
    echo ""
    echo "Wine/MT5 require an environment capable of executing x86_64 binaries."
    echo ""
    echo "OPTIONS:"
    echo "1. Request x86_64/amd64 environment from Codex Cloud"
    echo "2. Use validation-only mode (no compilation)"
    echo "3. Compile locally on x86_64 machine"
    echo ""
    echo "Setting up VALIDATION-ONLY mode..."
    echo ""

    sudo apt-get update -qq
    sudo apt-get install -y -qq git curl jq python3-pip

    mkdir -p "${REPO_ROOT}" "${REPO_ROOT}/build" "$SCRIPTS_DIR"

    cat > "${SCRIPTS_DIR}/compile_rpea.sh" <<'COMPILE_EOF'
#!/bin/bash
set -euo pipefail

REPO_ROOT="${EARL_ROOT:-/workspace/earl}"
if [ -f "${REPO_ROOT}/.env" ]; then
    # shellcheck disable=SC1090
    source "${REPO_ROOT}/.env"
fi

REASON=${VALIDATION_REASON:-"Wine environment unavailable"}
echo "⚠️  Running in VALIDATION-ONLY mode (${REASON})"
echo "    Actual compilation requires x86_64 architecture"
echo ""
echo "Performing static code validation instead..."
echo ""

MQ5_FILE="${1:-${REPO_ROOT}/MQL5/Experts/FundingPips/RPEA.mq5}"

# Check file exists
if [ ! -f "$MQ5_FILE" ]; then
    echo "❌ File not found: $MQ5_FILE"
    exit 1
fi

echo "✅ File exists: $MQ5_FILE"

echo ""
echo "==> Checking MQL5 syntax patterns..."

ERRORS=0

OPEN_BRACES=$(grep -o '{' "$MQ5_FILE" | wc -l)
CLOSE_BRACES=$(grep -o '}' "$MQ5_FILE" | wc -l)
if [ "$OPEN_BRACES" -ne "$CLOSE_BRACES" ]; then
    echo "❌ Brace mismatch: $OPEN_BRACES open, $CLOSE_BRACES close"
    ERRORS=$((ERRORS + 1))
else
    echo "✅ Braces balanced: $OPEN_BRACES pairs"
fi

REQUIRED_INCLUDES=("config.mqh" "state.mqh" "order_engine.mqh")
for inc in "${REQUIRED_INCLUDES[@]}"; do
    if grep -q "#include.*$inc" "$MQ5_FILE"; then
        echo "✅ Found include: $inc"
    else
        echo "⚠️  Missing include: $inc"
    fi
done

EVENT_HANDLERS=("OnInit" "OnDeinit" "OnTimer" "OnTradeTransaction")
for handler in "${EVENT_HANDLERS[@]}"; do
    if grep -q "^void $handler\|^int $handler" "$MQ5_FILE" "$REPO_ROOT"/MQL5/Include/RPEA/*.mqh 2>/dev/null; then
        echo "✅ Found handler: $handler"
    else
        echo "⚠️  Handler not found: $handler"
    fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ Validation passed (syntax checks only - full compilation requires x86_64)"
    echo ""
    echo "To compile for real:"
    echo "  1. Use x86_64 Codex environment, OR"
    echo "  2. Compile locally: copy to Windows MT5 and compile with MetaEditor"
    exit 0
else
    echo "❌ Validation found $ERRORS issue(s)"
    exit 1
fi
COMPILE_EOF
    chmod +x "${SCRIPTS_DIR}/compile_rpea.sh"

    {
        echo "VALIDATION_ONLY_MODE=true"
        echo "ARCH=$ARCH"
        echo "WINE_AVAILABLE=false"
        if [ -n "$reason" ]; then
            printf 'VALIDATION_REASON=%q\n' "$reason"
        fi
    } > "${REPO_ROOT}/.env"

    echo ""
    echo "✅ Validation-only setup complete!"
    echo ""
    echo "⚠️  NOTE: This mode can validate code structure but cannot compile MQ5 files."
    echo "    For full compilation, request an x86_64 environment from Codex."
    echo ""

    cleanup_xvfb
    exit 0
}

trap cleanup_xvfb EXIT

if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    enable_validation_only_mode "ARM64 architecture detected"
fi

# x86_64 detected - proceed with full Wine setup
echo "==> x86_64 architecture - proceeding with Wine/MT5 installation"

echo "==> Enabling 32-bit architecture support..."
if ! sudo dpkg --add-architecture i386 2>/dev/null; then
    echo "Warning: Unable to add i386 architecture (continuing with wine64 only)"
fi

echo "==> Updating package lists..."
if ! sudo apt-get update -qq; then
    enable_validation_only_mode "Package repository update failed"
fi

echo "==> Installing Wine and tools..."
if ! sudo apt-get install -y -qq wine64 winetricks wget unzip cabextract p7zip-full xvfb; then
    enable_validation_only_mode "Wine packages failed to install"
fi

if ! sudo apt-get install -y -qq wine32; then
    echo "Note: wine32 not available, using wine64 only (sufficient for 64-bit MT5)"
fi

echo "==> Initializing Wine prefix..."
export WINEPREFIX=/workspace/.wine-mt5
export WINEARCH=win64
export DISPLAY=:99

Xvfb :99 -screen 0 1024x768x16 &>/dev/null &
XVFB_PID=$!
sleep 2

if ! wineboot --init; then
    enable_validation_only_mode "Wine initialization failed (likely unsupported binary format)"
fi
sleep 5

if ! wine --version &>/dev/null; then
    enable_validation_only_mode "Wine executables cannot run in this environment"
fi

echo "==> Installing VC++ runtime..."
WINEPREFIX=/workspace/.wine-mt5 winetricks -q vcrun2019 || echo "Warning: vcrun2019 install had issues, continuing..."

echo "==> Downloading MT5 terminal..."
MT5_DIR=/workspace/mt5
mkdir -p "$MT5_DIR"
cd "$MT5_DIR"

wget -q --timeout=30 -O mt5setup.exe \
  "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" || \
  echo "Warning: MT5 download failed, you may need to provide it manually"

if [ -f mt5setup.exe ]; then
  echo "==> Installing MT5..."
  WINEPREFIX=/workspace/.wine-mt5 wine mt5setup.exe /auto /portable || \
  WINEPREFIX=/workspace/.wine-mt5 wine mt5setup.exe /S || \
  echo "Warning: MT5 installation completed with warnings"
fi

echo "==> Setting up drive mapping..."
mkdir -p /workspace/.wine-mt5/dosdevices
ln -sf "$REPO_ROOT" /workspace/.wine-mt5/dosdevices/e: 2>/dev/null || true

mkdir -p "${REPO_ROOT}/build" "${REPO_ROOT}/reports" "${REPO_ROOT}/logs"
chmod +x "${SCRIPTS_DIR}"/*.sh 2>/dev/null || true

echo "VALIDATION_ONLY_MODE=false" > "${REPO_ROOT}/.env"
echo "ARCH=$ARCH" >> "${REPO_ROOT}/.env"
echo "WINE_AVAILABLE=true" >> "${REPO_ROOT}/.env"
echo "WINEPREFIX=/workspace/.wine-mt5" >> "${REPO_ROOT}/.env"
echo "MT5_TERMINAL_PATH=/workspace/mt5/terminal" >> "${REPO_ROOT}/.env"

cleanup_xvfb

echo "✅ Full setup complete!"
echo "   Wine prefix: /workspace/.wine-mt5"
echo "   MT5 path: /workspace/mt5/"
echo ""
echo "To compile: ./scripts/compile_rpea.sh"
echo "To test: ./scripts/run_tests.sh"
