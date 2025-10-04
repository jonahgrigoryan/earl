#ifndef EQUITY_GUARDIAN_MQH
#define EQUITY_GUARDIAN_MQH
// equity_guardian.mqh - Equity rooms, caps, and session governance
// References: finalspec.md (Equity & Risk Caps)

#include <RPEA/logging.mqh>

struct AppContext;

struct EquityRooms
{
   double room_today;
   double room_overall;
};

struct EquityBudgetGateResult
{
   bool   approved;
   double room_available;
   double open_risk;
   double pending_risk;
   double next_worst_case;
   bool   calculation_error;
};

struct EquitySessionState
{
   bool   daily_floor_breached;
   bool   overall_floor_breached;
   bool   small_room_pause;
   bool   one_and_done_met;
   bool   ny_gate_allowed;
   double day_gain;
   double day_loss;
   double one_and_done_threshold;
   double ny_gate_threshold;
};

static double        g_equity_current_equity  = 0.0;
static double        g_equity_baseline_today  = 0.0;
static double        g_equity_initial_baseline = 0.0;
static double        g_equity_daily_floor     = 0.0;
static double        g_equity_overall_floor   = 0.0;
static EquityRooms   g_equity_last_rooms      = {0.0, 0.0};
static bool          g_equity_state_valid     = false;
static datetime      g_equity_state_time      = 0;
static EquitySessionState g_equity_session_state = {false,false,false,false,true,0.0,0.0,0.0,0.0};
static bool          g_equity_session_initialized = false;
static double        g_equity_open_risk       = 0.0;
static double        g_equity_pending_risk    = 0.0;

double Equity_FetchAccountEquity()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!MathIsValidNumber(equity) || equity <= 0.0)
      equity = AccountInfoDouble(ACCOUNT_BALANCE);
   if(!MathIsValidNumber(equity))
      equity = 0.0;
   return equity;
}

bool Equity_FetchSymbolContract(const string symbol, double &point, double &tick_size, double &tick_value)
{
   if(symbol == NULL || symbol == "")
      return false;
   if(!SymbolInfoDouble(symbol, SYMBOL_POINT, point) || point <= 0.0)
      return false;
   if(!SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE, tick_size) || tick_size <= 0.0)
      return false;
   if(!SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE, tick_value) || tick_value <= 0.0)
      return false;
   return true;
}

double Equity_CalcRiskDollars(const string symbol,
                              const double volume,
                              const double price_entry,
                              const double stop_price,
                              bool &ok)
{
   ok = false;
   if(symbol == NULL || symbol == "" || volume <= 0.0)
   {
      ok = true;
      return 0.0;
   }
   if(!MathIsValidNumber(price_entry) || !MathIsValidNumber(stop_price) || stop_price <= 0.0)
      return 0.0;

   double point = 0.0;
   double tick_size = 0.0;
   double tick_value = 0.0;
   if(!Equity_FetchSymbolContract(symbol, point, tick_size, tick_value))
      return 0.0;

   double distance = MathAbs(price_entry - stop_price);
   if(distance <= 0.0)
      return 0.0;

   double tick_ratio = tick_size / point;
   if(tick_ratio <= 0.0)
      return 0.0;

   double value_per_point = tick_value / tick_ratio;
   if(value_per_point <= 0.0)
      return 0.0;

   double points = distance / point;
   double risk = volume * value_per_point * points;
   if(!MathIsValidNumber(risk))
      return 0.0;

   ok = true;
   if(risk < 0.0)
      risk = -risk;
   return risk;
}

double Equity_SumOpenRisk(bool &calc_ok)
{
   calc_ok = true;
   double total = 0.0;
   int count = PositionsTotal();
   for(int i=0; i<count; i++)
   {
      if(PositionGetSymbol(i) == "")
      {
         calc_ok = false;
         continue;
      }
      string symbol = PositionGetString(POSITION_SYMBOL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);

      bool risk_ok = false;
      double risk = Equity_CalcRiskDollars(symbol, volume, price_open, sl, risk_ok);
      if(!risk_ok)
      {
         calc_ok = false;
         continue;
      }
      total += risk;
   }
   if(!MathIsValidNumber(total) || total < 0.0)
      total = 0.0;
   return total;
}

