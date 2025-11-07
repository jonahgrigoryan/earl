# Task 10 News CSV Fallback Outline

## Preparation

- **Review Specs**: Re-read `.kiro/specs/rpea-m3/tasks.md` Task 10 (lines 96-101) and requirements §10 (.kiro/specs/rpea-m3/requirements.md:125-137) to capture the acceptance language on rejecting stale CSVs and files missing required columns `timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min`.
- **Inspect Current Code**: Snapshot `MQL5/Include/RPEA/news.mqh` and `MQL5/Include/RPEA/config.mqh` to identify existing stubs and confirm available configuration constants (`DEFAULT_NewsCSVPath`, `DEFAULT_NewsCSVMaxAgeHours`).

## Implementation Steps

- **Struct & State Setup** (`news.mqh`)
- Define a `NewsEvent` struct with fields `timestamp_utc`, `symbol`, `impact`, `source`, `event`, `prebuffer_min`, `postbuffer_min`, `block_start`, `block_end`, `is_valid`.
- Declare file-scope cache variables:
  - `static NewsEvent g_news_events[];`
  - `static int g_news_event_count = 0;`
  - `static datetime g_news_last_mtime = 0;`
  - `static bool g_news_cache_valid = false;`
  - `static int g_news_last_load_code = 0; // optional reason code`
- Add helpers for ISO8601 UTC parsing, string normalization (including broker suffix stripping), and block window computation (`start = ts − max(prebuffer_min,0)*60`, `end = ts + max(postbuffer_min,0)*60`), clamping negative buffers to zero.
- Ensure `bool News_LoadCsvFallback()` returns true only when the cache is populated; callers clear cache on false.

- **Schema & Staleness Guards** (`news.mqh`)
- Implement `News_ValidateCsvSchema(const string header_line, int &idx_timestamp, ...)` that confirms presence (order-agnostic) of the seven required headers exactly as specified and rejects the file otherwise (per tasks.md §10 acceptance).
- Implement `News_GetFileMTime(const string path, datetime &mtime)` via `FileFindFirst`/`FileFindNext`, caching the last modification time so reloads occur only when the mtime changes; missing file should clear cache, emit `[News] CSV missing: <path>`, and return without error.
- Implement `News_IsCsvFresh(const datetime mtime, const int max_age_hours)` using `TimeCurrent()`; on stale files (mtime older than `max_age_hours`), clear the cache and log `[News] CSV stale (age %.1f h > max %d): <path>` to satisfy requirement 10.6.

- **CSV Parsing Logic** (`news.mqh`)
- Rewrite `News_LoadCsvFallback()` to:
  - Use `DEFAULT_NewsCSVPath`/`DEFAULT_NewsCSVMaxAgeHours` unless inputs are later added; document this assumption so the agent doesn’t reference non-existent variables.
  - Acquire mtime via `News_GetFileMTime`, run freshness check, open the CSV (`FILE_READ|FILE_TXT|FILE_ANSI`), and validate schema via the index map.
  - Iterate rows with `StringSplit`, parse timestamp in UTC, buffers (minutes), and normalize impact to `HIGH|MEDIUM|LOW` before computing block windows; also compute effective buffers honoring `NewsBufferS` (convert to minutes and take the maximum of per-row vs global requirement guard).
  - Record accepted vs skipped counts (bad schema, invalid timestamp, invalid buffers) and log summary per acceptance text (`[News] Loaded %d events (skipped %d) from fallback CSV`), updating the cache only on successful parse and clearing otherwise; log `[News] CSV invalid headers: expected timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min` when schema fails and `[News] CSV parse error on line %d: <reason>` for row-level issues.

- **Integration Hooks** (`news.mqh`)
- Implement the following public helpers with exact signatures:
  - `bool News_LoadCsvFallback();`
  - `bool News_ReloadIfChanged();`
  - `void News_ForceReload();`
  - `bool News_GetEventsForSymbol(const string symbol, NewsEvent &out[]); // true when any events copied`
- Implement `News_ReloadIfChanged()` to compare cached `last_loaded_mtime` with current mtime and refresh only when the file changes; include `News_ForceReload()` test hook and ensure cache clears on failure/missing file.
- Keep the public `bool News_IsBlocked(const string symbol)` signature; inside, call `News_ReloadIfChanged()`, convert current time to UTC (`TimeGMT()`), normalize `symbol`, short-circuit false when `impact != "HIGH"`, and for HIGH-impact events evaluate whether `now_utc` lies within `[block_start, block_end]` (pre/post buffers vs `NewsBufferS`).

## Logging Messages

- Emit consistent lines for key scenarios:
    - `[News] CSV missing: <path>`
    - `[News] CSV stale (age %.1f h > max %d): <path>`
    - `[News] CSV invalid headers: expected timestamp_utc,symbol,impact,source,event,prebuffer_min postbuffer_min`
    - `[News] Loaded %d events (skipped %d) from fallback CSV`
    - `[News] CSV parse error on line %d: <reason>`

## Testing Strategy

- **Unit Tests** (`Tests/RPEA/test_news_csv_fallback.mqh`)
- Follow existing test patterns (e.g., `test_order_engine_*.mqh`) to add deterministic cases: valid load, schema rejection, stale file rejection, buffer math with `NewsBufferS`, HIGH-only gating, MEDIUM/LOW bypass, cache reuse, forced reload hook, and UTC window checks.
- Place fixture CSVs under `Tests/RPEA/fixtures/news/` so the automated harness (`run_automated_tests_ea.mq5`) picks them up consistently.

- **Manual Verification**
- Run the automated test harness to confirm new tests and existing Tasks 1-9 suites pass.
- Place a sample CSV in `Files/RPEA/news/` and attach EA in Strategy Tester to confirm runtime logs report fallback load and correct blocking behavior.

## Wrap-up

- Review code for MQL5 style compliance (no `static`, no reference aliasing, early returns).
- Ensure `[News]` logging includes reasons for rejection (missing headers, stale, parse errors) as required by spec.
- Document helper functions via inline comments and note that future inputs may replace direct uses of the `DEFAULT_` constants.