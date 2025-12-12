# Task 24 Outline — Pending Order Expiry Optimization

## Objective

Expire all pending orders (single and OCO legs) after 45 minutes unless a manual override is provided, flowing directly after Task 23 (breakeven) without altering prior behaviors.

## Implementation Steps

1. **Config/Defaults Review**

- Current code uses `DEFAULT_PendingExpiryGraceSeconds` (~60s) for fallback. Add a dedicated default for this task: `DEFAULT_PendingExpiryMinutes = 45` (or `DEFAULT_PendingExpirySeconds = 2700`), keeping the grace seconds for housekeeping if still used elsewhere.

2. **Helper Function (concrete signature)**

- In `Include/RPEA/order_engine.mqh`, add `datetime OE_CalcPendingExpiry(const datetime custom_expiry)`:
 - If `custom_expiry > 0`, return it (honor manual override).
 - Otherwise return `TimeCurrent() + (45 * 60)`.

3. **Application Points (explicit sites)**

- Single pending orders: around line ~1523 in `PlaceOrder()`, set `normalized.expiry = OE_CalcPendingExpiry(request.expiry);` before intent creation/normalization.
- OCO primary leg: in `EstablishOCO()` (~2012) ensure the calculated expiry is applied.
- OCO sibling leg: when creating the sibling (~1248), use the same expiry as primary.
- Fallback paths using `m_pending_expiry_grace_seconds` (e.g., ~1224, 1234, 1241): update to default to the 45-minute expiry unless a specific custom override remains.

4. **Broker vs Aligned Expiry (session cutoff interplay)**

- Set `expiry_broker` to the 45-minute value (`OE_CalcPendingExpiry`).
- `expiry_aligned` currently leverages session cutoff (`GetSessionCutoffAligned()` around ~2030). Decide whether to keep session-aligned for housekeeping or mirror the 45-minute value; ensure both OCO legs store consistent `expiry_broker`, and update OCO relationship metadata accordingly.

5. **Logging & Audit Hooks**

- Log expiry assignment with timestamp and rationale ("pending expiry set to +45m" vs "custom expiry retained").
- Ensure no regression with Task 14 audit logging; add minimal OrderEngine log entry if audit schema lacks expiry.

6. **Edge Cases & Retries**

- Respect manual/strategy overrides (`request.expiry > 0`).
- Avoid extending expiry unintentionally on retries/replacements; re-derive only when appropriate.

7. **Unit Tests & Registration**

- Add `Tests/RPEA/test_order_engine_pending_expiry.mqh` with cases: `PendingExpiry_Sets45Minutes`, `PendingExpiry_AppliesToAllPendings`, `PendingExpiry_AutoCancelsExpired`, `PendingExpiry_HonorsCustomExpiry`, `PendingExpiry_LogsExpirySet`.
- Register in `Tests/RPEA/run_automated_tests_ea.mq5`: include after breakeven tests, add forward declaration `bool TestOrderEnginePendingExpiry_RunAll();`, and invoke the suite in `RunAllTests()`.

## Deliverables

- `task24.md` documenting the above implementation and test plan.
- No code changes yet—outline only.