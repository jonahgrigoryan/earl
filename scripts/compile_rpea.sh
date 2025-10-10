#!/bin/bash
set -euo pipefail

# Use environment variables set by maintenance script
REPO_ROOT="${EARL_ROOT:-/workspace/earl}"
BUILD_DIR="${REPO_ROOT}/build"
export WINEPREFIX="${WINEPREFIX:-/workspace/.wine-mt5}"

# Find MetaEditor dynamically
METAEDITOR_PATHS=(
  "${MT5_TERMINAL_PATH}/metaeditor64.exe"
  "/workspace/mt5/terminal/metaeditor64.exe"
  "/workspace/mt5/MetaTrader 5/metaeditor64.exe"
  "/workspace/.wine-mt5/drive_c/Program Files/MetaTrader 5/metaeditor64.exe"
)

MT5_METAEDITOR=""
for path in "${METAEDITOR_PATHS[@]}"; do
  if [ -f "$path" ]; then
    MT5_METAEDITOR="$path"
    break
  fi
done

if [ -z "$MT5_METAEDITOR" ]; then
  echo "❌ MetaEditor not found!"
  echo "Searched:"
  printf '  %s\n' "${METAEDITOR_PATHS[@]}"
  exit 1
fi

mkdir -p "${BUILD_DIR}"

# File to compile
MQ5_FILE="${1:-${REPO_ROOT}/MQL5/Experts/FundingPips/RPEA.mq5}"
MQ5_NAME=$(basename "${MQ5_FILE}" .mq5)

echo "==> Compiling ${MQ5_NAME}..."
echo "    MetaEditor: ${MT5_METAEDITOR}"
echo "    Source: ${MQ5_FILE}"

# Wine paths (using E: drive mapping from setup)
WINE_SOURCE="E:\\MQL5\\Experts\\FundingPips\\RPEA.mq5"
WINE_LOG="E:\\build\\compile_${MQ5_NAME}.log"
WINE_INCLUDE="E:\\MQL5\\Include"

# Compile
wine "${MT5_METAEDITOR}" \
  /compile:"${WINE_SOURCE}" \
  /log:"${WINE_LOG}" \
  /include:"${WINE_INCLUDE}" 2>&1 | tee "${BUILD_DIR}/wine_output.log"

# Check results
LOG_FILE="${BUILD_DIR}/compile_${MQ5_NAME}.log"

if [ -f "${LOG_FILE}" ]; then
  echo ""
  echo "==> Compilation Results:"
  
  ERRORS=$(grep -ciE "\\berror\\b" "${LOG_FILE}" || echo "0")
  WARNINGS=$(grep -ciE "\\bwarning\\b" "${LOG_FILE}" || echo "0")
  
  if [ "${ERRORS}" -gt 0 ]; then
    echo "❌ Found ${ERRORS} error(s):"
    grep -iE "\\berror\\b" "${LOG_FILE}"
    exit 1
  elif [ "${WARNINGS}" -gt 0 ]; then
    echo "⚠️  Found ${WARNINGS} warning(s):"
    grep -iE "\\bwarning\\b" "${LOG_FILE}"
  else
    echo "✅ Clean compilation"
  fi
  
  # Check for EX5 output
  EX5_FILE="${MQ5_FILE%.mq5}.ex5"
  if [ -f "${EX5_FILE}" ]; then
    echo "✅ Generated: ${EX5_FILE}"
    cp "${EX5_FILE}" "${BUILD_DIR}/"
  fi
else
  echo "❌ No log file generated"
  exit 1
fi


