#!/bin/bash
set -euo pipefail

echo "==> RPEA MT5 Environment Setup (One-time)"
echo "    Workspace: $(pwd)"

# Install Wine and dependencies
echo "==> Installing Wine and tools..."
sudo apt-get update -qq
sudo apt-get install -y -qq wine64 wine32 winetricks wget unzip cabextract p7zip-full xvfb

# Initialize Wine prefix
echo "==> Initializing Wine prefix..."
export WINEPREFIX=/workspace/.wine-mt5
export WINEARCH=win64
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x16 &>/dev/null &
XVFB_PID=$!
wineboot --init
wait

# Install Visual C++ runtime
echo "==> Installing VC++ runtime..."
WINEPREFIX=/workspace/.wine-mt5 winetricks -q vcrun2019 || echo "Warning: vcrun2019 install had issues, continuing..."

# Download MT5 portable
echo "==> Downloading MT5 terminal..."
mkdir -p /workspace/mt5
cd /workspace/mt5

# Try official MetaQuotes download
wget -q --timeout=30 -O mt5setup.exe \
  "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" || \
  echo "Warning: MT5 download failed, you may need to provide it manually"

# Install MT5 (silent if possible)
if [ -f mt5setup.exe ]; then
  echo "==> Installing MT5..."
  WINEPREFIX=/workspace/.wine-mt5 wine mt5setup.exe /auto /portable || \
  WINEPREFIX=/workspace/.wine-mt5 wine mt5setup.exe /S || \
  echo "Warning: MT5 installation completed with warnings"
fi

# Setup Wine drive mapping for easier paths
echo "==> Setting up drive mapping..."
mkdir -p /workspace/.wine-mt5/dosdevices
ln -sf /workspace/earl /workspace/.wine-mt5/dosdevices/e: 2>/dev/null || true

# Create required directories
echo "==> Creating project directories..."
mkdir -p /workspace/earl/build
mkdir -p /workspace/earl/reports
mkdir -p /workspace/earl/logs

# Make scripts executable
echo "==> Setting script permissions..."
chmod +x /workspace/earl/scripts/*.sh 2>/dev/null || true

# Kill Xvfb
kill $XVFB_PID 2>/dev/null || true

echo "✅ Setup complete!"
echo "   Wine prefix: /workspace/.wine-mt5"
echo "   MT5 path: /workspace/mt5/"
echo ""
echo "To compile: ./scripts/compile_rpea.sh"
echo "To test: ./scripts/run_tests.sh"

