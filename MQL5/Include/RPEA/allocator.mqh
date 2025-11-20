#ifndef RPEA_ALLOCATOR_MQH
#define RPEA_ALLOCATOR_MQH
// allocator.mqh - Risk allocator implementation (M2)
// References: finalspec.md (Allocator Integration)

#include <Trade\Trade.mqh>
#include <RPEA/logging.mqh>
#include <RPEA/risk.mqh>
#include <RPEA/equity_guardian.mqh>
#include <RPEA/symbol_bridge.mqh>

struct AppContext;

struct OrderPlan
{
   bool            valid;
   string          symbol;
   string          signal_symbol;
   ENUM_ORDER_TYPE order_type;
   double          volume;
   double          price;
   double          sl;
   double          tp;
   string          comment;
   long            magic;
   string          setup_type;
   double          bias;
   string          rejection_reason;
   bool            is_proxy;
   double          proxy_rate;
   double          signal_sl_points;
   double          signal_tp_points;
   string          proxy_context;
};

// Helpers ----------------------------------------------------------
string Allocator_TrimComment(const string text)
{
   const int max_len = 31;
   if(StringLen(text) <= max_len)
      return text;
   return StringSubstr(text, 0, max_len);
}

bool Allocator_GetContractDetails(const string symbol,
                                  double &point,
                                  double &value_per_point,
                                  int &digits)
{
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
   if(value_per_point <= 0.0)
      return false;
   long digits_long = 0;
   if(!SymbolInfoInteger(symbol, SYMBOL_DIGITS, digits_long))
      digits = 5;
   else
      digits = (int)digits_long;
   return true;
}

long Allocator_ComputeMagic(const AppContext& ctx, const string symbol)
{
   for(int i = 0; i < ctx.symbols_count; ++i)
   {
      if(ctx.symbols[i] == symbol)
         return MagicBase + i;
   }

   long hash = 0;
   int len = StringLen(symbol);
   for(int i = 0; i < len; ++i)
   {
      hash = (hash * 131 + StringGetCharacter(symbol, i)) & 0x7FFFFFFF;
   }
   return MagicBase + hash % 1000;
}

double Allocator_NormalizePrice(const double price, const int digits)
{
   if(digits <= 0)
      return price;
   return NormalizeDouble(price, digits);
}

