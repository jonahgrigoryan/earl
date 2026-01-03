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
   bool   approved;           // Keep for backward compatibility
   bool   gate_pass;          // Primary boolean for pass/fail
   string gating_reason;      // "pass", "insufficient_room", "lock_timeout", "calc_error"
   double room_available;     // Keep existing
   double room_today;         // Separate field
   double room_overall;       // Separate field
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

// Budget Gate Snapshot Structures
struct PositionSnapshot
{
   string symbol;
   ENUM_POSITION_TYPE type;
   double volume;
   double price_open;
   double sl;
   ulong ticket;
};

struct PendingSnapshot
{
   string symbol;
   ENUM_ORDER_TYPE type;
   double volume;
   double price;
   double sl;
   ulong ticket;
};

struct BudgetGateSnapshot
{
   datetime snapshot_time;
   double open_risk;
   double pending_risk;
   double room_today;
   double room_overall;
   PositionSnapshot position_snapshots[];
   PendingSnapshot pending_snapshots[];
   bool is_locked;
   bool open_risk_ok;
   bool pending_risk_ok;
   bool rooms_valid;
   bool state_valid;
};

// Budget Gate Lock State
static bool  g_budget_gate_locked = false;
static ulong g_budget_gate_lock_time_ms = 0;

//==============================================================================
// M4-Task03: Test Overrides for Kill-Switch Testing
//==============================================================================

#ifdef RPEA_TEST_RUNNER
bool   g_equity_override_active = false;
double g_equity_override_value  = 0.0;
bool   g_margin_override_active = false;
double g_margin_override_level  = 0.0;

void Equity_Test_SetEquityOverride(const double equity)
{
   g_equity_override_active = true;
   g_equity_override_value = equity;
}

void Equity_Test_ClearEquityOverride()
{
   g_equity_override_active = false;
   g_equity_override_value = 0.0;
}

void Equity_Test_SetMarginLevel(const double margin_level)
{
   g_margin_override_active = true;
   g_margin_override_level = margin_level;
}

void Equity_Test_ClearMarginLevel()
{
   g_margin_override_active = false;
   g_margin_override_level = 0.0;
}
#endif // RPEA_TEST_RUNNER

//==============================================================================
// M4-Task03: Floor Getters
//==============================================================================

double Equity_GetDailyFloor()
{
   return g_equity_daily_floor;
}

double Equity_GetOverallFloor()
{
   return g_equity_overall_floor;
}

//==============================================================================
// Core Functions
//==============================================================================

