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
   double   worst_case_risk_money_total;
   double   theoretical_r_weighted_sum;
   double   theoretical_r_risk_weight_sum;
   double   entry_volume_initial;
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

bool Telemetry_GetContractDetails(const string symbol,
                                  double &point,
                                  double &value_per_point)
{
   point = 0.0;
   value_per_point = 0.0;

   if(symbol == "")
      return false;

   double tick_size = 0.0;
   double tick_value = 0.0;
   if(!SymbolInfoDouble(symbol, SYMBOL_POINT, point) || point <= 0.0)
      return false;
   if(!SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE, tick_size) || tick_size <= 0.0)
      return false;
   if(!SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE, tick_value) || tick_value <= 0.0)
      return false;

   double ratio = tick_size / point;
   if(ratio <= 0.0)
      return false;

   value_per_point = tick_value / ratio;
   return (value_per_point > 0.0);
}

bool Telemetry_CalculateEntryRiskBasis(const string symbol,
                                       const double entry_price,
                                       const double sl_price,
                                       const double tp_price,
                                       const double entry_volume,
                                       double &out_worst_case_risk_money,
                                       double &out_theoretical_r)
{
   out_worst_case_risk_money = 0.0;
   out_theoretical_r = 0.0;

   if(symbol == "")
      return false;
   if(!MathIsValidNumber(entry_price) || !MathIsValidNumber(sl_price) ||
      !MathIsValidNumber(tp_price) || !MathIsValidNumber(entry_volume))
   {
      return false;
   }
   if(entry_price <= 0.0 || sl_price <= 0.0 || tp_price <= 0.0 || entry_volume <= 0.0)
      return false;

   double sl_distance = MathAbs(entry_price - sl_price);
   double tp_distance = MathAbs(tp_price - entry_price);
   if(sl_distance <= 0.0 || tp_distance <= 0.0)
      return false;

   double point = 0.0;
   double value_per_point = 0.0;
   if(!Telemetry_GetContractDetails(symbol, point, value_per_point))
      return false;

   double sl_points = sl_distance / point;
   if(!MathIsValidNumber(sl_points) || sl_points <= 0.0)
      return false;

   double risk_money = sl_points * value_per_point * entry_volume;
   if(!MathIsValidNumber(risk_money) || risk_money <= 0.0)
      return false;

   double theoretical_r = tp_distance / sl_distance;
   if(!MathIsValidNumber(theoretical_r) || theoretical_r <= 0.0)
      return false;

   out_worst_case_risk_money = risk_money;
   out_theoretical_r = theoretical_r;
   return true;
}

double Telemetry_ComputeFrictionTaxR(const double theoretical_r,
                                     const double realized_r)
{
   if(!MathIsValidNumber(theoretical_r) || !MathIsValidNumber(realized_r))
      return 0.0;
   if(theoretical_r <= 0.0)
      return 0.0;

   double friction_r = theoretical_r - realized_r;
   if(!MathIsValidNumber(friction_r))
      return 0.0;
   if(friction_r < 0.0)
      friction_r = 0.0;
   return friction_r;
}

bool Telemetry_GetTrackerRiskBasis(const int index,
                                   double &out_worst_case_risk_money_total,
                                   double &out_theoretical_r)
{
   out_worst_case_risk_money_total = 0.0;
   out_theoretical_r = 0.0;

   int count = ArraySize(g_telemetry_positions);
   if(index < 0 || index >= count)
      return false;

   out_worst_case_risk_money_total = g_telemetry_positions[index].worst_case_risk_money_total;
   double denom = g_telemetry_positions[index].theoretical_r_risk_weight_sum;
   if(!MathIsValidNumber(out_worst_case_risk_money_total) || out_worst_case_risk_money_total <= 0.0)
      return false;
   if(!MathIsValidNumber(denom) || denom <= 0.0)
      return false;

   out_theoretical_r = g_telemetry_positions[index].theoretical_r_weighted_sum / denom;
   if(!MathIsValidNumber(out_theoretical_r) || out_theoretical_r <= 0.0)
      return false;

   return true;
}

