#ifndef RPEA_TELEMETRY_MQH
#define RPEA_TELEMETRY_MQH
// telemetry.mqh - Telemetry stubs (M1)
// References: finalspec.md (Telemetry & SLOs)

#include <RPEA/logging.mqh>
#include <RPEA/regime.mqh>

void Telemetry_OnTradeClosed(const string strategy,
                             const double net_outcome,
                             const int hold_minutes);

struct TelemetryStrategyKpis
{
   int    samples;
   int    wins;
   double sum_outcome;
   double sum_positive;
   double sum_negative;
   double expectancy;
   double efficiency;
};

struct TelemetryKpiState
{
   bool                 initialized;
   int                  min_samples;
   datetime             last_update_time;
   TelemetryStrategyKpis bwisc;
   TelemetryStrategyKpis mr;
};

struct TelemetryPositionTracker
{
   ulong    position_id;
   string   strategy;
   datetime entry_time;
   double   cumulative_outcome;
};

TelemetryKpiState g_telemetry_kpis;
TelemetryPositionTracker g_telemetry_positions[];

void Telemetry_ResetStrategyKpis(TelemetryStrategyKpis &k)
{
   k.samples = 0;
   k.wins = 0;
   k.sum_outcome = 0.0;
   k.sum_positive = 0.0;
   k.sum_negative = 0.0;
   k.expectancy = 0.0;
   k.efficiency = 0.0;
}

void Telemetry_EnsureInitialized()
{
   if(g_telemetry_kpis.initialized)
      return;

   g_telemetry_kpis.initialized = true;
   g_telemetry_kpis.min_samples = 5;
   g_telemetry_kpis.last_update_time = 0;
   Telemetry_ResetStrategyKpis(g_telemetry_kpis.bwisc);
   Telemetry_ResetStrategyKpis(g_telemetry_kpis.mr);
}

void Telemetry_InitKpis(const int min_samples = 5)
{
   Telemetry_EnsureInitialized();
   g_telemetry_kpis.min_samples = (min_samples > 0 ? min_samples : 1);
   g_telemetry_kpis.last_update_time = TimeCurrent();
}

void Telemetry_UpdateSingle(TelemetryStrategyKpis &k)
{
   if(k.samples < g_telemetry_kpis.min_samples)
   {
      k.expectancy = 0.0;
      k.efficiency = 0.0;
      return;
   }

   k.expectancy = k.sum_outcome / (double)k.samples;
   double denom = k.sum_positive + k.sum_negative;
   if(denom <= 1e-9)
      k.efficiency = 0.0;
   else
      k.efficiency = k.sum_positive / denom;
}

void Telemetry_UpdateKpis()
{
   Telemetry_EnsureInitialized();
   Telemetry_UpdateSingle(g_telemetry_kpis.bwisc);
   Telemetry_UpdateSingle(g_telemetry_kpis.mr);
   g_telemetry_kpis.last_update_time = TimeCurrent();
}

void Telemetry_RecordOutcome(const string strategy, const double outcome)
{
   Telemetry_EnsureInitialized();

   if(strategy == "BWISC")
   {
      g_telemetry_kpis.bwisc.samples++;
      g_telemetry_kpis.bwisc.sum_outcome += outcome;
      if(outcome > 0.0)
      {
         g_telemetry_kpis.bwisc.wins++;
         g_telemetry_kpis.bwisc.sum_positive += outcome;
      }
      else if(outcome < 0.0)
      {
         g_telemetry_kpis.bwisc.sum_negative += MathAbs(outcome);
      }
   }
   else if(strategy == "MR")
   {
      g_telemetry_kpis.mr.samples++;
      g_telemetry_kpis.mr.sum_outcome += outcome;
      if(outcome > 0.0)
      {
         g_telemetry_kpis.mr.wins++;
         g_telemetry_kpis.mr.sum_positive += outcome;
      }
      else if(outcome < 0.0)
      {
         g_telemetry_kpis.mr.sum_negative += MathAbs(outcome);
      }
   }
   else
   {
      return;
   }

   Telemetry_UpdateKpis();
}

string Telemetry_NormalizeStrategy(const string strategy_hint)
{
   string normalized = strategy_hint;
   StringTrimLeft(normalized);
   StringTrimRight(normalized);
   StringToUpper(normalized);

   if(normalized == "MR" || normalized == "BWISC")
      return normalized;

   if(StringFind(normalized, "MR-MR") >= 0 || StringFind(normalized, "MR-") >= 0)
      return "MR";

   if(StringFind(normalized, "BWISC-") >= 0 || StringFind(normalized, "BWISC") >= 0)
      return "BWISC";

   return "";
}

