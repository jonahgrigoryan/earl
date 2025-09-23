#ifndef RPEA_ALLOCATOR_MQH
#define RPEA_ALLOCATOR_MQH
// allocator.mqh - Risk allocator implementation (M2)
// References: finalspec.md (Allocator Enhancements)

#include <RPEA/logging.mqh>
#include <RPEA/risk.mqh>
#include <RPEA/equity_guardian.mqh>

struct AppContext;

struct OrderPlan
{
   bool             valid;
   string           symbol;
   ENUM_ORDER_TYPE  order_type;
   double           volume;
   double           price;
   double           sl;
   double           tp;
   string           comment;
   long             magic;
};

extern BWISC_Context g_last_bwisc_context;

OrderPlan Allocator_BuildOrderPlan(const AppContext& ctx,
                                   const string strategy,
                                   const string symbol,
                                   const int slPoints,
                                   const int tpPoints,
                                   const double confidence)
{
   OrderPlan plan;
   plan.valid   = false;
   plan.symbol  = symbol;
   plan.order_type = ORDER_TYPE_BUY;
   plan.volume  = 0.0;
   plan.price   = 0.0;
   plan.sl      = 0.0;
   plan.tp      = 0.0;
   plan.comment = "";
   plan.magic   = 0;

   string setup_type = "Unknown";
   string rejection_reason = "";
   double entry_price = 0.0;
   double stop_price = 0.0;
   double tp_price = 0.0;
   double bias_value = 0.0;
   double point = 0.0;
   int digits = (int)Digits();
   int direction = 0;
   double computed_volume = 0.0;

   EquityBudgetGateResult budget;
   budget.approved = false;
   budget.room_available = 0.0;
   budget.open_risk = 0.0;
   budget.pending_risk = 0.0;
   budget.next_worst_case = 0.0;
   budget.calculation_error = true;

   do
   {
      if(strategy != "BWISC")
      {
         rejection_reason = "unsupported_strategy";
         break;
      }

      if(symbol == NULL || symbol == "")
      {
         rejection_reason = "invalid_symbol";
         break;
      }

      if(slPoints <= 0 || tpPoints <= 0)
      {
         rejection_reason = "invalid_sl_tp";
         break;
      }

      if(!SymbolInfoDouble(symbol, SYMBOL_POINT, point) || point <= 0.0)
      {
         rejection_reason = "symbol_point_error";
         break;
      }

      long digits_long = 0;
      if(SymbolInfoInteger(symbol, SYMBOL_DIGITS, digits_long))
         digits = (int)digits_long;

      double ratio = ((double)slPoints > 0.0 ? ((double)tpPoints) / (double)slPoints : 0.0);
      double diff_bc = MathAbs(ratio - RtargetBC);
      double diff_msc = MathAbs(ratio - RtargetMSC);
      double tolerance = 0.35;

      if(diff_bc <= diff_msc && diff_bc <= tolerance)
         setup_type = "BC";
      else if(diff_msc < diff_bc && diff_msc <= tolerance)
         setup_type = "MSC";
      else
         setup_type = (diff_bc <= diff_msc ? "BC" : "MSC");

      direction = g_last_bwisc_context.direction;
      if(direction == 0)
         direction = (setup_type == "MSC" ? -1 : 1);

      entry_price = g_last_bwisc_context.entry_price;
      if(!MathIsValidNumber(entry_price) || entry_price <= 0.0)
      {
         rejection_reason = "missing_entry_price";
         break;
      }

      double sl_distance = (double)slPoints * point;
      double tp_distance = (double)tpPoints * point;

      if(direction > 0)
      {
         stop_price = entry_price - sl_distance;
         tp_price = entry_price + tp_distance;
      }
      else
      {
         stop_price = entry_price + sl_distance;
         tp_price = entry_price - tp_distance;
      }

      if(stop_price <= 0.0 || tp_price <= 0.0)
      {
         rejection_reason = "invalid_price_levels";
         break;
      }

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(!MathIsValidNumber(equity) || equity <= 0.0)
         equity = AccountInfoDouble(ACCOUNT_BALANCE);

      double worst_case = g_last_bwisc_context.worst_case_risk;
      if(!MathIsValidNumber(worst_case) || worst_case <= 0.0)
         worst_case = equity * (RiskPct / 100.0);

      budget = Equity_EvaluateBudgetGate(ctx, worst_case);
      if(!budget.approved)
      {
         rejection_reason = "budget_gate";
         break;
      }

      computed_volume = Risk_SizingByATRDistanceForSymbol(symbol, entry_price, stop_price,
                                                          equity, RiskPct, budget.room_available);
      if(computed_volume <= 0.0)
      {
         rejection_reason = "sizing_failed";
         break;
      }

      int total_positions = 0;
      int symbol_positions = 0;
      int symbol_pending = 0;
      if(!Equity_CheckPositionCaps(symbol, total_positions, symbol_positions, symbol_pending))
      {
         rejection_reason = "position_caps";
         break;
      }

      int symbol_index = -1;
      for(int i=0; i<ctx.symbols_count; i++)
      {
         if(ctx.symbols[i] == symbol)
         {
            symbol_index = i;
            break;
         }
      }

      long magic = MagicBase;
      if(symbol_index >= 0)
         magic += (long)(symbol_index + 1);

      ENUM_ORDER_TYPE order_type = ORDER_TYPE_BUY;
      if(setup_type == "BC")
         order_type = (direction > 0 ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP);
      else
         order_type = (direction > 0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT);

      bias_value = confidence;
      if(direction < 0)
         bias_value = -bias_value;

      string ts = TimeToString(TimeCurrent(), TIME_SECONDS);
      plan.comment = StringFormat("BWISC-%s|bias=%.2f|conf=%.2f|ts=%s",
                                  setup_type,
                                  bias_value,
                                  confidence,
                                  ts);

      plan.valid = true;
      plan.symbol = symbol;
      plan.order_type = order_type;
      plan.volume = computed_volume;
      plan.price = NormalizeDouble(entry_price, digits);
      plan.sl = NormalizeDouble(stop_price, digits);
      plan.tp = NormalizeDouble(tp_price, digits);
      plan.magic = magic;
   } while(false);

   string log_reason = (rejection_reason == "" ? "none" : rejection_reason);
   string log_fields = StringFormat(
      "{\"symbol\":\"%s\",\"strategy\":\"%s\",\"setup_type\":\"%s\",\"entry_price\":%.5f,\"sl\":%.5f,\"tp\":%.5f,\"volume\":%.4f,\"order_type\":%d,\"magic\":%I64d,\"confidence\":%.2f,\"bias\":%.2f,\"room_available\":%.2f,\"valid\":%s,\"rejection_reason\":\"%s\"}",
      symbol,
      strategy,
      setup_type,
      plan.price,
      plan.sl,
      plan.tp,
      plan.volume,
      (int)plan.order_type,
      plan.magic,
      confidence,
      bias_value,
      budget.room_available,
      plan.valid ? "true" : "false",
      log_reason);
   LogDecision("Allocator", "ORDER_PLAN", log_fields);

   if(!plan.valid)
   {
      plan.comment = "";
      plan.magic = 0;
      plan.order_type = ORDER_TYPE_BUY;
      plan.volume = 0.0;
      plan.price = 0.0;
      plan.sl = 0.0;
      plan.tp = 0.0;
   }

   return plan;
}
#endif // RPEA_ALLOCATOR_MQH