double Equity_FetchAccountEquity()
{
#ifdef RPEA_TEST_RUNNER
   if(g_equity_override_active)
      return g_equity_override_value;
#endif
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

// Budget Gate Helper Functions
double Equity_CalculateOpenRiskFromSnapshot(const PositionSnapshot &snapshots[], bool &calc_ok)
{
   calc_ok = true;
   double total = 0.0;
   int count = ArraySize(snapshots);
   for(int i = 0; i < count; i++)
   {
      if(snapshots[i].symbol == NULL || snapshots[i].symbol == "")
      {
         calc_ok = false;
         continue;
      }
      bool risk_ok = false;
      double risk = Equity_CalcRiskDollars(snapshots[i].symbol,
                                          snapshots[i].volume,
                                          snapshots[i].price_open,
                                          snapshots[i].sl,
                                          risk_ok);
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

double Equity_CalculatePendingRiskFromSnapshot(const PendingSnapshot &snapshots[], bool &calc_ok)
{
   calc_ok = true;
   double total = 0.0;
   int count = ArraySize(snapshots);
   for(int i = 0; i < count; i++)
   {
      if(snapshots[i].symbol == NULL || snapshots[i].symbol == "")
      {
         calc_ok = false;
         continue;
      }
      bool risk_ok = false;
      double risk = Equity_CalcRiskDollars(snapshots[i].symbol,
                                          snapshots[i].volume,
                                          snapshots[i].price,
                                          snapshots[i].sl,
                                          risk_ok);
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

// Budget Gate Snapshot Capture
BudgetGateSnapshot Equity_TakePositionSnapshot(const AppContext& ctx)
{
   BudgetGateSnapshot snapshot;
   snapshot.snapshot_time = TimeCurrent();
   snapshot.is_locked = false;
   snapshot.open_risk_ok = true;
   snapshot.pending_risk_ok = true;
   snapshot.rooms_valid = false;
   snapshot.state_valid = false;
   snapshot.open_risk = 0.0;
   snapshot.pending_risk = 0.0;
   snapshot.room_today = 0.0;
   snapshot.room_overall = 0.0;
   ArrayResize(snapshot.position_snapshots, 0);
   ArrayResize(snapshot.pending_snapshots, 0);
   
   // Ensure rooms computed
   if(g_equity_state_time != ctx.current_server_time)
      Equity_ComputeRooms(ctx);
   // Refresh state validity after potential recompute
   snapshot.state_valid = g_equity_state_valid;
   
   // Capture rooms from snapshot (frozen state)
   snapshot.room_today = g_equity_last_rooms.room_today;
   snapshot.room_overall = g_equity_last_rooms.room_overall;
   snapshot.rooms_valid = (MathIsValidNumber(snapshot.room_today) && snapshot.room_today >= 0.0 &&
                           MathIsValidNumber(snapshot.room_overall) && snapshot.room_overall >= 0.0);
   
   // Capture all open positions
   int pos_count = PositionsTotal();
   ArrayResize(snapshot.position_snapshots, pos_count);
   for(int i = 0; i < pos_count; i++)
   {
      if(PositionGetSymbol(i) == "")
         continue;
      
      PositionSnapshot ps;
      ps.symbol = PositionGetString(POSITION_SYMBOL);
      ps.ticket = PositionGetInteger(POSITION_TICKET);
      ps.type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ps.volume = PositionGetDouble(POSITION_VOLUME);
      ps.price_open = PositionGetDouble(POSITION_PRICE_OPEN);
      ps.sl = PositionGetDouble(POSITION_SL);
      
      snapshot.position_snapshots[i] = ps;
   }
   
   // Capture all pending orders
   int order_count = OrdersTotal();
   int pending_idx = 0;
   ArrayResize(snapshot.pending_snapshots, order_count);
   for(int i = 0; i < order_count; i++)
   {
      if(OrderGetTicket(i) == 0)
         continue;
      
      int type = (int)OrderGetInteger(ORDER_TYPE);
      if(!Equity_IsPendingOrderType(type))
         continue;
      
      PendingSnapshot ps;
      ps.symbol = OrderGetString(ORDER_SYMBOL);
      ps.ticket = OrderGetInteger(ORDER_TICKET);
      ps.type = (ENUM_ORDER_TYPE)type;
      ps.volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      ps.price = OrderGetDouble(ORDER_PRICE_OPEN);
      ps.sl = OrderGetDouble(ORDER_SL);
      
      snapshot.pending_snapshots[pending_idx] = ps;
      pending_idx++;
   }
   ArrayResize(snapshot.pending_snapshots, pending_idx);
   
   // Calculate risks from snapshot arrays
   bool open_ok = true;
   bool pending_ok = true;
   snapshot.open_risk = Equity_CalculateOpenRiskFromSnapshot(snapshot.position_snapshots, open_ok);
   snapshot.pending_risk = Equity_CalculatePendingRiskFromSnapshot(snapshot.pending_snapshots, pending_ok);
   snapshot.open_risk_ok = open_ok;
   snapshot.pending_risk_ok = pending_ok;
   if(!snapshot.open_risk_ok)
      snapshot.open_risk = 0.0;
   if(!snapshot.pending_risk_ok)
      snapshot.pending_risk = 0.0;
   
   return snapshot;
}

// Budget Gate Lock Management
bool Equity_AcquireBudgetGateLock(const int timeout_ms)
{
   if(g_budget_gate_locked == true)
   {
      ulong elapsed = GetTickCount64() - g_budget_gate_lock_time_ms;
      if(elapsed <= (ulong)timeout_ms)
      {
         return false; // Lock timeout
      }
      // Lock timed out, allow takeover
   }
   
   g_budget_gate_locked = true;
   g_budget_gate_lock_time_ms = GetTickCount64();
   return true;
}

void Equity_ReleaseBudgetGateLock()
{
   g_budget_gate_locked = false;
   g_budget_gate_lock_time_ms = 0;
}

EquityBudgetGateResult Equity_EvaluateBudgetGate(const AppContext& ctx, const double next_trade_worst_case)
{
   EquityBudgetGateResult result;
   result.approved = false;
   result.gate_pass = false;
   result.gating_reason = "";
   result.room_available = 0.0;
   result.room_today = 0.0;
   result.room_overall = 0.0;
   result.open_risk = 0.0;
   result.pending_risk = 0.0;
   result.next_worst_case = (MathIsValidNumber(next_trade_worst_case) && next_trade_worst_case > 0.0 ? next_trade_worst_case : 0.0);
   result.calculation_error = false;
   bool lock_acquired = false;
   
   // Resolve input parameters with fallback to defaults
   int lock_ms = BudgetGateLockMs;
   if(lock_ms <= 0)
      lock_ms = DEFAULT_BudgetGateLockMs;
   
   double headroom = RiskGateHeadroom;
   if(headroom <= 0.0 || !MathIsValidNumber(headroom))
      headroom = DEFAULT_RiskGateHeadroom;
   
   // Acquire lock
   if(!Equity_AcquireBudgetGateLock(lock_ms))
   {
      result.gate_pass = false;
      result.gating_reason = "lock_timeout";
      result.approved = false;
      string timeout_log = StringFormat("{\"lock_timeout_ms\":%d,\"gate_pass\":false,\"gating_reason\":\"lock_timeout\"}", lock_ms);
      LogDecision("Equity", "BUDGET_GATE", timeout_log);
      return result;
   }
   lock_acquired = true;
   
   // Ensure rooms computed before snapshot
   if(g_equity_state_time != ctx.current_server_time)
      Equity_ComputeRooms(ctx);
   
   // Take position snapshot
   BudgetGateSnapshot snapshot = Equity_TakePositionSnapshot(ctx);
   snapshot.is_locked = true; // Mark snapshot as locked (frozen state)
   
   // Use snapshot data (not live broker state)
   result.open_risk = snapshot.open_risk;
   result.pending_risk = snapshot.pending_risk;
   result.room_today = snapshot.room_today;
   result.room_overall = snapshot.room_overall;
   if(!MathIsValidNumber(result.open_risk) || result.open_risk < 0.0)
      result.open_risk = 0.0;
   if(!MathIsValidNumber(result.pending_risk) || result.pending_risk < 0.0)
      result.pending_risk = 0.0;
   if(!MathIsValidNumber(result.room_today) || result.room_today < 0.0)
      result.room_today = 0.0;
   if(!MathIsValidNumber(result.room_overall) || result.room_overall < 0.0)
      result.room_overall = 0.0;
   
   // Validate snapshot calculations
   bool snapshot_valid = (snapshot.open_risk_ok && snapshot.pending_risk_ok && snapshot.rooms_valid && snapshot.state_valid);
   if(!snapshot_valid)
   {
      result.calculation_error = true;
      result.gate_pass = false;
      result.approved = false;
      result.gating_reason = "calc_error";
      string error_log = StringFormat("{\"open_risk\":%.2f,\"pending_risk\":%.2f,\"next_trade\":%.2f,\"room_today\":%.2f,\"room_overall\":%.2f,\"gate_pass\":false,\"gating_reason\":\"calc_error\",\"calc_error\":true}",
                                      result.open_risk,
                                      result.pending_risk,
                                      result.next_worst_case,
                                      result.room_today,
                                      result.room_overall);
      LogDecision("Equity", "BUDGET_GATE", error_log);
      if(lock_acquired)
      {
         Equity_ReleaseBudgetGateLock();
         lock_acquired = false;
      }
      return result;
   }
   
   // Update global state for backward compatibility
   g_equity_open_risk = snapshot.open_risk;
   g_equity_pending_risk = snapshot.pending_risk;
   
   // Calculate gate threshold
   double min_room = MathMin(snapshot.room_today, snapshot.room_overall);
   if(!MathIsValidNumber(min_room) || min_room < 0.0)
   {
      min_room = 0.0;
      result.calculation_error = true;
   }
   
   double gate_threshold = headroom * min_room;
   double remaining_headroom = gate_threshold - (snapshot.open_risk + snapshot.pending_risk);
   if(!MathIsValidNumber(remaining_headroom))
      remaining_headroom = 0.0;
   result.room_available = (remaining_headroom > 0.0 ? remaining_headroom : 0.0);
   
   // Calculate total required
   double total_required = snapshot.open_risk + snapshot.pending_risk + result.next_worst_case;
   if(!MathIsValidNumber(total_required) || total_required < 0.0)
   {
      total_required = gate_threshold + 1.0;
      result.calculation_error = true;
   }
   
   // Determine gate_pass
   result.gate_pass = (!result.calculation_error && total_required <= gate_threshold + 1e-6);
   result.approved = result.gate_pass; // Backward compatibility
   
   // Set gating_reason
   if(result.calculation_error)
   {
      result.gating_reason = "calc_error";
   }
   else if(result.gate_pass)
   {
      result.gating_reason = "pass";
   }
   else
   {
      result.gating_reason = "insufficient_room";
   }
   
   // Log structured JSON with all 5 inputs + gate_pass + gating_reason
   string log_fields = StringFormat("{\"open_risk\":%.2f,\"pending_risk\":%.2f,\"next_trade\":%.2f,\"room_today\":%.2f,\"room_overall\":%.2f,\"gate_pass\":%s,\"gating_reason\":\"%s\"}",
                                    result.open_risk,
                                    result.pending_risk,
                                    result.next_worst_case,
                                    result.room_today,
                                    result.room_overall,
                                    result.gate_pass ? "true" : "false",
                                    result.gating_reason);
   LogDecision("Equity", "BUDGET_GATE", log_fields);
   
   // Release lock (finally-style guard)
   if(lock_acquired)
   {
      Equity_ReleaseBudgetGateLock();
      lock_acquired = false;
   }
   
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

//==============================================================================
// M4-Task02: Micro-Mode, Hard-Stop, and Giveback Protection
//==============================================================================

// Forward declarations for inputs (defined in RPEA.mq5)
#ifdef RPEA_TEST_RUNNER
#ifndef TargetProfitPct
#define TargetProfitPct DEFAULT_TargetProfitPct
#endif
#ifndef MicroRiskPct
#define MicroRiskPct DEFAULT_MicroRiskPct
#endif
#ifndef MicroTimeStopMin
#define MicroTimeStopMin DEFAULT_MicroTimeStopMin
#endif
#ifndef GivebackCapDayPct
#define GivebackCapDayPct DEFAULT_GivebackCapDayPct
#endif
#ifndef MaxSlippagePoints
#define MaxSlippagePoints 10
#endif
#ifndef MinTradeDaysRequired
#define MinTradeDaysRequired 3
#endif
#endif

// Global context forward declaration
#ifndef GLOBAL_CTX_FORWARD_DECLARED
#define GLOBAL_CTX_FORWARD_DECLARED
#endif

// Forward declaration for persistence flush
#ifndef PERSISTENCE_FORWARD_DECLARED
#define PERSISTENCE_FORWARD_DECLARED
void Persistence_Flush();
#endif

//------------------------------------------------------------------------------
// Micro-Mode Functions
//------------------------------------------------------------------------------

// Check if Micro-Mode is currently active
bool Equity_IsMicroModeActive()
{
   ChallengeState st = State_Get();
   return st.micro_mode;
}

// Check and activate Micro-Mode if conditions are met
// Activates when: profit target achieved AND gDaysTraded < MinTradeDaysRequired
void Equity_CheckMicroMode(const AppContext &ctx)
{
   ChallengeState st = State_Get();
   
   // Already in Micro-Mode or permanently disabled
   if(st.micro_mode || st.disabled_permanent)
      return;
   
   // Condition 1: Profit target achieved
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double baseline = ctx.initial_baseline;
   if(!MathIsValidNumber(baseline) || baseline <= 0.0)
      baseline = st.initial_baseline;
   if(!MathIsValidNumber(baseline) || baseline <= 0.0)
      return;
   
   double target_equity = baseline * (1.0 + TargetProfitPct / 100.0);
   
   if(current_equity < target_equity)
      return;
   
   // Condition 2: gDaysTraded still below requirement
   if(st.gDaysTraded >= MinTradeDaysRequired)
      return;
   
   // Activate Micro-Mode
   st.micro_mode = true;
   st.micro_mode_activated_at = TimeCurrent();
   State_Set(st);
   
   LogAuditRow("MICRO_MODE_ACTIVATED", "EQUITY", 1,
               StringFormat("Equity %.2f hit target %.2f, days %d/%d", 
                           current_equity, target_equity, st.gDaysTraded, MinTradeDaysRequired),
               StringFormat("{\"equity\":%.2f,\"target\":%.2f,\"days_traded\":%d,\"micro_risk_pct\":%.2f}",
                           current_equity, target_equity, st.gDaysTraded, MicroRiskPct));
}

// Check if Micro-Mode time stop has been exceeded for a position
bool Equity_MicroTimeStopExceeded(const datetime entry_time)
{
   if(!Equity_IsMicroModeActive())
      return false;
   
   int elapsed_min = (int)((TimeCurrent() - entry_time) / 60);
   return elapsed_min >= MicroTimeStopMin;
}

//------------------------------------------------------------------------------
// Hard-Stop Functions
//------------------------------------------------------------------------------

// Check if trading is hard-stopped
bool Equity_IsHardStopped()
{
   ChallengeState st = State_Get();
   return st.disabled_permanent;
}

// Close all open positions (used by hard-stop and giveback)
void Equity_CloseAllPositions(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);
         
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_DEAL;
         request.position = ticket;
         request.symbol = symbol;
         request.volume = volume;
         request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) 
                        ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.price = (request.type == ORDER_TYPE_BUY) 
                         ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                         : SymbolInfoDouble(symbol, SYMBOL_BID);
         request.deviation = MaxSlippagePoints;
         request.comment = reason;
         
         if(!OrderSend(request, result))
         {
            PrintFormat("[HardStop] Failed to close position %d: %d", ticket, result.retcode);
         }
      }
   }
}

// Cancel all pending orders (used by hard-stop and giveback)
void Equity_CancelAllPendingOrders(const string reason)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_REMOVE;
         request.order = ticket;
         request.comment = reason;
         
         if(!OrderSend(request, result))
         {
            PrintFormat("[HardStop] Failed to cancel order %d: %d", ticket, result.retcode);
         }
      }
   }
}