int Telemetry_FindPositionTracker(const ulong position_id)
{
   int count = ArraySize(g_telemetry_positions);
   for(int i = 0; i < count; i++)
   {
      if(g_telemetry_positions[i].position_id == position_id)
         return i;
   }
   return -1;
}

void Telemetry_RemovePositionTrackerAt(const int index)
{
   int count = ArraySize(g_telemetry_positions);
   if(index < 0 || index >= count)
      return;

   for(int i = index; i < count - 1; i++)
      g_telemetry_positions[i] = g_telemetry_positions[i + 1];

   ArrayResize(g_telemetry_positions, count - 1);
}

void Telemetry_OnPositionEntry(const ulong position_id,
                               const string strategy_hint,
                               const datetime entry_time)
{
   if(position_id == 0)
      return;

   string strategy = Telemetry_NormalizeStrategy(strategy_hint);
   if(strategy == "")
      return;

   datetime resolved_entry_time = entry_time;
   if(resolved_entry_time <= 0)
      resolved_entry_time = TimeCurrent();

   int index = Telemetry_FindPositionTracker(position_id);
   if(index >= 0)
   {
      g_telemetry_positions[index].strategy = strategy;
      if(g_telemetry_positions[index].entry_time <= 0 ||
         resolved_entry_time < g_telemetry_positions[index].entry_time)
      {
         g_telemetry_positions[index].entry_time = resolved_entry_time;
      }
      return;
   }

   int count = ArraySize(g_telemetry_positions);
   if(ArrayResize(g_telemetry_positions, count + 1) <= count)
      return;

   g_telemetry_positions[count].position_id = position_id;
   g_telemetry_positions[count].strategy = strategy;
   g_telemetry_positions[count].entry_time = resolved_entry_time;
   g_telemetry_positions[count].cumulative_outcome = 0.0;
}

bool Telemetry_OnPositionExit(const ulong position_id,
                              const string strategy_hint,
                              const double net_outcome,
                              const datetime exit_time,
                              const bool position_closed,
                              string &out_strategy,
                              double &out_total_outcome,
                              int &out_hold_minutes)
{
   out_strategy = "";
   out_total_outcome = 0.0;
   out_hold_minutes = 0;

   if(position_id == 0)
      return false;

   string fallback_strategy = Telemetry_NormalizeStrategy(strategy_hint);
   int index = Telemetry_FindPositionTracker(position_id);

   if(index < 0)
   {
      if(!position_closed || fallback_strategy == "")
         return false;

      out_strategy = fallback_strategy;
      out_total_outcome = net_outcome;
      out_hold_minutes = 0;
      Telemetry_OnTradeClosed(out_strategy, out_total_outcome, out_hold_minutes);
      return true;
   }

   g_telemetry_positions[index].cumulative_outcome += net_outcome;
   if(g_telemetry_positions[index].strategy == "")
      g_telemetry_positions[index].strategy = fallback_strategy;

   if(!position_closed)
      return false;

   datetime resolved_exit_time = exit_time;
   if(resolved_exit_time <= 0)
      resolved_exit_time = TimeCurrent();

   datetime entry_time = g_telemetry_positions[index].entry_time;
   if(entry_time > 0 && resolved_exit_time >= entry_time)
      out_hold_minutes = (int)((resolved_exit_time - entry_time) / 60);

   out_strategy = g_telemetry_positions[index].strategy;
   if(out_strategy == "")
      out_strategy = fallback_strategy;
   out_total_outcome = g_telemetry_positions[index].cumulative_outcome;

   Telemetry_RemovePositionTrackerAt(index);

   if(out_strategy == "")
      return false;

   Telemetry_OnTradeClosed(out_strategy, out_total_outcome, out_hold_minutes);
   return true;
}

void Telemetry_OnTradeClosed(const string strategy,
                             const double net_outcome,
                             const int hold_minutes)
{
   if(hold_minutes < 0)
   {
      // Guard negative values from malformed callers.
   }

   Telemetry_RecordOutcome(strategy, net_outcome);
}

void Telemetry_AutoThrottle()
{
   // TODO[M7]: SLO thresholds and auto-risk reduction
}

double Telemetry_GetBWISCEfficiency()
{
   Telemetry_UpdateKpis();
   return g_telemetry_kpis.bwisc.efficiency;
}

double Telemetry_GetMREfficiency()
{
   Telemetry_UpdateKpis();
   return g_telemetry_kpis.mr.efficiency;
}

