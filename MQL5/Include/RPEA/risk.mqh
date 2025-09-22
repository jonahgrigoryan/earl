#ifndef RPEA_RISK_MQH
#define RPEA_RISK_MQH
// risk.mqh - Risk sizing helpers (M2 implementation)
// References: finalspec.md (Sizing by ATR distance)

#include "logging.mqh"

inline double Risk_FloorToStep(const double value, const double step)
{
   if(step <= 0.0)
      return 0.0;
   double ratio = value / step;
   double floored = MathFloor(ratio + 1e-8);
   return floored * step;
}

double Risk_SizingByATRDistanceForSymbol(const string symbol,
                                          const double entry, const double stop,
                                          const double equity, const double riskPct,
                                          double availableRoom = -1.0)
{
   if(symbol == NULL || symbol == "")
      return 0.0;
   if(!MathIsValidNumber(entry) || !MathIsValidNumber(stop) ||
      !MathIsValidNumber(equity) || !MathIsValidNumber(riskPct))
      return 0.0;
   if(entry <= 0.0 || equity <= 0.0 || riskPct <= 0.0)
      return 0.0;

   double point = 0.0;
   double tick_size = 0.0;
   double tick_value = 0.0;
   double vol_min = 0.0;
   double vol_max = 0.0;
   double vol_step = 0.0;

   if(!SymbolInfoDouble(symbol, SYMBOL_POINT, point) || point <= 0.0)
      return 0.0;
   if(!SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE, tick_size) || tick_size <= 0.0)
      return 0.0;
   if(!SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE, tick_value) || tick_value <= 0.0)
      return 0.0;
   if(!SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN, vol_min) || vol_min <= 0.0)
      return 0.0;
   if(!SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX, vol_max) || vol_max <= 0.0)
      return 0.0;
   if(!SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP, vol_step) || vol_step <= 0.0)
      return 0.0;

   double distance = MathAbs(entry - stop);
   if(distance <= 0.0)
      return 0.0;

   double risk_money = equity * (riskPct / 100.0);
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

   double tick_ratio = tick_size / point;
   if(tick_ratio <= 0.0)
      return 0.0;

   double value_per_point = tick_value / tick_ratio;
   if(value_per_point <= 0.0)
      return 0.0;

   double denom = sl_points * value_per_point;
   if(denom <= 0.0)
      return 0.0;

   double raw_volume = risk_money / denom;
   if(!MathIsValidNumber(raw_volume) || raw_volume <= 0.0)
      return 0.0;

   double volume = Risk_FloorToStep(raw_volume, vol_step);
   double max_allowed = Risk_FloorToStep(vol_max, vol_step);
   if(max_allowed <= 0.0)
      max_allowed = vol_max;
   if(volume > max_allowed)
      volume = max_allowed;

   if(volume < vol_min)
      volume = 0.0;

   double margin_used_pct = 0.0;
   double final_volume = volume;

   if(final_volume >= vol_min && final_volume > 0.0)
   {
      double free_margin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
      if(!MathIsValidNumber(free_margin) || free_margin <= 0.0)
      {
         final_volume = 0.0;
      }
      else
      {
         double volume_iter = final_volume;
         while(volume_iter >= vol_min && volume_iter > 0.0)
         {
            double required_margin = 0.0;
            if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, volume_iter, entry, required_margin) ||
               !MathIsValidNumber(required_margin))
            {
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
               final_volume = 0.0;
               margin_used_pct = 0.0;
               break;
            }
            volume_iter = next_volume;
         }
      }
   }

   final_volume = NormalizeDouble(final_volume, 8);
   double log_margin = margin_used_pct;
   if(final_volume <= 0.0)
   {
      final_volume = 0.0;
      log_margin = 0.0;
   }

   string log_fields = StringFormat(
      "{\"symbol\":\"%s\",\"entry\":%.5f,\"stop\":%.5f,\"risk_money\":%.2f,\"sl_points\":%.2f,\"raw_volume\":%.4f,\"final_volume\":%.4f,\"margin_used_pct\":%.2f,\"room_cap\":%.2f,\"clamped\":%s}",
      symbol,
      entry,
      stop,
      risk_money,
      sl_points,
      raw_volume,
      final_volume,
      log_margin,
      room_cap,
      clamped ? "true" : "false");
   LogDecision("Risk", "SIZING", log_fields);

   return final_volume;
}

double Risk_SizingByATRDistance(const double entry, const double stop,
                                const double equity, const double riskPct)
{
   return Risk_SizingByATRDistanceForSymbol(_Symbol, entry, stop, equity, riskPct);
}

#endif // RPEA_RISK_MQH