// Trigger hard-stop with reason
void Equity_TriggerHardStop(const string reason)
{
   ChallengeState st = State_Get();
   
   if(st.disabled_permanent)
      return;  // Already stopped
   
   st.disabled_permanent = true;
   st.trading_enabled = false;
   st.hard_stop_reason = reason;
   st.hard_stop_time = TimeCurrent();
   st.hard_stop_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   State_Set(st);
   
   // Note: g_ctx.permanently_disabled is set by RPEA.mq5 after checking Equity_IsHardStopped()
   
   LogAuditRow("HARD_STOP_ACTIVATED", "EQUITY", 0, reason,
               StringFormat("{\"equity\":%.2f,\"reason\":\"%s\",\"days_traded\":%d}",
                           st.hard_stop_equity, reason, st.gDaysTraded));
   
   // Close all positions and cancel all orders
   Equity_CloseAllPositions("HARD_STOP");
   Equity_CancelAllPendingOrders("HARD_STOP");
   
   // Persist immediately
   Persistence_Flush();
}

// Check for hard-stop conditions
void Equity_CheckHardStopConditions(const AppContext &ctx)
{
   ChallengeState st = State_Get();
   
   if(st.disabled_permanent)
      return;
   
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double baseline = ctx.initial_baseline;
   if(!MathIsValidNumber(baseline) || baseline <= 0.0)
      baseline = st.initial_baseline;
   if(!MathIsValidNumber(baseline) || baseline <= 0.0)
      return;
   
   // Check 1: Overall drawdown floor breach
   double overall_floor = baseline * (1.0 - OverallLossCapPct / 100.0);
   if(current_equity <= overall_floor)
   {
      Equity_TriggerHardStop(StringFormat("Overall floor breach: %.2f <= %.2f", 
                                          current_equity, overall_floor));
      return;
   }
   
   // Check 2: Challenge complete (success hard-stop)
   double target_equity = baseline * (1.0 + TargetProfitPct / 100.0);
   if(current_equity >= target_equity && st.gDaysTraded >= MinTradeDaysRequired)
   {
      LogAuditRow("CHALLENGE_COMPLETE", "EQUITY", 1,
                  StringFormat("Target %.2f achieved with %d days", target_equity, st.gDaysTraded),
                  StringFormat("{\"equity\":%.2f,\"target\":%.2f,\"days_traded\":%d}",
                              current_equity, target_equity, st.gDaysTraded));
      Equity_TriggerHardStop("Challenge completed successfully");
      return;
   }
   
   // Check 3: Target hit but MinTradeDays not met - log warning
   if(current_equity >= target_equity && st.gDaysTraded < MinTradeDaysRequired && !st.micro_mode)
   {
      LogAuditRow("TARGET_PENDING_DAYS", "EQUITY", 1,
                  StringFormat("Target hit, need %d more days", MinTradeDaysRequired - st.gDaysTraded),
                  StringFormat("{\"equity\":%.2f,\"days_traded\":%d,\"required\":%d}",
                              current_equity, st.gDaysTraded, MinTradeDaysRequired));
   }
}

