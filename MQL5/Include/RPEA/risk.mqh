#ifndef RPEA_RISK_MQH
#define RPEA_RISK_MQH
// risk.mqh - Risk sizing helpers (M2 implementation)
// References: finalspec.md (Sizing by ATR distance)

#include <RPEA/config.mqh>
#include "logging.mqh"

struct RiskSizingDiagnostics
{
   bool   initialized;
   double raw_volume;
   double floored_volume;
   double final_volume;
   double volume_min;
   double volume_step;
   double raw_gap_to_min_lot_frac;
   double floored_gap_to_min_lot_frac;
   string volume_zero_subcause;
   double volume_zero_reference_volume;
   double volume_zero_gap_to_min_lot_frac;
};

static RiskSizingDiagnostics g_last_risk_sizing_diagnostics;

void Risk_ResetLastSizingDiagnostics()
{
   g_last_risk_sizing_diagnostics.initialized = false;
   g_last_risk_sizing_diagnostics.raw_volume = 0.0;
   g_last_risk_sizing_diagnostics.floored_volume = 0.0;
   g_last_risk_sizing_diagnostics.final_volume = 0.0;
   g_last_risk_sizing_diagnostics.volume_min = 0.0;
   g_last_risk_sizing_diagnostics.volume_step = 0.0;
   g_last_risk_sizing_diagnostics.raw_gap_to_min_lot_frac = 0.0;
   g_last_risk_sizing_diagnostics.floored_gap_to_min_lot_frac = 0.0;
   g_last_risk_sizing_diagnostics.volume_zero_subcause = "";
   g_last_risk_sizing_diagnostics.volume_zero_reference_volume = 0.0;
   g_last_risk_sizing_diagnostics.volume_zero_gap_to_min_lot_frac = 0.0;
}

inline double Risk_GapToMinLotFraction(const double volume, const double volume_min)
{
   if(!MathIsValidNumber(volume) || !MathIsValidNumber(volume_min) || volume_min <= 0.0)
      return 0.0;

   double gap = (volume_min - volume) / volume_min;
   return (gap > 0.0 ? gap : 0.0);
}

void Risk_SetVolumeZeroDiagnostics(const string subcause,
                                   const double reference_volume,
                                   const double volume_min)
{
   g_last_risk_sizing_diagnostics.volume_zero_subcause = subcause;
   g_last_risk_sizing_diagnostics.volume_zero_reference_volume = reference_volume;
   g_last_risk_sizing_diagnostics.volume_zero_gap_to_min_lot_frac =
      Risk_GapToMinLotFraction(reference_volume, volume_min);
}

inline double Risk_FloorToStep(const double value, const double step)
{
   if(step <= 0.0)
      return 0.0;
   double ratio = value / step;
   double floored = MathFloor(ratio + 1e-8);
   return floored * step;
}