bool Equity_IsPendingOrderType(const int type)
{
   switch(type)
   {
      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_SELL_LIMIT:
      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_SELL_STOP:
      case ORDER_TYPE_BUY_STOP_LIMIT:
      case ORDER_TYPE_SELL_STOP_LIMIT:
         return true;
   }
   return false;
}

double Equity_SumPendingRisk(bool &calc_ok)
{
   calc_ok = true;
   double total = 0.0;
   int count = OrdersTotal();
   for(int i=0; i<count; i++)
   {
      if(OrderGetTicket(i) == 0)
      {
         calc_ok = false;
         continue;
      }
      int type = (int)OrderGetInteger(ORDER_TYPE);
      if(!Equity_IsPendingOrderType(type))
         continue;

      string symbol = OrderGetString(ORDER_SYMBOL);
      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      double price_open = OrderGetDouble(ORDER_PRICE_OPEN);
      double sl = OrderGetDouble(ORDER_SL);

      bool risk_ok = false;
      double risk = Equity_CalcRiskDollars(symbol, volume, price_open, sl, risk_ok);
      if(!risk_ok)
      {
         calc_ok = false;
         continue;
      }
      total += risk;
   }
   if(!MathIsValidNumber(total) || total < 0.0)
      total = 0.0;
   return total;
}

int Equity_CountOpenPositionsTotal(bool &calc_ok)
{
   calc_ok = true;
   int total = 0;
   int count = PositionsTotal();
   for(int i=0; i<count; i++)
   {
      if(PositionGetSymbol(i) == "")
      {
         calc_ok = false;
         continue;
      }
      total++;
   }
   return total;
}

int Equity_CountOpenPositionsBySymbol(const string symbol, bool &calc_ok)
{
   calc_ok = true;
   if(symbol == NULL || symbol == "")
   {
      calc_ok = false;
      return 0;
   }

   int total = 0;
   int count = PositionsTotal();
   for(int i=0; i<count; i++)
   {
      if(PositionGetSymbol(i) == "")
      {
         calc_ok = false;
         continue;
      }
      string sym = PositionGetString(POSITION_SYMBOL);
      if(sym == symbol)
         total++;
   }
   return total;
}

int Equity_CountPendingsBySymbol(const string symbol, bool &calc_ok)
{
   calc_ok = true;
   if(symbol == NULL || symbol == "")
   {
      calc_ok = false;
      return 0;
   }

   int total = 0;
   int count = OrdersTotal();
   for(int i=0; i<count; i++)
   {
      if(OrderGetTicket(i) == 0)
      {
         calc_ok = false;
         continue;
      }
      int type = (int)OrderGetInteger(ORDER_TYPE);
      if(!Equity_IsPendingOrderType(type))
         continue;

      string sym = OrderGetString(ORDER_SYMBOL);
      if(sym == symbol)
         total++;
   }
   return total;
}

EquitySessionState Equity_BuildSessionState(const EquityRooms &rooms)
{
   EquitySessionState state;
   state.daily_floor_breached = false;
   state.overall_floor_breached = false;
   state.small_room_pause = false;
   state.one_and_done_met = false;
   state.ny_gate_allowed = true;
   state.day_gain = 0.0;
   state.day_loss = 0.0;
   state.one_and_done_threshold = 0.0;
   state.ny_gate_threshold = 0.0;

   bool equity_ok = MathIsValidNumber(g_equity_current_equity) && g_equity_current_equity > 0.0;
   bool daily_ok = MathIsValidNumber(g_equity_baseline_today) && g_equity_baseline_today > 0.0;
   bool overall_ok = MathIsValidNumber(g_equity_initial_baseline) && g_equity_initial_baseline > 0.0;

   double daily_floor = g_equity_daily_floor;
   double overall_floor = g_equity_overall_floor;

   if(equity_ok && daily_ok)
   {
      state.day_gain = g_equity_current_equity - g_equity_baseline_today;
      state.day_loss = g_equity_baseline_today - g_equity_current_equity;
      if(state.day_loss < 0.0)
         state.day_loss = 0.0;

      double risk_pct = (RiskPct > 0.0 ? RiskPct : 0.0);
      state.one_and_done_threshold = g_equity_baseline_today * (risk_pct / 100.0) * OneAndDoneR;
      if(state.one_and_done_threshold > 0.0 && state.day_gain >= state.one_and_done_threshold - 1e-6)
         state.one_and_done_met = true;

      state.ny_gate_threshold = g_equity_baseline_today * (DailyLossCapPct / 100.0) * NYGatePctOfDailyCap;
      if(state.ny_gate_threshold > 0.0)
         state.ny_gate_allowed = (state.day_loss <= state.ny_gate_threshold + 1e-6);
      else
         state.ny_gate_allowed = (state.day_loss <= 1e-6);
   }
   else
   {
      state.ny_gate_allowed = false;
   }

   if(!equity_ok || !daily_ok)
      state.daily_floor_breached = true;
   else
      state.daily_floor_breached = (g_equity_current_equity <= daily_floor + 1e-6);

   if(!equity_ok || !overall_ok)
      state.overall_floor_breached = true;
   else
      state.overall_floor_breached = (g_equity_current_equity <= overall_floor + 1e-6);

   if(MinRiskDollar > 0.0)
   {
      if(!MathIsValidNumber(rooms.room_today) || rooms.room_today < MinRiskDollar)
         state.small_room_pause = true;
   }

   return state;
}

