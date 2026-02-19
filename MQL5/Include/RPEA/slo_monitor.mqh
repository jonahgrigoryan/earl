#ifndef RPEA_SLO_MONITOR_MQH
#define RPEA_SLO_MONITOR_MQH
// slo_monitor.mqh - SLO monitoring runtime for MR strategy
// References: docs/m7-final-workflow.md (Phase 5, Task 8/9)

#define SLO_MAX_SAMPLES                        2048
#define SLO_MAX_INGEST_IDS                     4096
#define SLO_CHECK_INTERVAL_SEC                 60
#define SLO_DEFAULT_WINDOW_DAYS                30
#define SLO_DEFAULT_MIN_SAMPLES                5
#define SLO_DEFAULT_DISABLE_AFTER_BREACH_CHECKS 3

#define SLO_WARN_WIN_RATE                      0.58
#define SLO_WARN_MEDIAN_HOLD_HOURS             2.3
#define SLO_WARN_HOLD_P80_HOURS                3.6
#define SLO_WARN_MEDIAN_EFFICIENCY             0.85
#define SLO_WARN_MEDIAN_FRICTION_R             0.35

#define SLO_HARD_WIN_RATE                      0.55
#define SLO_HARD_MEDIAN_HOLD_HOURS             2.5
#define SLO_HARD_HOLD_P80_HOURS                4.0
#define SLO_HARD_MEDIAN_EFFICIENCY             0.80
#define SLO_HARD_MEDIAN_FRICTION_R             0.40

struct SLO_Metrics
{
   double   mr_win_rate_30d;            // Rolling 30-day win rate
   double   mr_median_hold_hours;       // Median hold time in hours
   double   mr_hold_p80_hours;          // 80th percentile hold time
   double   mr_median_efficiency;       // realized R / worst_case_risk
   double   mr_median_friction_r;       // (realized - theoretical) R
   int      rolling_samples;            // Current rolling sample count
   int      breach_consecutive_checks;  // Consecutive periodic hard-breach checks
   datetime breach_first_time;          // First hard-breach timestamp in current streak
   datetime breach_last_time;           // Last hard-breach timestamp in current streak
   bool     mr_disabled;                // Persistent disable after prolonged breach
   bool     warn_only;                  // True if warn threshold breached
   bool     slo_breached;               // True if hard threshold breached
};

struct SLO_ClosedTradeSample
{
   datetime closed_at;
   double   net_outcome;
   int      hold_minutes;
   double   friction_r;
   double   efficiency;
};

SLO_Metrics g_slo_metrics;
datetime    g_slo_last_check_time = 0;
SLO_ClosedTradeSample g_slo_samples[];
ulong                 g_slo_ingested_close_ids[];
int                   g_slo_window_days = SLO_DEFAULT_WINDOW_DAYS;
int                   g_slo_min_samples = SLO_DEFAULT_MIN_SAMPLES;
int                   g_slo_disable_after_breach_checks = SLO_DEFAULT_DISABLE_AFTER_BREACH_CHECKS;

void SLO_InitMetrics(SLO_Metrics &metrics)
{
   metrics.mr_win_rate_30d = 0.60;
   metrics.mr_median_hold_hours = 2.0;
   metrics.mr_hold_p80_hours = 3.5;
   metrics.mr_median_efficiency = 0.85;
   metrics.mr_median_friction_r = 0.30;
   metrics.rolling_samples = 0;
   metrics.breach_consecutive_checks = 0;
   metrics.breach_first_time = 0;
   metrics.breach_last_time = 0;
   metrics.mr_disabled = false;
   metrics.warn_only = false;
   metrics.slo_breached = false;
}

void SLO_ResetIngestionBuffers()
{
   ArrayResize(g_slo_samples, 0);
   ArrayResize(g_slo_ingested_close_ids, 0);
}

void SLO_ResetPersistentState(SLO_Metrics &metrics)
{
   metrics.breach_consecutive_checks = 0;
   metrics.breach_first_time = 0;
   metrics.breach_last_time = 0;
   metrics.mr_disabled = false;
}