double Telemetry_GetBWISCExpectancy()
{
   Telemetry_UpdateKpis();
   return g_telemetry_kpis.bwisc.expectancy;
}

double Telemetry_GetMRExpectancy()
{
   Telemetry_UpdateKpis();
   return g_telemetry_kpis.mr.expectancy;
}

int Telemetry_GetBWISCSamples()
{
   Telemetry_EnsureInitialized();
   return g_telemetry_kpis.bwisc.samples;
}

int Telemetry_GetMRSamples()
{
   Telemetry_EnsureInitialized();
   return g_telemetry_kpis.mr.samples;
}

int Telemetry_GetMinSamples()
{
   Telemetry_EnsureInitialized();
   return g_telemetry_kpis.min_samples;
}

#ifdef RPEA_TEST_RUNNER
void Telemetry_TestReset()
{
   g_telemetry_kpis.initialized = false;
   Telemetry_EnsureInitialized();
   ArrayResize(g_telemetry_positions, 0);
}

void Telemetry_TestSetMinSamples(const int min_samples)
{
   Telemetry_InitKpis(min_samples);
}

void Telemetry_TestRecordOutcome(const string strategy, const double outcome)
{
   Telemetry_RecordOutcome(strategy, outcome);
}

void Telemetry_TestProcessPositionEntry(const ulong position_id,
                                        const string strategy_hint,
                                        const datetime entry_time)
{
   Telemetry_OnPositionEntry(position_id, strategy_hint, entry_time);
}

bool Telemetry_TestProcessPositionExit(const ulong position_id,
                                       const string strategy_hint,
                                       const double net_outcome,
                                       const datetime exit_time,
                                       const bool position_closed)
{
   string strategy = "";
   double total_outcome = 0.0;
   int hold_minutes = 0;
   return Telemetry_OnPositionExit(position_id,
                                   strategy_hint,
                                   net_outcome,
                                   exit_time,
                                   position_closed,
                                   strategy,
                                   total_outcome,
                                   hold_minutes);
}

bool Telemetry_TestProcessPositionExitDetailed(const ulong position_id,
                                               const string strategy_hint,
                                               const double net_outcome,
                                               const datetime exit_time,
                                               const bool position_closed,
                                               string &out_strategy,
                                               double &out_total_outcome,
                                               int &out_hold_minutes)
{
   return Telemetry_OnPositionExit(position_id,
                                   strategy_hint,
                                   net_outcome,
                                   exit_time,
                                   position_closed,
                                   out_strategy,
                                   out_total_outcome,
                                   out_hold_minutes);
}

int Telemetry_TestGetTrackedPositionCount()
{
   return ArraySize(g_telemetry_positions);
}
#endif // RPEA_TEST_RUNNER

void LogMetaPolicyDecision(const string symbol,
                           const string choice,
                           const string gating_reason,
                           const string news_state,
                           const double confidence,
                           const double efficiency,
                           const double bwisc_conf,
                           const double mr_conf,
                           const double bwisc_eff,
                           const double mr_eff,
                           const double emrt_rank,
                           const double rho_est,
                           const double spread_q,
                           const double slippage_q,
                           const int hold_minutes_est,
                           const REGIME_LABEL regime)
{
   string regime_str;
   switch(regime)
   {
      case REGIME_TRENDING: regime_str = "TRENDING"; break;
      case REGIME_RANGING:  regime_str = "RANGING";  break;
      case REGIME_VOLATILE: regime_str = "VOLATILE"; break;
      default:              regime_str = "UNKNOWN";  break;
   }

   string fields = StringFormat(
      "{\"symbol\":\"%s\",\"choice\":\"%s\",\"confidence\":%.2f,\"efficiency\":%.2f,"
      "\"rho_est\":%.2f,\"gating_reason\":\"%s\",\"news_window_state\":\"%s\","
      "\"bwisc_conf\":%.2f,\"mr_conf\":%.2f,\"bwisc_eff\":%.2f,\"mr_eff\":%.2f,"
      "\"emrt\":%.2f,\"spread_q\":%.2f,\"slippage_q\":%.2f,\"hold_time_min\":%d,"
      "\"regime\":\"%s\"}",
      symbol,
      choice,
      confidence,
      efficiency,
      rho_est,
      gating_reason,
      news_state,
      bwisc_conf,
      mr_conf,
      bwisc_eff,
      mr_eff,
      emrt_rank,
      spread_q,
      slippage_q,
      hold_minutes_est,
      regime_str);

   LogDecision("MetaPolicy", "EVAL", fields);
}
#endif // RPEA_TELEMETRY_MQH