void Equity_LogSessionStateTransitions(const EquitySessionState &state)
{
   if(!g_equity_session_initialized || state.daily_floor_breached != g_equity_session_state.daily_floor_breached)
   {
      if(state.daily_floor_breached)
      {
         string note = StringFormat("{\"reason\":\"floor\",\"value\":\"daily\",\"equity\":%.2f}", g_equity_current_equity);
         LogDecision("Equity", "SESSION_GOV", note);
      }
   }
   if(!g_equity_session_initialized || state.overall_floor_breached != g_equity_session_state.overall_floor_breached)
   {
      if(state.overall_floor_breached)
      {
         string note = StringFormat("{\"reason\":\"floor\",\"value\":\"overall\",\"equity\":%.2f}", g_equity_current_equity);
         LogDecision("Equity", "SESSION_GOV", note);
      }
   }
   if(!g_equity_session_initialized || state.one_and_done_met != g_equity_session_state.one_and_done_met)
   {
      if(state.one_and_done_met)
      {
         string note = StringFormat("{\"reason\":\"one_and_done\",\"value\":%.2f,\"threshold\":%.2f}",
                                    state.day_gain,
                                    state.one_and_done_threshold);
         LogDecision("Equity", "SESSION_GOV", note);
      }
   }
   if(!g_equity_session_initialized || state.ny_gate_allowed != g_equity_session_state.ny_gate_allowed)
   {
      if(!state.ny_gate_allowed)
      {
         string note = StringFormat("{\"reason\":\"ny_gate\",\"value\":%.2f,\"threshold\":%.2f}",
                                    state.day_loss,
                                    state.ny_gate_threshold);
         LogDecision("Equity", "SESSION_GOV", note);
      }
   }
   if(!g_equity_session_initialized || state.small_room_pause != g_equity_session_state.small_room_pause)
   {
      if(state.small_room_pause)
      {
         string note = StringFormat("{\"reason\":\"small_room\",\"value\":%.2f}", g_equity_last_rooms.room_today);
         LogDecision("Equity", "SESSION_GOV", note);
      }
   }

   g_equity_session_state = state;
   g_equity_session_initialized = true;
}