string SLO_NormalizeStrategy(const string strategy)
{
   string normalized = strategy;
   StringTrimLeft(normalized);
   StringTrimRight(normalized);
   StringToUpper(normalized);
   return normalized;
}

bool SLO_IsMRStrategy(const string strategy)
{
   return (SLO_NormalizeStrategy(strategy) == "MR");
}

int SLO_FindIngestedCloseId(const ulong close_id)
{
   if(close_id == 0)
      return -1;

   int count = ArraySize(g_slo_ingested_close_ids);
   for(int i = 0; i < count; i++)
   {
      if(g_slo_ingested_close_ids[i] == close_id)
         return i;
   }
   return -1;
}

bool SLO_IsDuplicateCloseId(const ulong close_id)
{
   return (SLO_FindIngestedCloseId(close_id) >= 0);
}

void SLO_RecordIngestedCloseId(const ulong close_id)
{
   if(close_id == 0)
      return;
   if(SLO_IsDuplicateCloseId(close_id))
      return;

   int count = ArraySize(g_slo_ingested_close_ids);
   if(count >= SLO_MAX_INGEST_IDS)
   {
      for(int i = 1; i < count; i++)
         g_slo_ingested_close_ids[i - 1] = g_slo_ingested_close_ids[i];
      g_slo_ingested_close_ids[count - 1] = close_id;
      return;
   }

   if(ArrayResize(g_slo_ingested_close_ids, count + 1) <= count)
      return;
   g_slo_ingested_close_ids[count] = close_id;
}

double SLO_ComputeEfficiencySample(const double net_outcome, const double friction_r)
{
   if(!MathIsValidNumber(net_outcome))
      return 0.0;

   double friction = friction_r;
   if(!MathIsValidNumber(friction))
      friction = 0.0;
   if(friction < 0.0)
      friction = MathAbs(friction);

   if(net_outcome <= 0.0)
      return 0.0;

   double gross = net_outcome + friction;
   if(gross <= 1e-9)
      return 0.0;

   double efficiency = net_outcome / gross;
   if(efficiency < 0.0)
      return 0.0;
   if(efficiency > 1.0)
      return 1.0;
   return efficiency;
}

bool SLO_OnTradeClosed(const ulong close_id,
                       const ulong position_id,
                       const string strategy,
                       const double net_outcome,
                       const int hold_minutes,
                       const double friction_r,
                       const datetime closed_at)
{
   if(close_id == 0 && position_id == 0)
      return false;
   if(!SLO_IsMRStrategy(strategy))
      return false;
   if(close_id > 0 && SLO_IsDuplicateCloseId(close_id))
      return false;

   datetime resolved_closed_at = closed_at;
   if(resolved_closed_at <= 0)
      resolved_closed_at = TimeCurrent();

   int resolved_hold_minutes = hold_minutes;
   if(resolved_hold_minutes < 0)
      resolved_hold_minutes = 0;

   double resolved_friction = friction_r;
   if(!MathIsValidNumber(resolved_friction))
      resolved_friction = 0.0;
   if(resolved_friction < 0.0)
      resolved_friction = MathAbs(resolved_friction);

   int count = ArraySize(g_slo_samples);
   if(count >= SLO_MAX_SAMPLES)
   {
      for(int i = 1; i < count; i++)
         g_slo_samples[i - 1] = g_slo_samples[i];
      count = SLO_MAX_SAMPLES - 1;
      ArrayResize(g_slo_samples, count);
   }

   if(ArrayResize(g_slo_samples, count + 1) <= count)
      return false;

   g_slo_samples[count].closed_at = resolved_closed_at;
   g_slo_samples[count].net_outcome = net_outcome;
   g_slo_samples[count].hold_minutes = resolved_hold_minutes;
   g_slo_samples[count].friction_r = resolved_friction;
   g_slo_samples[count].efficiency = SLO_ComputeEfficiencySample(net_outcome, resolved_friction);

   g_slo_metrics.rolling_samples = ArraySize(g_slo_samples);
   SLO_RecordIngestedCloseId(close_id);

   return true;
}

