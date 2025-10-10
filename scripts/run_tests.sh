#!/bin/bash
set -euo pipefail

# Environment setup
export WINEPREFIX=${WINEPREFIX:-/workspace/.wine-mt5}
REPO_ROOT="${EARL_ROOT:-/workspace/earl}"
REPORTS_DIR="${REPO_ROOT}/reports"
MT5_TERMINAL="${MT5_TERMINAL_PATH:-/workspace/mt5/terminal}/terminal64.exe"
TEST_CONFIG="${REPO_ROOT}/MQL5/Files/RPEA/strategy_tester/RPEA_10k_tester.ini"

mkdir -p "${REPORTS_DIR}"

echo "==> Running MT5 Strategy Tester..."

# Ensure test EA is compiled
"${REPO_ROOT}/scripts/compile_rpea.sh" "${REPO_ROOT}/MQL5/Experts/FundingPips/RPEA.mq5"

if [ $? -ne 0 ]; then
  echo "❌ Compilation failed - aborting tests"
  exit 1
fi

# Convert paths for Wine
WINE_CONFIG="E:\\MQL5\\Files\\RPEA\\strategy_tester\\RPEA_10k_tester.ini"

echo "==> Launching Strategy Tester..."
# Run Strategy Tester in headless mode
wine "${MT5_TERMINAL}" \
  /portable \
  /config:"${WINE_CONFIG}" &

MT5_PID=$!

# Wait for test completion (check for report file or timeout)
TIMEOUT=300  # 5 minutes
ELAPSED=0

echo "==> Waiting for test completion (timeout: ${TIMEOUT}s)..."
while [ ${ELAPSED} -lt ${TIMEOUT} ]; do
  if [ -f "${REPORTS_DIR}/audit_report.csv" ]; then
    echo "✅ Test execution completed at ${ELAPSED}s"
    break
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo -n "."
done
echo ""

# Kill MT5 process
kill ${MT5_PID} 2>/dev/null || true
sleep 2
killall -9 terminal64.exe 2>/dev/null || true

# Parse test results
if [ -f "${REPORTS_DIR}/audit_report.csv" ]; then
  echo "==> Test Results:"
  tail -20 "${REPORTS_DIR}/audit_report.csv"
  
  # Simple pass/fail check (customize based on your report format)
  if grep -q "FAIL\|ERROR" "${REPORTS_DIR}/audit_report.csv"; then
    echo "❌ Tests contain failures"
    exit 1
  else
    echo "✅ Tests passed"
    exit 0
  fi
else
  echo "❌ Test report not generated within timeout"
  echo "Checking for MT5 logs..."
  find /workspace/.wine-mt5/drive_c -name "*.log" -mmin -10 -exec tail -20 {} \; || true
  exit 1
fi