inline ENUM_ORDER_TYPE Risk_InferOrderTypeFromStop(const double entry, const double stop)
{
   return (stop < entry ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
}

double Risk_CalcStopLossPerLot(const string symbol,
                               const double entry,
                               const double stop,
                               const double point,
                               const double min_stop_points,
                               double &sl_points,
                               double &calc_stop)
{
   if(symbol == NULL || symbol == "")
      return 0.0;
   if(!MathIsValidNumber(entry) || !MathIsValidNumber(stop) || !MathIsValidNumber(point))
      return 0.0;
   if(entry <= 0.0 || point <= 0.0)
      return 0.0;

   sl_points = MathAbs(entry - stop) / point;
   if(min_stop_points > 0.0)
      sl_points = MathMax(sl_points, min_stop_points);
   if(sl_points <= 0.0)
      return 0.0;

   ENUM_ORDER_TYPE order_type = Risk_InferOrderTypeFromStop(entry, stop);
   double direction = (order_type == ORDER_TYPE_BUY ? -1.0 : 1.0);
   calc_stop = entry + (sl_points * point * direction);

   double loss = 0.0;
   if(!OrderCalcProfit(order_type, symbol, 1.0, entry, calc_stop, loss))
      return 0.0;

   loss = MathAbs(loss);
   if(!MathIsValidNumber(loss) || loss <= 0.0)
      return 0.0;

   return loss;
}

double Risk_SizingByATRDistanceForSymbol(const string symbol,
                                          const double entry, const double stop,
                                          const double equity, const double riskPct,
                                          double availableRoom = -1.0,
                                          double confidence = 1.0)
{
   Risk_ResetLastSizingDiagnostics();

   if(symbol == NULL || symbol == "")
      return 0.0;
   if(!MathIsValidNumber(entry) || !MathIsValidNumber(stop) ||
      !MathIsValidNumber(equity) || !MathIsValidNumber(riskPct))
      return 0.0;
   if(entry <= 0.0 || equity <= 0.0 || riskPct <= 0.0)
      return 0.0;

   // Defense-in-depth: sanitize confidence even though allocator may have sanitized it
   if(!MathIsValidNumber(confidence)) confidence = 0.0; // Fail safe for NaN
   double effective_conf = MathMin(MathMax(confidence, 0.0), 1.0); // Clamp to [0.0, 1.0]
   double effective_risk_pct = riskPct * effective_conf;

   double point = 0.0;
   double vol_min = 0.0;
   double vol_max = 0.0;
   double vol_step = 0.0;

   if(!SymbolInfoDouble(symbol, SYMBOL_POINT, point) || point <= 0.0)
      return 0.0;
   if(!SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN, vol_min) || vol_min <= 0.0)
      return 0.0;
   if(!SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX, vol_max) || vol_max <= 0.0)
      return 0.0;
   if(!SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP, vol_step) || vol_step <= 0.0)
      return 0.0;

   g_last_risk_sizing_diagnostics.initialized = true;
   g_last_risk_sizing_diagnostics.volume_min = vol_min;
   g_last_risk_sizing_diagnostics.volume_step = vol_step;

   double distance = MathAbs(entry - stop);
   if(distance <= 0.0)
      return 0.0;

   double risk_money = equity * (effective_risk_pct / 100.0);
   if(risk_money <= 0.0)
      return 0.0;

   double room_cap = -1.0;
   bool clamped = false;
   if(MathIsValidNumber(availableRoom) && availableRoom >= 0.0)
   {
      room_cap = availableRoom;
      double capped_money = MathMin(risk_money, availableRoom);
      clamped = (capped_money < risk_money - 1e-8);
      risk_money = capped_money;
      if(risk_money <= 0.0)
         return 0.0;
   }

   double sl_points = distance / point;
   double min_stop = (double)MinStopPoints;
   if(min_stop > 0.0)
      sl_points = MathMax(sl_points, min_stop);

   double calc_stop = stop;
   double loss_per_lot = Risk_CalcStopLossPerLot(symbol,
                                                 entry,
                                                 stop,
                                                 point,
                                                 min_stop,
                                                 sl_points,
                                                 calc_stop);
   if(loss_per_lot <= 0.0)
      return 0.0;

   double raw_volume = risk_money / loss_per_lot;
   if(!MathIsValidNumber(raw_volume) || raw_volume <= 0.0)
      return 0.0;

   g_last_risk_sizing_diagnostics.raw_volume = raw_volume;
   g_last_risk_sizing_diagnostics.raw_gap_to_min_lot_frac =
      Risk_GapToMinLotFraction(raw_volume, vol_min);

   double volume = Risk_FloorToStep(raw_volume, vol_step);
   double max_allowed = Risk_FloorToStep(vol_max, vol_step);
   if(max_allowed <= 0.0)
      max_allowed = vol_max;
   if(volume > max_allowed)
      volume = max_allowed;

   g_last_risk_sizing_diagnostics.floored_volume = volume;
   g_last_risk_sizing_diagnostics.floored_gap_to_min_lot_frac =
      Risk_GapToMinLotFraction(volume, vol_min);

   if(volume < vol_min)
   {
      Risk_SetVolumeZeroDiagnostics("below_min_after_step", raw_volume, vol_min);
      volume = 0.0;
   }

   double margin_used_pct = 0.0;
   double final_volume = volume;
   ENUM_ORDER_TYPE order_type = Risk_InferOrderTypeFromStop(entry, stop);

