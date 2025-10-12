#!/bin/bash
set -euo pipefail

# Environment setup
export WINEPREFIX=${WINEPREFIX:-/workspace/.wine-mt5}
REPO_ROOT="${EARL_ROOT:-/workspace/earl}"

# Load environment (.env) if present
if [ -f "${REPO_ROOT}/.env" ]; then
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/.env"
fi

REPORTS_DIR="${REPO_ROOT}/reports"
MT5_TERMINAL="${MT5_TERMINAL_PATH:-/workspace/mt5/terminal}/terminal64.exe"
TEST_CONFIG="${REPO_ROOT}/MQL5/Files/RPEA/strategy_tester/RPEA_10k_tester.ini"

# Respect validation-only mode
if [ "${VALIDATION_ONLY_MODE:-false}" = "true" ]; then
  echo "⚠️  Validation-only mode: skipping Strategy Tester"
  exit 0
fi

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

# Support alternate report path under MQL5/Files
TEST_REPORT="${REPORTS_DIR}/audit_report.csv"
ALT_REPORT="${REPO_ROOT}/MQL5/Files/RPEA/reports/audit_report.csv"

while [ ${ELAPSED} -lt ${TIMEOUT} ]; do
  if [ -f "${TEST_REPORT}" ] || [ -f "${ALT_REPORT}" ]; then
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
pkill -f terminal64.exe 2>/dev/null || wineserver -k || true

# Parse test results
REPORT_TO_READ="${TEST_REPORT}"
if [ -f "${ALT_REPORT}" ]; then
  REPORT_TO_READ="${ALT_REPORT}"
fi

if [ -f "${REPORT_TO_READ}" ]; then
  echo "==> Test Results:"
  tail -20 "${REPORT_TO_READ}"
  
  # Simple pass/fail check (customize based on your report format)
  if grep -E -q "FAIL|ERROR" "${REPORT_TO_READ}"; then
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