EquityRooms Equity_ComputeRooms(const AppContext& ctx)
{
   EquityRooms rooms;
   rooms.room_today = 0.0;
   rooms.room_overall = 0.0;

   double current_equity = Equity_FetchAccountEquity();
   double baseline_today = ctx.baseline_today;
   if(!MathIsValidNumber(baseline_today) || baseline_today <= 0.0)
      baseline_today = current_equity;

   double initial_baseline = ctx.initial_baseline;
   if(!MathIsValidNumber(initial_baseline) || initial_baseline <= 0.0)
      initial_baseline = baseline_today;

   double today_cap = (DailyLossCapPct / 100.0) * baseline_today;
   if(!MathIsValidNumber(today_cap) || today_cap < 0.0)
      today_cap = 0.0;

   double overall_cap = (OverallLossCapPct / 100.0) * initial_baseline;
   if(!MathIsValidNumber(overall_cap) || overall_cap < 0.0)
      overall_cap = 0.0;

   double room_today = today_cap - (baseline_today - current_equity);
   double room_overall = overall_cap - (initial_baseline - current_equity);

   if(!MathIsValidNumber(room_today) || room_today < 0.0)
      room_today = 0.0;
   if(!MathIsValidNumber(room_overall) || room_overall < 0.0)
      room_overall = 0.0;

   rooms.room_today = room_today;
   rooms.room_overall = room_overall;

   g_equity_current_equity = current_equity;
   g_equity_baseline_today = baseline_today;
   g_equity_initial_baseline = initial_baseline;
   g_equity_last_rooms = rooms;
   g_equity_daily_floor = baseline_today - today_cap;
   if(g_equity_daily_floor < 0.0)
      g_equity_daily_floor = 0.0;
   g_equity_overall_floor = initial_baseline - overall_cap;
   if(g_equity_overall_floor < 0.0)
      g_equity_overall_floor = 0.0;

   g_equity_state_valid = (MathIsValidNumber(current_equity) && current_equity > 0.0 &&
                           MathIsValidNumber(baseline_today) && baseline_today > 0.0 &&
                           MathIsValidNumber(initial_baseline) && initial_baseline > 0.0);
   g_equity_state_time = ctx.current_server_time;

   string log_fields = StringFormat("{\"room_today\":%.2f,\"room_overall\":%.2f,\"current_equity\":%.2f,\"baseline_today\":%.2f,\"initial_baseline\":%.2f}",
                                    room_today,
                                    room_overall,
                                    current_equity,
                                    baseline_today,
                                    initial_baseline);
   LogDecision("Equity", "ROOMS", log_fields);

   return rooms;
}

bool Equity_CheckFloors(const AppContext& ctx)
{
   if(g_equity_state_time != ctx.current_server_time)
      Equity_ComputeRooms(ctx);

   if(!g_equity_state_valid)
      return false;

   EquitySessionState state = Equity_BuildSessionState(g_equity_last_rooms);
   Equity_LogSessionStateTransitions(state);

   bool ok = true;
   if(state.daily_floor_breached || state.overall_floor_breached || state.small_room_pause)
      ok = false;
   return ok;
}

EquityBudgetGateResult Equity_EvaluateBudgetGate(const AppContext& ctx, const double next_trade_worst_case)
{
   if(g_equity_state_time != ctx.current_server_time)
      Equity_ComputeRooms(ctx);

   EquityBudgetGateResult result;
   result.approved = false;
   result.room_available = 0.0;
   result.open_risk = 0.0;
   result.pending_risk = 0.0;
   result.next_worst_case = (MathIsValidNumber(next_trade_worst_case) && next_trade_worst_case > 0.0 ? next_trade_worst_case : 0.0);
   result.calculation_error = false;

   bool open_ok = true;
   bool pending_ok = true;
   double open_risk = Equity_SumOpenRisk(open_ok);
   double pending_risk = Equity_SumPendingRisk(pending_ok);

   g_equity_open_risk = open_risk;
   g_equity_pending_risk = pending_risk;

   if(!open_ok || !pending_ok || !g_equity_state_valid)
      result.calculation_error = true;

   result.open_risk = open_risk;
   result.pending_risk = pending_risk;

   double min_room = MathMin(g_equity_last_rooms.room_today, g_equity_last_rooms.room_overall);
   if(!MathIsValidNumber(min_room) || min_room < 0.0)
   {
      min_room = 0.0;
      result.calculation_error = true;
   }
   result.room_available = 0.9 * min_room;
   if(result.room_available < 0.0)
      result.room_available = 0.0;

   double total_required = result.open_risk + result.pending_risk + result.next_worst_case;
   if(!MathIsValidNumber(total_required) || total_required < 0.0)
   {
      total_required = result.room_available + 1.0;
      result.calculation_error = true;
   }

   result.approved = (!result.calculation_error && total_required <= result.room_available + 1e-6);

   string extra = result.calculation_error ? ",\"calc_error\":true" : "";
   string log_fields = StringFormat("{\"open_risk\":%.2f,\"pending_risk\":%.2f,\"next_worst_case\":%.2f,\"room_available\":%.2f,\"approved\":%s%s}",
                                    result.open_risk,
                                    result.pending_risk,
                                    result.next_worst_case,
                                    result.room_available,
                                    result.approved ? "true" : "false",
                                    extra);
   LogDecision("Equity", "BUDGET_GATE", log_fields);

   return result;
}