//------------------------------------------------------------------------------
// Giveback Protection Functions (Micro-Mode Only)
//------------------------------------------------------------------------------

// Update peak equity tracking
void Equity_UpdatePeakTracking()
{
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   ChallengeState st = State_Get();
   
   // Update intraday peak
   if(current_equity > st.day_peak_equity)
   {
      st.day_peak_equity = current_equity;
   }
   
   // Update overall peak
   if(current_equity > st.overall_peak_equity)
   {
      st.overall_peak_equity = current_equity;
   }
   
   State_Set(st);
}

// Check and trigger giveback protection (Micro-Mode only)
bool Equity_CheckGivebackProtection()
{
   ChallengeState st = State_Get();
   
   // Only active in Micro-Mode
   if(!st.micro_mode)
      return false;
   
   if(st.day_peak_equity <= 0.0)
      return false;
   
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown_from_peak = (st.day_peak_equity - current_equity) / st.day_peak_equity;
   
   if(drawdown_from_peak >= GivebackCapDayPct / 100.0)
   {
      if(st.trading_enabled)
      {
         st.trading_enabled = false;
         State_Set(st);
         
         LogAuditRow("GIVEBACK_PROTECTION", "EQUITY", 0,
                     StringFormat("DD %.2f%% from peak %.2f", drawdown_from_peak * 100, st.day_peak_equity),
                     StringFormat("{\"equity\":%.2f,\"peak\":%.2f,\"dd_pct\":%.2f}",
                                 current_equity, st.day_peak_equity, drawdown_from_peak * 100));
         
         Equity_CloseAllPositions("GIVEBACK_PROTECTION");
         Equity_CancelAllPendingOrders("GIVEBACK_PROTECTION");
      }
      return true;
   }
   
   return !st.trading_enabled;
}