double SLO_Quantile(const double &values[], const double quantile)
{
   int n = ArraySize(values);
   if(n <= 0)
      return 0.0;

   double sorted[];
   if(ArrayResize(sorted, n) <= 0)
      return 0.0;
   for(int i = 0; i < n; i++)
      sorted[i] = values[i];
   ArraySort(sorted);

   if(n == 1)
      return sorted[0];

   double q = quantile;
   if(q < 0.0)
      q = 0.0;
   if(q > 1.0)
      q = 1.0;

   double pos = q * (n - 1);
   int lo = (int)MathFloor(pos);
   int hi = (int)MathCeil(pos);
   if(lo == hi)
      return sorted[lo];

   double weight = pos - lo;
   return sorted[lo] + (sorted[hi] - sorted[lo]) * weight;
}

void SLO_RecomputeMetricsFromWindow(SLO_Metrics &metrics, const datetime server_time)
{
   datetime now = server_time;
   if(now <= 0)
      now = TimeCurrent();

   int window_days = g_slo_window_days;
   if(window_days <= 0)
      window_days = SLO_DEFAULT_WINDOW_DAYS;

   datetime cutoff = now - (window_days * 24 * 60 * 60);

   double hold_hours[];
   double efficiencies[];
   double frictions[];

   int sample_count = 0;
   int win_count = 0;

   int total = ArraySize(g_slo_samples);
   for(int i = 0; i < total; i++)
   {
      if(g_slo_samples[i].closed_at < cutoff)
         continue;

      if(ArrayResize(hold_hours, sample_count + 1) <= sample_count)
         continue;
      if(ArrayResize(efficiencies, sample_count + 1) <= sample_count)
         continue;
      if(ArrayResize(frictions, sample_count + 1) <= sample_count)
         continue;

      hold_hours[sample_count] = (double)g_slo_samples[i].hold_minutes / 60.0;
      efficiencies[sample_count] = g_slo_samples[i].efficiency;
      frictions[sample_count] = g_slo_samples[i].friction_r;

      if(g_slo_samples[i].net_outcome > 0.0)
         win_count++;

      sample_count++;
   }

   metrics.rolling_samples = sample_count;
   if(sample_count <= 0)
   {
      SLO_InitMetrics(metrics);
      metrics.rolling_samples = 0;
      return;
   }

   metrics.mr_win_rate_30d = (double)win_count / (double)sample_count;
   metrics.mr_median_hold_hours = SLO_Quantile(hold_hours, 0.5);
   metrics.mr_hold_p80_hours = SLO_Quantile(hold_hours, 0.8);
   metrics.mr_median_efficiency = SLO_Quantile(efficiencies, 0.5);
   metrics.mr_median_friction_r = SLO_Quantile(frictions, 0.5);
}

void SLO_SetDisableAfterBreachChecks(const int checks)
{
   g_slo_disable_after_breach_checks = (checks > 0 ? checks : SLO_DEFAULT_DISABLE_AFTER_BREACH_CHECKS);
}