bool Equity_RoomAllowsNextTrade(const AppContext& ctx, const double next_trade_worst_case)
{
   EquityBudgetGateResult res = Equity_EvaluateBudgetGate(ctx, next_trade_worst_case);
   return res.approved;
}

bool Equity_RoomAllowsNextTrade(const AppContext& ctx)
{
   return Equity_RoomAllowsNextTrade(ctx, 0.0);
}

bool Equity_CheckPositionCaps(const string symbol,
                              int &out_total_positions,
                              int &out_symbol_positions,
                              int &out_symbol_pending)
{
   bool totals_ok = true;
   bool symbol_ok = true;
   bool pending_ok = true;

   out_total_positions = Equity_CountOpenPositionsTotal(totals_ok);
   out_symbol_positions = Equity_CountOpenPositionsBySymbol(symbol, symbol_ok);
   out_symbol_pending = Equity_CountPendingsBySymbol(symbol, pending_ok);

   bool allowed = true;

   if(MaxOpenPositionsTotal > 0 && out_total_positions >= MaxOpenPositionsTotal)
   {
      string note = StringFormat("{\"type\":\"total\",\"current\":%d,\"limit\":%d}", out_total_positions, MaxOpenPositionsTotal);
      LogDecision("Equity", "CAP_VIOLATION", note);
      allowed = false;
   }
   if(MaxOpenPerSymbol > 0 && out_symbol_positions >= MaxOpenPerSymbol)
   {
      string note = StringFormat("{\"type\":\"symbol\",\"current\":%d,\"limit\":%d}", out_symbol_positions, MaxOpenPerSymbol);
      LogDecision("Equity", "CAP_VIOLATION", note);
      allowed = false;
   }
   if(MaxPendingsPerSymbol > 0 && out_symbol_pending >= MaxPendingsPerSymbol)
   {
      string note = StringFormat("{\"type\":\"pending\",\"current\":%d,\"limit\":%d}", out_symbol_pending, MaxPendingsPerSymbol);
      LogDecision("Equity", "CAP_VIOLATION", note);
      allowed = false;
   }

   if(!totals_ok)
   {
      string note = StringFormat("{\"type\":\"total\",\"current\":-1,\"limit\":%d}", MaxOpenPositionsTotal);
      LogDecision("Equity", "CAP_VIOLATION", note);
      allowed = false;
   }
   if(!symbol_ok)
   {
      string note = StringFormat("{\"type\":\"symbol\",\"current\":-1,\"limit\":%d}", MaxOpenPerSymbol);
      LogDecision("Equity", "CAP_VIOLATION", note);
      allowed = false;
   }
   if(!pending_ok)
   {
      string note = StringFormat("{\"type\":\"pending\",\"current\":-1,\"limit\":%d}", MaxPendingsPerSymbol);
      LogDecision("Equity", "CAP_VIOLATION", note);
      allowed = false;
   }

   return allowed;
}

EquitySessionState Equity_GetSessionGovernanceState(const AppContext& ctx)
{
   if(g_equity_state_time != ctx.current_server_time)
      Equity_CheckFloors(ctx);
   return g_equity_session_state;
}

bool Equity_IsOneAndDoneAchieved(const AppContext& ctx)
{
   EquitySessionState state = Equity_GetSessionGovernanceState(ctx);
   return state.one_and_done_met;
}

bool Equity_IsNYGateAllowed(const AppContext& ctx)
{
   EquitySessionState state = Equity_GetSessionGovernanceState(ctx);
   return state.ny_gate_allowed;
}

bool Equity_IsSmallRoomPause(const AppContext& ctx)
{
   EquitySessionState state = Equity_GetSessionGovernanceState(ctx);
   return state.small_room_pause;
}

#endif // EQUITY_GUARDIAN_MQH