void Telemetry_OnPositionEntryDetailed(const ulong position_id,
                                       const string strategy_hint,
                                       const datetime entry_time,
                                       const string symbol,
                                       const double entry_price,
                                       const double sl_price,
                                       const double tp_price,
                                       const double entry_volume)
{
   if(position_id == 0)
      return;

   string strategy = Telemetry_NormalizeStrategy(strategy_hint);
   if(strategy == "")
      return;

   datetime resolved_entry_time = entry_time;
   if(resolved_entry_time <= 0)
      resolved_entry_time = TimeCurrent();

   double leg_risk_money = 0.0;
   double leg_theoretical_r = 0.0;
   bool has_leg_basis = Telemetry_CalculateEntryRiskBasis(symbol,
                                                          entry_price,
                                                          sl_price,
                                                          tp_price,
                                                          entry_volume,
                                                          leg_risk_money,
                                                          leg_theoretical_r);

   int index = Telemetry_FindPositionTracker(position_id);
   if(index >= 0)
   {
      g_telemetry_positions[index].strategy = strategy;
      if(g_telemetry_positions[index].entry_time <= 0 ||
         resolved_entry_time < g_telemetry_positions[index].entry_time)
      {
         g_telemetry_positions[index].entry_time = resolved_entry_time;
      }
      if(g_telemetry_positions[index].entry_volume_initial <= 0.0 &&
         MathIsValidNumber(entry_volume) && entry_volume > 0.0)
      {
         g_telemetry_positions[index].entry_volume_initial = entry_volume;
      }
      if(has_leg_basis)
      {
         g_telemetry_positions[index].worst_case_risk_money_total += leg_risk_money;
         g_telemetry_positions[index].theoretical_r_weighted_sum += (leg_theoretical_r * leg_risk_money);
         g_telemetry_positions[index].theoretical_r_risk_weight_sum += leg_risk_money;
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
   g_telemetry_positions[count].worst_case_risk_money_total = 0.0;
   g_telemetry_positions[count].theoretical_r_weighted_sum = 0.0;
   g_telemetry_positions[count].theoretical_r_risk_weight_sum = 0.0;
   g_telemetry_positions[count].entry_volume_initial =
      (MathIsValidNumber(entry_volume) && entry_volume > 0.0 ? entry_volume : 0.0);

   if(has_leg_basis)
   {
      g_telemetry_positions[count].worst_case_risk_money_total = leg_risk_money;
      g_telemetry_positions[count].theoretical_r_weighted_sum = leg_theoretical_r * leg_risk_money;
      g_telemetry_positions[count].theoretical_r_risk_weight_sum = leg_risk_money;
   }
}

void Telemetry_OnPositionEntry(const ulong position_id,
                               const string strategy_hint,
                               const datetime entry_time)
{
   Telemetry_OnPositionEntryDetailed(position_id,
                                     strategy_hint,
                                     entry_time,
                                     "",
                                     0.0,
                                     0.0,
                                     0.0,
                                     0.0);
}

bool Telemetry_OnPositionExitWithTheory(const ulong position_id,
                                        const string strategy_hint,
                                        const double net_outcome,
                                        const double theoretical_outcome,
                                        const datetime exit_time,
                                        const bool position_closed,
                                        string &out_strategy,
                                        double &out_total_outcome,
                                        int &out_hold_minutes,
                                        double &out_friction_r)
{
   out_strategy = "";
   out_total_outcome = 0.0;
   out_hold_minutes = 0;
   out_friction_r = 0.0;

   if(position_id == 0)
      return false;

   string fallback_strategy = Telemetry_NormalizeStrategy(strategy_hint);
   if(!MathIsValidNumber(theoretical_outcome))
   {
      // Parameter retained for backward compatibility with existing call sites.
   }
   int index = Telemetry_FindPositionTracker(position_id);

   if(index < 0)
   {
      if(!position_closed || fallback_strategy == "")
         return false;

      out_strategy = fallback_strategy;
      out_total_outcome = net_outcome;
      out_hold_minutes = 0;
      out_friction_r = 0.0;
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
   double worst_case_risk_money_total = 0.0;
   double theoretical_r = 0.0;
   if(Telemetry_GetTrackerRiskBasis(index, worst_case_risk_money_total, theoretical_r))
   {
      double realized_r = out_total_outcome / worst_case_risk_money_total;
      if(!MathIsValidNumber(realized_r))
         realized_r = 0.0;
      out_friction_r = Telemetry_ComputeFrictionTaxR(theoretical_r, realized_r);
   }
   else
   {
      out_friction_r = 0.0;
   }

   Telemetry_RemovePositionTrackerAt(index);

   if(out_strategy == "")
      return false;

   Telemetry_OnTradeClosed(out_strategy, out_total_outcome, out_hold_minutes);
   return true;
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
   double friction_r = 0.0;
   return Telemetry_OnPositionExitWithTheory(position_id,
                                             strategy_hint,
                                             net_outcome,
                                             0.0,
                                             exit_time,
                                             position_closed,
                                             out_strategy,
                                             out_total_outcome,
                                             out_hold_minutes,
                                             friction_r);
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
   // Finalized in post-M7 closeout: throttle control is owned by SLO/meta-policy.
   // Keep this hook deterministic and side-effect free for backward compatibility.
   Telemetry_UpdateKpis();
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

void Telemetry_TestProcessPositionEntryDetailed(const ulong position_id,
                                                const string strategy_hint,
                                                const datetime entry_time,
                                                const string symbol,
                                                const double entry_price,
                                                const double sl_price,
                                                const double tp_price,
                                                const double entry_volume)
{
   Telemetry_OnPositionEntryDetailed(position_id,
                                     strategy_hint,
                                     entry_time,
                                     symbol,
                                     entry_price,
                                     sl_price,
                                     tp_price,
                                     entry_volume);
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

bool Telemetry_TestProcessPositionExitDetailedWithTheory(const ulong position_id,
                                                         const string strategy_hint,
                                                         const double net_outcome,
                                                         const double theoretical_outcome,
                                                         const datetime exit_time,
                                                         const bool position_closed,
                                                         string &out_strategy,
                                                         double &out_total_outcome,
                                                         int &out_hold_minutes,
                                                         double &out_friction_r)
{
   return Telemetry_OnPositionExitWithTheory(position_id,
                                             strategy_hint,
                                             net_outcome,
                                             theoretical_outcome,
                                             exit_time,
                                             position_closed,
                                             out_strategy,
                                             out_total_outcome,
                                             out_hold_minutes,
                                             out_friction_r);
}

int Telemetry_TestGetTrackedPositionCount()
{
   return ArraySize(g_telemetry_positions);
}

bool Telemetry_TestGetPositionRiskBasis(const ulong position_id,
                                        double &out_worst_case_risk_money_total,
                                        double &out_theoretical_r)
{
   int index = Telemetry_FindPositionTracker(position_id);
   return Telemetry_GetTrackerRiskBasis(index,
                                        out_worst_case_risk_money_total,
                                        out_theoretical_r);
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

void Telemetry_LogBanditShadowDelta(const string symbol,
                                    const string bandit_choice,
                                    const string deterministic_choice,
                                    const bool bandit_ready)
{
   bool delta = (bandit_choice != deterministic_choice);
   string fields = StringFormat(
      "{\"symbol\":\"%s\",\"bandit\":\"%s\",\"deterministic\":\"%s\","
      "\"delta\":%s,\"bandit_ready\":%s}",
      symbol,
      bandit_choice,
      deterministic_choice,
      delta ? "true" : "false",
      bandit_ready ? "true" : "false");
   LogDecision("MetaPolicy", "SHADOW", fields);
}
#endif // RPEA_TELEMETRY_MQH
