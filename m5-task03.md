# M5-Task03: CSV audit/reporting artifacts

## Objective

Generate CSV audit and backtest summary reports by combining EA audit logs with MT5 Strategy Tester reports.

## Deliverables

- scripts/generate_audit_report.ps1
- scripts/analyze_backtest.ps1
- Files/RPEA/reports/audit_report_template.csv

## Requirements

- Parse MT5 report HTML/XML for trade metrics (net profit, profit factor, trade count, win rate, max DD).
- Derive daily PnL and trade-day counts from MT5 report trade tables (or from audit logs if the report lacks detail).
- Compute daily cap and overall cap violations from derived PnL and max DD.
- Parse EA audit CSV logs for compliance metrics (news blocks, budget gate rejects, floor breaches).
- Emit a summary CSV in Files/RPEA/reports.
- Support portable and default MT5 report locations.
- Keep scripts idempotent and repo-root relative by default.

## Files to Modify/Create

- scripts/generate_audit_report.ps1
- scripts/analyze_backtest.ps1
- Files/RPEA/reports/audit_report_template.csv

## Steps

1. Define audit_report_template.csv with required output columns.
2. Implement generate_audit_report.ps1:
   - Resolve repo root.
   - Optionally copy tester agent audit logs into Files/RPEA/logs (handle both layouts):
     - Portable: C:\Program Files\MetaTrader 5\Tester\Agent-*\MQL5\Files\RPEA\logs\
     - Default: %APPDATA%\MetaQuotes\Tester\<HASH>\Agent-*\MQL5\Files\RPEA\logs\
   - Load MT5 report (XML or HTML) and extract summary metrics.
   - Parse trade tables to compute daily PnL and trade-day counts; fall back to audit logs if needed.
   - Load audit CSVs and compute compliance counts.
   - Write a combined CSV report.
3. Implement analyze_backtest.ps1:
   - Parse MT5 report.
   - Validate against targets (profit, daily cap, overall cap, trade days).
   - Print PASS/FAIL with reasons.

## Validation

- Run a sample MT5 test to generate a report, then:
  - scripts/analyze_backtest.ps1 -ReportPath <report>
  - scripts/generate_audit_report.ps1 -FromDate <start> -ToDate <end> -MT5ReportPath <report>
- Confirm output CSV exists and is populated.

## Notes

- MT5 report formats can vary; use robust parsing with clear error messages.
- Keep all files ASCII-only.