#ifndef RPEA_RISK_SKIP_MARGIN_CHECK
   if(final_volume >= vol_min && final_volume > 0.0)
   {
      double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(!MathIsValidNumber(free_margin) || free_margin <= 0.0)
      {
         Risk_SetVolumeZeroDiagnostics("margin_check_failed", final_volume, vol_min);
         final_volume = 0.0;
      }
      else
      {
         double volume_iter = final_volume;
         while(volume_iter >= vol_min && volume_iter > 0.0)
         {
            double required_margin = 0.0;
            if(!OrderCalcMargin(order_type, symbol, volume_iter, entry, required_margin) ||
               !MathIsValidNumber(required_margin))
            {
               Risk_SetVolumeZeroDiagnostics("margin_check_failed", volume_iter, vol_min);
               final_volume = 0.0;
               margin_used_pct = 0.0;
               volume_iter = 0.0;
               break;
            }

            if(required_margin <= 0.0)
            {
               final_volume = volume_iter;
               margin_used_pct = 0.0;
               break;
            }

            margin_used_pct = (required_margin / free_margin) * 100.0;

            if(margin_used_pct <= 60.0)
            {
               final_volume = volume_iter;
               break;
            }

            // Decrease size in steps until estimated margin usage is <=60%.
            double next_volume = Risk_FloorToStep(volume_iter - vol_step, vol_step);
            if(next_volume < vol_min || next_volume <= 0.0)
            {
               Risk_SetVolumeZeroDiagnostics("below_min_after_margin", volume_iter, vol_min);
               final_volume = 0.0;
               margin_used_pct = 0.0;
               break;
            }
            volume_iter = next_volume;
         }
      }
   }
#endif

   final_volume = NormalizeDouble(final_volume, 8);
   g_last_risk_sizing_diagnostics.final_volume = final_volume;
   double log_margin = margin_used_pct;
   if(final_volume <= 0.0)
   {
      final_volume = 0.0;
      g_last_risk_sizing_diagnostics.final_volume = 0.0;
      log_margin = 0.0;
   }

   string log_fields = StringFormat(
      "{\"symbol\":\"%s\",\"entry\":%.5f,\"stop\":%.5f,\"calc_stop\":%.5f,\"risk_money\":%.2f,\"confidence\":%.2f,\"effective_risk_pct\":%.2f,\"sl_points\":%.2f,\"loss_per_lot\":%.2f,\"raw_volume\":%.8f,\"floored_volume\":%.8f,\"final_volume\":%.8f,\"volume_min\":%.8f,\"volume_step\":%.8f,\"raw_gap_to_min_lot_frac\":%.8f,\"floored_gap_to_min_lot_frac\":%.8f,\"margin_used_pct\":%.2f,\"room_cap\":%.2f,\"clamped\":%s",
      symbol,
      entry,
      stop,
      calc_stop,
      risk_money,
      effective_conf,
      effective_risk_pct,
      sl_points,
      loss_per_lot,
      raw_volume,
      g_last_risk_sizing_diagnostics.floored_volume,
      final_volume,
      vol_min,
      vol_step,
      g_last_risk_sizing_diagnostics.raw_gap_to_min_lot_frac,
      g_last_risk_sizing_diagnostics.floored_gap_to_min_lot_frac,
      log_margin,
      room_cap,
      clamped ? "true" : "false");
   if(StringLen(g_last_risk_sizing_diagnostics.volume_zero_subcause) > 0)
   {
      log_fields += StringFormat(
         ",\"volume_zero_subcause\":\"%s\",\"volume_zero_reference_volume\":%.8f,\"volume_zero_gap_to_min_lot_frac\":%.8f",
         g_last_risk_sizing_diagnostics.volume_zero_subcause,
         g_last_risk_sizing_diagnostics.volume_zero_reference_volume,
         g_last_risk_sizing_diagnostics.volume_zero_gap_to_min_lot_frac
      );
   }
   log_fields += "}";
   LogDecision("Risk", "SIZING", log_fields);

   return final_volume;
}

double Risk_SizingByATRDistance(const double entry, const double stop,
                                const double equity, const double riskPct,
                                double confidence = 1.0)
{
   return Risk_SizingByATRDistanceForSymbol(_Symbol, entry, stop, equity, riskPct, -1.0, confidence);
}

//==============================================================================
// M4-Task02: Micro-Mode Risk Override
//==============================================================================

// Forward declaration for Micro-Mode check
#ifndef EQUITY_MICRO_FORWARD_DECLARED
#define EQUITY_MICRO_FORWARD_DECLARED
bool Equity_IsMicroModeActive();
#endif

// Forward declarations for inputs (defined in RPEA.mq5)
#ifdef RPEA_TEST_RUNNER
#ifndef RiskPct
#define RiskPct 1.0
#endif
#ifndef MicroRiskPct
#define MicroRiskPct DEFAULT_MicroRiskPct
#endif
#endif

// Get effective risk percentage (respects Micro-Mode)
double Risk_GetEffectiveRiskPct()
{
   return Equity_IsMicroModeActive() ? Config_GetMicroRiskPct() : Config_GetRiskPct();
}

#endif // RPEA_RISK_MQH
