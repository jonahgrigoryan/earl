#ifndef RPEA_SLO_MONITOR_MQH
#define RPEA_SLO_MONITOR_MQH
// slo_monitor.mqh - SLO monitoring stub for MR strategy (M7 Task 7)
// Full tracking implementation deferred to Task 8 or post-M7.
// References: docs/m7-final-workflow.md (Phase 5, Task 7, Step 7.2)

struct SLO_Metrics
{
   double mr_win_rate_30d;          // Rolling 30-day win rate
   double mr_median_hold_hours;     // Median hold time in hours
   double mr_hold_p80_hours;        // 80th percentile hold time
   double mr_median_efficiency;     // realized R / worst_case_risk
   double mr_median_friction_r;     // (realized - theoretical) R
   bool   warn_only;                // True if warn threshold breached
   bool   slo_breached;             // True if hard threshold breached
};

// Initialize SLO metrics with safe defaults (no warnings, no breaches)
void SLO_InitMetrics(SLO_Metrics& metrics)
{
   metrics.mr_win_rate_30d = 0.60;         // Optimistic default (above 55% target)
   metrics.mr_median_hold_hours = 2.0;     // Within target (< 2.5h)
   metrics.mr_hold_p80_hours = 3.5;        // Within target (< 4h)
   metrics.mr_median_efficiency = 0.85;    // Above threshold (>= 0.8)
   metrics.mr_median_friction_r = 0.30;    // Below threshold (<= 0.4R)
   metrics.warn_only = false;              // No warnings initially
   metrics.slo_breached = false;           // No breaches initially
}

// Check SLO thresholds and set breach flags
// Spec thresholds:
// - MR win rate warn < 55% (target 58-62%)
// - Median hold <= 2.5h, 80th percentile <= 4h
// - Median efficiency >= 0.8
// - Median friction tax <= 0.4R
void SLO_CheckAndThrottle(SLO_Metrics& metrics)
{
   // Check warn threshold
   metrics.warn_only = (metrics.mr_win_rate_30d < 0.55);

   // Check all breach conditions
   if(metrics.mr_win_rate_30d < 0.55 ||
      metrics.mr_median_hold_hours > 2.5 ||
      metrics.mr_hold_p80_hours > 4.0 ||
      metrics.mr_median_efficiency < 0.80 ||
      metrics.mr_median_friction_r > 0.40)
   {
      metrics.slo_breached = true;
      // TODO[M7-Task8]: Throttle MR_RiskPct *= 0.75 or disable MR if persistent
      // Implementation options:
      // 1. Global flag g_mr_throttled that Config_GetMRRiskPctDefault() checks
      // 2. Modify meta_policy to skip MR when slo_breached
   }
   else
   {
      metrics.slo_breached = false;
   }
}

//+------------------------------------------------------------------+
//| SLO Runtime State (Task 08)                                      |
//| Single owner of all SLO metrics. Init in RPEA.mq5::OnInit().     |
//+------------------------------------------------------------------+
SLO_Metrics g_slo_metrics;
datetime    g_slo_last_check_time = 0;
const int   SLO_CHECK_INTERVAL_SEC = 60;  // Check once per minute

// Initialize SLO state - call from RPEA.mq5::OnInit()
void SLO_OnInit()
{
   SLO_InitMetrics(g_slo_metrics);
   g_slo_last_check_time = 0;
}

// Query: is MR currently throttled by SLO breach?
bool SLO_IsMRThrottled()
{
   return g_slo_metrics.slo_breached;
}

// Periodic check - call from Scheduler_Tick each tick; self-throttles to once/minute
void SLO_PeriodicCheck(const datetime server_time)
{
   if(server_time - g_slo_last_check_time < SLO_CHECK_INTERVAL_SEC)
      return;
   g_slo_last_check_time = server_time;

   // NOTE: g_slo_metrics fields are stub defaults (safe, no breach).
   // Full 30-day rolling analytics computation is post-M7 scope.
   SLO_CheckAndThrottle(g_slo_metrics);
}

#endif // RPEA_SLO_MONITOR_MQH
