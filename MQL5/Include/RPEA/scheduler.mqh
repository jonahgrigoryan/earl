// scheduler.mqh - RPEA Scheduler Module
// References: finalspec.md sections on "Scheduler (OnTimer 30–60s)" and "Data Flow & Sequence (per trading window)"

// TODO[M1]: Implement Scheduler_Tick() function with orchestration flow
// TODO[M2]: Add session window evaluation and gating logic
// TODO[M4]: Implement news window handling and protective exits
// TODO[M7]: Integrate with ensemble meta-policy and adaptive components

#pragma once

// Forward declarations for AppContext and other structs
// These will be defined in the main EA file
struct AppContext;

// Scheduler_Tick - Main scheduling function called from OnTimer
// Purpose: Orchestrate the high-level flow per tick and emit a heartbeat log in M1.
// Flow (per cosine.txt): Equity/News gates → Session checks → Signal proposals → Meta-policy → Allocation → Order engine → Logging
void Scheduler_Tick(const AppContext& ctx)
{
    // TODO[M1]: Implement the full orchestration flow as specified in cosine.txt
    // 1) Equity_ComputeRooms → News_IsBlocked → session predicates
    // 2) if proceed, call SignalsBWISC_Propose and SignalsMR_Propose
    // 3) MetaPolicy_Choose
    // 4) Allocator_BuildOrderPlan
    // 5) OrderEngine (no-ops)
    // 6) LogDecision
    // Only log the decisions; no orders placed at M1

    // TODO[M1]: Replace with LogAuditRow("SCHED_TICK", "Scheduler", 1, "heartbeat", "{}") once logging.mqh is wired
    Print("[RPEA] SCHED_TICK heartbeat");
}