void SLO_CheckAndThrottle(SLO_Metrics &metrics, const datetime server_time = 0)
{
   int min_samples = g_slo_min_samples;
   if(min_samples <= 0)
      min_samples = SLO_DEFAULT_MIN_SAMPLES;

   datetime now = server_time;
   if(now <= 0)
      now = TimeCurrent();

   if(metrics.rolling_samples < min_samples)
   {
      metrics.warn_only = false;
      metrics.slo_breached = false;
      SLO_ResetPersistentState(metrics);
      return;
   }

   bool warn_breach = false;
   if(metrics.mr_win_rate_30d < SLO_WARN_WIN_RATE ||
      metrics.mr_median_hold_hours > SLO_WARN_MEDIAN_HOLD_HOURS ||
      metrics.mr_hold_p80_hours > SLO_WARN_HOLD_P80_HOURS ||
      metrics.mr_median_efficiency < SLO_WARN_MEDIAN_EFFICIENCY ||
      metrics.mr_median_friction_r > SLO_WARN_MEDIAN_FRICTION_R)
   {
      warn_breach = true;
   }
   metrics.warn_only = warn_breach;

   bool hard_breach = false;
   if(metrics.mr_win_rate_30d < SLO_HARD_WIN_RATE ||
      metrics.mr_median_hold_hours > SLO_HARD_MEDIAN_HOLD_HOURS ||
      metrics.mr_hold_p80_hours > SLO_HARD_HOLD_P80_HOURS ||
      metrics.mr_median_efficiency < SLO_HARD_MEDIAN_EFFICIENCY ||
      metrics.mr_median_friction_r > SLO_HARD_MEDIAN_FRICTION_R)
   {
      hard_breach = true;
   }
   metrics.slo_breached = hard_breach;

   if(hard_breach)
   {
      if(metrics.breach_consecutive_checks == 0)
         metrics.breach_first_time = now;
      metrics.breach_consecutive_checks++;
      metrics.breach_last_time = now;

      int disable_after = g_slo_disable_after_breach_checks;
      if(disable_after <= 0)
         disable_after = SLO_DEFAULT_DISABLE_AFTER_BREACH_CHECKS;
      if(metrics.breach_consecutive_checks >= disable_after)
         metrics.mr_disabled = true;
   }
   else
   {
      SLO_ResetPersistentState(metrics);
   }
}

void SLO_OnInit()
{
   SLO_InitMetrics(g_slo_metrics);
   SLO_ResetIngestionBuffers();
   g_slo_last_check_time = 0;
   g_slo_window_days = SLO_DEFAULT_WINDOW_DAYS;
   g_slo_min_samples = SLO_DEFAULT_MIN_SAMPLES;
   g_slo_disable_after_breach_checks = SLO_DEFAULT_DISABLE_AFTER_BREACH_CHECKS;
}

bool SLO_IsMRThrottled()
{
   return (g_slo_metrics.slo_breached || g_slo_metrics.mr_disabled);
}

bool SLO_IsMRDisabled()
{
   return g_slo_metrics.mr_disabled;
}

void SLO_PeriodicCheck(const datetime server_time)
{
   if(server_time - g_slo_last_check_time < SLO_CHECK_INTERVAL_SEC)
      return;

   g_slo_last_check_time = server_time;
   SLO_RecomputeMetricsFromWindow(g_slo_metrics, server_time);
   SLO_CheckAndThrottle(g_slo_metrics, server_time);
}

#ifdef RPEA_TEST_RUNNER
void SLO_TestResetState()
{
   SLO_OnInit();
}

bool SLO_TestIngestTradeClosed(const ulong close_id,
                               const ulong position_id,
                               const string strategy,
                               const double net_outcome,
                               const int hold_minutes,
                               const double friction_r,
                               const datetime closed_at)
{
   return SLO_OnTradeClosed(close_id,
                            position_id,
                            strategy,
                            net_outcome,
                            hold_minutes,
                            friction_r,
                            closed_at);
}

void SLO_TestSetWindowDays(const int window_days)
{
   g_slo_window_days = (window_days > 0 ? window_days : SLO_DEFAULT_WINDOW_DAYS);
}

void SLO_TestSetMinSamples(const int min_samples)
{
   g_slo_min_samples = (min_samples > 0 ? min_samples : SLO_DEFAULT_MIN_SAMPLES);
}

void SLO_TestSetDisableAfterBreachChecks(const int checks)
{
   SLO_SetDisableAfterBreachChecks(checks);
}

void SLO_TestRunPeriodicCheck(const datetime server_time)
{
   SLO_PeriodicCheck(server_time);
}

int SLO_TestGetSampleCount()
{
   return ArraySize(g_slo_samples);
}

int SLO_TestGetIngestedIdCount()
{
   return ArraySize(g_slo_ingested_close_ids);
}

int SLO_TestGetConsecutiveBreachChecks()
{
   return g_slo_metrics.breach_consecutive_checks;
}
#endif // RPEA_TEST_RUNNER

#endif // RPEA_SLO_MONITOR_MQH