// Read-only gate for order engine
bool Equity_IsGivebackProtectionActive()
{
   ChallengeState st = State_Get();
   return st.micro_mode && !st.trading_enabled;
}

// Reset daily tracking on server-day rollover
void Equity_OnServerDayRollover()
{
   ChallengeState st = State_Get();
   
   // M4-Task03: Reset daily kill-switch flags
   st.daily_floor_breached = false;
   st.daily_floor_breach_time = (datetime)0;
   
   st.day_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!st.disabled_permanent)
      st.trading_enabled = TradingEnabledDefault;
   State_Set(st);
   
   string note = StringFormat("{\"trading_enabled\":%s,\"daily_floor_breached\":false}",
                              st.trading_enabled ? "true" : "false");
   LogDecision("Equity", "DAILY_FLAGS_RESET", note);
}

//==============================================================================
// M4-Task03: Kill-Switch Floor Detection and Execution
//==============================================================================

// Forward declaration for margin protection input
#ifdef RPEA_TEST_RUNNER
#ifndef MarginLevelCritical
#define MarginLevelCritical DEFAULT_MarginLevelCritical
#endif
#ifndef EnableMarginProtection
#define EnableMarginProtection DEFAULT_EnableMarginProtection
#endif
#ifndef TradingEnabledDefault
#define TradingEnabledDefault DEFAULT_TradingEnabledDefault
#endif
#endif