// Main builder -----------------------------------------------------
OrderPlan Allocator_BuildOrderPlan(const AppContext& ctx,
                                   const string strategy,
                                   const string symbol,
                                   const int slPoints,
                                   const int tpPoints,
                                   const double confidence)
{
   OrderPlan plan;
   plan.valid = false;
   const string signal_symbol = symbol;
   const string exec_symbol = SymbolBridge_GetExecutionSymbol(signal_symbol);
   plan.symbol = exec_symbol;
   plan.signal_symbol = signal_symbol;
   plan.order_type = ORDER_TYPE_BUY;
   plan.volume = 0.0;
   plan.price = 0.0;
   plan.sl = 0.0;
   plan.tp = 0.0;
   plan.comment = "";
   plan.magic = Allocator_ComputeMagic(ctx, exec_symbol);
   plan.setup_type = "None";
   plan.bias = 0.0;
   plan.rejection_reason = "";
   plan.proxy_rate = 1.0;
   plan.signal_sl_points = (double)slPoints;
   plan.signal_tp_points = (double)tpPoints;
   plan.proxy_context = "";
   plan.is_proxy = (signal_symbol != exec_symbol);
   if(plan.is_proxy)
      plan.proxy_context = signal_symbol + "->" + exec_symbol;

   string rejection = "";

   if(strategy != "BWISC")
   {
      rejection = "unsupported_strategy";
   }
   else if(exec_symbol == "")
   {
      rejection = "invalid_symbol";
   }
   else if(slPoints <= 0 || tpPoints <= 0)
   {
      rejection = "invalid_sl_tp";
   }

   double entry_price = 0.0;
   int direction = 0;
  if(rejection == "")
  {
     entry_price = g_last_bwisc_context.entry_price;
     direction = g_last_bwisc_context.direction;
     if(entry_price <= 0.0)
        rejection = "missing_entry_price";
  }

   double point = 0.0;
   double value_per_point = 0.0;
   int digits = 0;
   if(rejection == "" && !Allocator_GetContractDetails(exec_symbol, point, value_per_point, digits))
      rejection = "symbol_contract";

  double bid = 0.0;
  double ask = 0.0;
  if(rejection == "")
  {
      if(!SymbolInfoDouble(exec_symbol, SYMBOL_BID, bid) || !MathIsValidNumber(bid))
         rejection = "symbol_bid";
      if(!SymbolInfoDouble(exec_symbol, SYMBOL_ASK, ask) || !MathIsValidNumber(ask))
         rejection = "symbol_ask";
  }

  ENUM_ORDER_TYPE order_type = ORDER_TYPE_BUY;
  string setup_type = "";
  if(rejection == "")
  {
     double epsilon = point * 0.5;
     if(direction > 0 || direction < 0)
     {
        if(direction > 0)
        {
           if(entry_price >= ask + epsilon)
           {
              order_type = ORDER_TYPE_BUY_STOP;
              setup_type = "BC";
           }
           else if(entry_price <= bid - epsilon)
           {
             order_type = ORDER_TYPE_BUY_LIMIT;
             setup_type = "MSC";
           }
           else
           {
              order_type = ORDER_TYPE_BUY;
              setup_type = "BC";
           }
        }
        else
        {
           if(entry_price <= bid - epsilon)
           {
              order_type = ORDER_TYPE_SELL_STOP;
              setup_type = "BC";
           }
           else if(entry_price >= ask + epsilon)
           {
              order_type = ORDER_TYPE_SELL_LIMIT;
              setup_type = "MSC";
           }
           else
           {
              order_type = ORDER_TYPE_SELL;
              setup_type = "BC";
           }
        }
     }
     else
     {
        // Fallback when direction not provided: infer setup type from tp/sl ratio
        double ratio = ((double)slPoints > 0.0 ? ((double)tpPoints) / (double)slPoints : 0.0);
        double diff_bc = MathAbs(ratio - RtargetBC);
        double diff_msc = MathAbs(ratio - RtargetMSC);
        double tolerance = 0.35;
        string setup_guess = (diff_bc <= diff_msc ? "BC" : "MSC");
        if(MathMin(diff_bc, diff_msc) > tolerance)
           setup_guess = "BC"; // default to BC if inconclusive

        if(setup_guess == "BC")
        {
           if(entry_price >= ask + epsilon)
           {
              order_type = ORDER_TYPE_BUY_STOP; setup_type = "BC"; direction = +1;
           }
           else if(entry_price <= bid - epsilon)
           {
              order_type = ORDER_TYPE_SELL_STOP; setup_type = "BC"; direction = -1;
           }
           else
           {
              rejection = "entry_inside_spread";
           }
        }
        else // MSC
        {
          if(entry_price <= bid - epsilon)
          {
             order_type = ORDER_TYPE_BUY_LIMIT; setup_type = "MSC"; direction = +1;
          }
          else if(entry_price >= ask + epsilon)
          {
             order_type = ORDER_TYPE_SELL_LIMIT; setup_type = "MSC"; direction = -1;
          }
          else
          {
             rejection = "entry_inside_spread";
          }
        }
     }
  }

   if(rejection == "")
   {
      if(setup_type == "")
         rejection = "setup_unknown";
      else if(setup_type == "BC" && order_type != ORDER_TYPE_BUY_STOP && order_type != ORDER_TYPE_SELL_STOP)
         rejection = "bc_not_stop";
      else if(setup_type == "MSC" && order_type != ORDER_TYPE_BUY_LIMIT && order_type != ORDER_TYPE_SELL_LIMIT)
         rejection = "msc_not_limit";
   }

   double exec_sl_points = plan.signal_sl_points;
   double exec_tp_points = plan.signal_tp_points;
   if(rejection == "" && plan.is_proxy)
     {
      double mapped = 0.0;
      double eurusd_rate = 0.0;
      if(!SymbolBridge_MapDistance(signal_symbol,
                                   exec_symbol,
                                   plan.signal_sl_points,
                                   mapped,
                                   eurusd_rate) ||
         mapped <= 0.0)
        {
         rejection = "xaueur_distance_unavailable";
        }
      else
        {
         exec_sl_points = mapped;
         plan.proxy_rate = eurusd_rate;
        }

      if(rejection == "")
        {
         double mapped_tp = 0.0;
         double eurusd_tp = 0.0;
         if(!SymbolBridge_MapDistance(signal_symbol,
                                      exec_symbol,
                                      plan.signal_tp_points,
                                      mapped_tp,
                                      eurusd_tp) ||
            mapped_tp <= 0.0)
           {
            rejection = "xaueur_distance_unavailable";
           }
         else
           {
            exec_tp_points = mapped_tp;
            plan.proxy_rate = eurusd_tp;
           }
        }
     }

   double sl_distance = 0.0;
   double tp_distance = 0.0;
   double sl_price = 0.0;
   double tp_price = 0.0;
   if(rejection == "")
   {
      sl_distance = exec_sl_points * point;
      tp_distance = exec_tp_points * point;
      if(sl_distance <= 0.0 || tp_distance <= 0.0)
         rejection = "distance_zero";
      else
      {
         if(direction > 0)
         {
            sl_price = entry_price - sl_distance;
            tp_price = entry_price + tp_distance;
         }
         else
         {
            sl_price = entry_price + sl_distance;
            tp_price = entry_price - tp_distance;
         }
         if(sl_price <= 0.0 || tp_price <= 0.0)
            rejection = "price_bounds";
      }
   }

   if(rejection == "")
   {
      entry_price = Allocator_NormalizePrice(entry_price, digits);
      sl_price = Allocator_NormalizePrice(sl_price, digits);
      tp_price = Allocator_NormalizePrice(tp_price, digits);
   }

   double equity = ctx.equity_snapshot;
   if(rejection == "" && (!MathIsValidNumber(equity) || equity <= 0.0))
   {
      equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(!MathIsValidNumber(equity) || equity <= 0.0)
         rejection = "equity_snapshot";
   }

   double volume = 0.0;
   if(rejection == "")
   {
      volume = Risk_SizingByATRDistanceForSymbol(exec_symbol, entry_price, sl_price, equity, RiskPct);
      if(volume <= 0.0)
         rejection = "volume_zero";
   }

   double worst_case = 0.0;
   if(rejection == "")
   {
      double distance = MathAbs(entry_price - sl_price);
      if(distance <= 0.0)
         rejection = "risk_calc";
      else
      {
         double points = distance / point;
         double risk = volume * value_per_point * points;
         if(!MathIsValidNumber(risk))
            rejection = "risk_calc";
         else
            worst_case = MathAbs(risk);
      }
   }

   EquityBudgetGateResult budget;
   budget.approved = false;
   budget.gate_pass = false;
   budget.gating_reason = "";
   budget.room_available = 0.0;
   budget.open_risk = 0.0;
   budget.pending_risk = 0.0;
   budget.next_worst_case = 0.0;
   budget.calculation_error = false;
  if(rejection == "")
  {
     budget = Equity_EvaluateBudgetGate(ctx, worst_case);
     if(budget.calculation_error)
        rejection = "budget_calc";
     else if(!budget.gate_pass)
     {
        // Attempt headroom-capped scaling instead of immediate reject
        if(MathIsValidNumber(budget.room_available) && budget.room_available > 0.0 && MathIsValidNumber(worst_case) && worst_case > 0.0)
        {
           double scale = budget.room_available / worst_case;
           if(scale > 0.0 && scale < 1.0)
           {
              double step=0.0, vmin=0.0, vmax=0.0;
              if(!SymbolInfoDouble(exec_symbol, SYMBOL_VOLUME_STEP, step) || step<=0.0) step = 0.01;
              if(!SymbolInfoDouble(exec_symbol, SYMBOL_VOLUME_MIN, vmin) || vmin<=0.0) vmin = step;
              if(!SymbolInfoDouble(exec_symbol, SYMBOL_VOLUME_MAX, vmax) || vmax<=0.0) vmax = 100.0;
              double vol_scaled = volume * scale;
              // Quantize to step and clamp
              vol_scaled = MathFloor(vol_scaled/step) * step;
              if(vol_scaled < vmin) vol_scaled = 0.0;
              if(vol_scaled > vmax) vol_scaled = vmax;
              if(vol_scaled > 0.0)
              {
                 volume = vol_scaled;
                 // Recompute worst_case with scaled volume
                 double distance2 = MathAbs(entry_price - sl_price);
                 double points2 = distance2 / point;
                 worst_case = MathAbs(volume * value_per_point * points2);
                 // Re-evaluate budget gate
                 EquityBudgetGateResult budget2 = Equity_EvaluateBudgetGate(ctx, worst_case);
                 if(!budget2.calculation_error && budget2.gate_pass)
                 {
                    budget = budget2;
                    rejection = "";
                 }
                 else
                 {
                    rejection = "budget_gate";
                 }
              }
              else
              {
                 rejection = "budget_gate";
              }
           }
           else
           {
              rejection = "budget_gate";
           }
        }
        else
        {
           rejection = "budget_gate";
        }
     }
  }

   int total_positions = 0;
   int symbol_positions = 0;
   int symbol_pending = 0;
   if(rejection == "")
   {
      if(!Equity_CheckPositionCaps(exec_symbol, total_positions, symbol_positions, symbol_pending))
         rejection = "position_caps";
   }

   double sanitized_confidence = (MathIsValidNumber(confidence) ? confidence : 0.0);

  if(rejection == "")
  {
     plan.valid = true;
     plan.volume = volume;
     plan.order_type = order_type;
     plan.price = entry_price;
     plan.sl = sl_price;
     plan.tp = tp_price;
     plan.setup_type = setup_type;
     plan.bias = 0.0;
     double bias_magnitude = MathMin(MathAbs(sanitized_confidence), 1.0);
     if(!MathIsValidNumber(bias_magnitude))
        bias_magnitude = 0.0;
     if(setup_type == "BC")
        plan.bias = (double)direction * bias_magnitude;
     else if(setup_type == "MSC")
        plan.bias = (double)(-direction) * bias_magnitude;

     string ts = TimeToString(ctx.current_server_time, TIME_DATE|TIME_MINUTES);
     string prefix = (plan.is_proxy ? "PX " : "");
     string comment = StringFormat("%sBWISC-%s b=%.2f conf=%.2f %s", prefix, setup_type, plan.bias, sanitized_confidence, ts);
     plan.comment = Allocator_TrimComment(comment);
  }
   else
   {
      plan.rejection_reason = rejection;
      plan.setup_type = (setup_type == "" ? "None" : setup_type);
      plan.price = entry_price;
      plan.sl = sl_price;
      plan.tp = tp_price;
   }

   string log_fields = StringFormat(
      "{\"signal_symbol\":\"%s\",\"exec_symbol\":\"%s\",\"strategy\":\"%s\",\"setup_type\":\"%s\",\"order_type\":%d,\"entry_price\":%.5f,\"sl\":%.5f,\"tp\":%.5f,\"volume\":%.4f,\"magic\":\"%s\",\"bias\":%.4f,\"valid\":%s,\"signal_sl_points\":%.2f,\"exec_sl_points\":%.2f,\"signal_tp_points\":%.2f,\"exec_tp_points\":%.2f,\"direction\":%d,\"positions_total\":%d,\"positions_symbol\":%d,\"pendings_symbol\":%d,\"proxy\":%s,\"proxy_rate\":%.5f",
      signal_symbol,
      exec_symbol,
      strategy,
      plan.setup_type,
      (int)plan.order_type,
      plan.price,
      plan.sl,
      plan.tp,
      plan.volume,
      IntegerToString(plan.magic),
      plan.bias,
      plan.valid ? "true" : "false",
      plan.signal_sl_points,
      exec_sl_points,
      plan.signal_tp_points,
      exec_tp_points,
      direction,
      total_positions,
      symbol_positions,
      symbol_pending,
      plan.is_proxy ? "true" : "false",
      plan.proxy_rate);

   if(rejection != "")
      log_fields += StringFormat(",\"rejection_reason\":\"%s\"", rejection);
   if(MathIsValidNumber(worst_case) && worst_case > 0.0)
      log_fields += StringFormat(",\"worst_case\":%.2f", worst_case);
   if(MathIsValidNumber(budget.next_worst_case) && budget.next_worst_case > 0.0)
      log_fields += StringFormat(",\"budget_next\":%.2f", budget.next_worst_case);
   if(MathIsValidNumber(budget.room_available) && budget.room_available > 0.0)
      log_fields += StringFormat(",\"room_available\":%.2f", budget.room_available);
   if(MathIsValidNumber(budget.open_risk) && budget.open_risk > 0.0)
      log_fields += StringFormat(",\"open_risk\":%.2f", budget.open_risk);
   if(MathIsValidNumber(budget.pending_risk) && budget.pending_risk > 0.0)
      log_fields += StringFormat(",\"pending_risk\":%.2f", budget.pending_risk);
   if(plan.comment != "")
      log_fields += StringFormat(",\"comment\":\"%s\"", plan.comment);
   log_fields += "}";

   LogDecision("Allocator", "ORDER_PLAN", log_fields);

   return plan;
}

#endif // RPEA_ALLOCATOR_MQH