// Log floor updates when they change significantly
void Equity_LogFloorUpdate(const double prev_daily, const double prev_overall)
{
   if(MathAbs(g_equity_daily_floor - prev_daily) <= 0.01 &&
      MathAbs(g_equity_overall_floor - prev_overall) <= 0.01)
      return;

   string note = StringFormat(
      "{\"daily_floor\":%.2f,\"overall_floor\":%.2f,\"baseline_today\":%.2f,\"initial_baseline\":%.2f}",
      g_equity_daily_floor,
      g_equity_overall_floor,
      g_equity_baseline_today,
      g_equity_initial_baseline
   );
   LogDecision("Equity", "FLOOR_UPDATE", note);
}

// Forward declarations for protective exits (implemented in order_engine.mqh)
int OrderEngine_CloseAllPositionsProtective(const string reason);
int OrderEngine_CancelAllPendingsProtective(const string reason);
void Queue_ClearAll(const string reason);

// Execute protective exits on kill-switch
void Equity_ExecuteProtectiveExits(const string reason)
{
   OrderEngine_CloseAllPositionsProtective(reason);
   OrderEngine_CancelAllPendingsProtective(reason);
   Queue_ClearAll(reason);
}

// Check and execute kill-switch on floor breach
void Equity_CheckAndExecuteKillswitch(const AppContext &ctx)
{
   ChallengeState st = State_Get();
   if(st.disabled_permanent)
      return;

   double prev_daily = g_equity_daily_floor;
   double prev_overall = g_equity_overall_floor;

   Equity_ComputeRooms(ctx);
   Equity_LogFloorUpdate(prev_daily, prev_overall);

   EquitySessionState session = Equity_BuildSessionState(g_equity_last_rooms);
   Equity_LogSessionStateTransitions(session);

   // Overall floor takes precedence
   if(session.overall_floor_breached && !st.disabled_permanent)
   {
      double breach_margin = g_equity_current_equity - g_equity_overall_floor;
      st.disabled_permanent = true;
      st.trading_enabled = false;
      st.hard_stop_reason = "overall_floor_breach";
      st.hard_stop_time = TimeCurrent();
      st.hard_stop_equity = g_equity_current_equity;
      State_Set(st);

      string note = StringFormat(
         "{\"floor_type\":\"overall\",\"floor_value\":%.2f,\"equity_at_breach\":%.2f,\"breach_margin\":%.2f,\"initial_baseline\":%.2f}",
         g_equity_overall_floor,
         g_equity_current_equity,
         breach_margin,
         g_equity_initial_baseline
      );
      LogDecision("Equity", "KILLSWITCH_OVERALL", note);

      Equity_ExecuteProtectiveExits("killswitch_overall");
      Persistence_Flush();
      return;
   }

   // Daily floor breach (once per server day)
   if(session.daily_floor_breached && !st.daily_floor_breached)
   {
      double breach_margin = g_equity_current_equity - g_equity_daily_floor;
      st.daily_floor_breached = true;
      st.daily_floor_breach_time = TimeCurrent();
      st.trading_enabled = false;
      State_Set(st);

      string note = StringFormat(
         "{\"floor_type\":\"daily\",\"floor_value\":%.2f,\"equity_at_breach\":%.2f,\"breach_margin\":%.2f,\"baseline_today\":%.2f}",
         g_equity_daily_floor,
         g_equity_current_equity,
         breach_margin,
         g_equity_baseline_today
      );
      LogDecision("Equity", "KILLSWITCH_DAILY", note);

      Equity_ExecuteProtectiveExits("killswitch_daily");
      Persistence_Flush();
   }
}

// Check margin level and trigger protection if needed
bool Equity_CheckMarginProtection()
{
   if(!EnableMarginProtection)
      return false;
   
   double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
#ifdef RPEA_TEST_RUNNER
   if(g_margin_override_active)
      margin_level = g_margin_override_level;
#endif
   
   // Margin level of 0 means no positions (nothing to protect)
   if(margin_level == 0.0)
      return false;
   
   if(margin_level < MarginLevelCritical)
   {
      double equity = Equity_FetchAccountEquity();
      double margin = AccountInfoDouble(ACCOUNT_MARGIN);
      
      string note = StringFormat(
         "{\"margin_level\":%.2f,\"threshold\":%.2f,\"equity\":%.2f,\"margin\":%.2f}",
         margin_level,
         MarginLevelCritical,
         equity,
         margin
      );
      LogDecision("Equity", "MARGIN_PROTECTION", note);
      
      // Close positions to free margin
      Equity_ExecuteProtectiveExits("margin_protection");
      
      return true;
   }
   
   return false;
}

// Check if daily kill-switch has been triggered
bool Equity_IsDailyKillswitchActive()
{
   ChallengeState st = State_Get();
   return st.daily_floor_breached && !st.disabled_permanent;
}

#endif // EQUITY_GUARDIAN_MQH
