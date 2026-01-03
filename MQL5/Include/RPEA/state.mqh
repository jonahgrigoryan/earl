#ifndef STATE_MQH
#define STATE_MQH
// state.mqh - Challenge state & helpers (M1 stubs)
// References: finalspec.md (Trading-day counting & persistence)

// ChallengeState persisted fields
struct ChallengeState
{
   double   initial_baseline;
   double   baseline_today;
   int      gDaysTraded;
   int      last_counted_server_date; // yyyymmdd
   bool     trading_enabled;
   bool     disabled_permanent;
   // M1 additions
   bool     micro_mode;
   double   day_peak_equity;
   // Anchors to prevent re-anchoring on restart
   datetime server_midnight_ts;
   double   baseline_today_e0; // equity at server midnight
   double   baseline_today_b0; // balance at server midnight
   
   // M4-Task02: Micro-Mode tracking
   datetime micro_mode_activated_at;       // When Micro-Mode was activated
   int      last_micro_entry_server_date;  // yyyymmdd of last micro entry day
   
   // M4-Task02: Hard-Stop metadata
   string   hard_stop_reason;              // Reason for hard-stop
   datetime hard_stop_time;                // When hard-stop was triggered
   double   hard_stop_equity;              // Final equity at hard-stop
   
   // M4-Task02: Overall peak tracking
   double   overall_peak_equity;           // Overall high water mark
   
   // M4-Task03: Kill-Switch state
   bool     daily_floor_breached;          // True if daily floor hit this server day
   datetime daily_floor_breach_time;       // When daily floor was breached
};

// Global singleton for simplicity in M1
// Order: initial_baseline, baseline_today, gDaysTraded, last_counted_server_date, trading_enabled,
//        disabled_permanent, micro_mode, day_peak_equity, server_midnight_ts, baseline_today_e0, baseline_today_b0,
//        micro_mode_activated_at, last_micro_entry_server_date, hard_stop_reason, hard_stop_time, hard_stop_equity, 
//        overall_peak_equity, daily_floor_breached, daily_floor_breach_time
static ChallengeState g_state = {0.0,0.0,0,0,true,false,false,0.0,(datetime)0,0.0,0.0,(datetime)0,0,"",0,0.0,0.0,false,(datetime)0};

// Accessors
ChallengeState State_Get() { return g_state; }
void State_Set(const ChallengeState &s) { g_state = s; }

// Reset baseline at new server day
void State_ResetDailyBaseline()
{
   // TODO[M1]: Load equity/balance as per spec; placeholder uses current equity/balance at rollover detect time
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_state.baseline_today_e0 = eq;
   g_state.baseline_today_b0 = bal;
   // Spec: baseline_today = max(equity_midnight, balance_midnight)
   g_state.baseline_today = (eq > bal ? eq : bal);
   if(eq > g_state.day_peak_equity) g_state.day_peak_equity = eq;
   if(g_state.disabled_permanent)
      g_state.trading_enabled = false;
   else
      g_state.trading_enabled = TradingEnabledDefault; // re-enable for the new day unless permanently disabled
}

// Overload with explicit state reference (per M1 API surface)
void State_ResetDailyBaseline(ChallengeState &state)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   state.baseline_today_e0 = eq;
   state.baseline_today_b0 = bal;
   // Spec: baseline_today = max(equity_midnight, balance_midnight)
   state.baseline_today = (eq > bal ? eq : bal);
   if(eq > state.day_peak_equity) state.day_peak_equity = eq;
   if(state.disabled_permanent)
      state.trading_enabled = false;
   else
      state.trading_enabled = TradingEnabledDefault;
   g_state = state;
}

// Count a trading day once per server date
void State_MarkTradeDayOnce()
{
   // TODO[M4]: Trigger only on first DEAL_ENTRY_IN of the server-day
   datetime now = TimeCurrent();
   MqlDateTime tm; TimeToStruct(now, tm);
   int yyyymmdd = tm.year*10000 + tm.mon*100 + tm.day;
   if(yyyymmdd != g_state.last_counted_server_date)
   {
      g_state.gDaysTraded++;
      g_state.last_counted_server_date = yyyymmdd;
   }
}

// Overload with explicit state reference
void State_MarkTradeDayOnce(ChallengeState &state)
{
   datetime now = TimeCurrent();
   MqlDateTime tm; TimeToStruct(now, tm);
   int yyyymmdd = tm.year*10000 + tm.mon*100 + tm.day;
   if(yyyymmdd != state.last_counted_server_date)
   {
      state.gDaysTraded++;
      state.last_counted_server_date = yyyymmdd;
      g_state = state;
   }
}

// Disable for the day (re-enabled on server-day rollover)
void State_DisableForDay()
{
   g_state.trading_enabled = false;
}

// Overload with explicit state reference
void State_DisableForDay(ChallengeState &state)
{
   state.trading_enabled = false;
   g_state = state;
}

// Disable permanently for the challenge lifecycle
void State_DisablePermanent()
{
   g_state.disabled_permanent = true;
   g_state.trading_enabled = false;
}

// Overload with explicit state reference
void State_DisablePermanent(ChallengeState &state)
{
   state.disabled_permanent = true;
   state.trading_enabled = false;
   g_state = state;
}

//==============================================================================
// M4-Task02: Server-Day Tracking + Micro-Mode Helpers
//==============================================================================

// Forward declaration for timeutils (included in main EA)
#ifndef TIMEUTILS_FORWARD_DECLARED
#define TIMEUTILS_FORWARD_DECLARED
int TimeUtils_ServerDateInt(const datetime server_time);
string TimeUtils_ServerDateString(const datetime server_time);
string TimeUtils_CestDateString(const datetime server_time);
#endif

// Forward declaration for logging (included in main EA)
#ifndef LOGGING_FORWARD_DECLARED
#define LOGGING_FORWARD_DECLARED
void LogAuditRow(const string event_type, const string symbol, const int ok, const string description, const string extra_json);
#endif

// Forward declaration for MinTradeDaysRequired input
#ifdef RPEA_TEST_RUNNER
#ifndef MinTradeDaysRequired
#define MinTradeDaysRequired 3
#endif
#endif

// Mark a trade day with explicit server timestamp (called from OnTradeTransaction on DEAL_ENTRY_IN)
void State_MarkTradeDayServer(const datetime server_time)
{
   int server_date = TimeUtils_ServerDateInt(server_time);
   string server_date_str = TimeUtils_ServerDateString(server_time);
   string cest_date = TimeUtils_CestDateString(server_time);
   
   ChallengeState st = State_Get();
   
   // Check if already counted today (idempotent)
   if(st.last_counted_server_date == server_date)
      return;
   
   // New trade day
   st.gDaysTraded++;
   st.last_counted_server_date = server_date;
   State_Set(st);
   
   LogAuditRow("TRADE_DAY_MARKED", "STATE", 1,
               StringFormat("Day %d of %d", st.gDaysTraded, MinTradeDaysRequired),
               StringFormat("{\"server_date\":\"%s\",\"cest_date\":\"%s\",\"days_traded\":%d}",
                           server_date_str, cest_date, st.gDaysTraded));
}

// Get current days traded count
int State_GetDaysTraded()
{
   ChallengeState st = State_Get();
   return st.gDaysTraded;
}

// Check if MinTradeDays requirement is met
bool State_MinTradeDaysMet()
{
   return State_GetDaysTraded() >= MinTradeDaysRequired;
}

// Check if a Micro-Mode entry is allowed for the current server day
bool State_MicroEntryAllowed(const datetime server_time)
{
   int server_date = TimeUtils_ServerDateInt(server_time);
   ChallengeState st = State_Get();
   return st.last_micro_entry_server_date != server_date;
}

// Mark that a Micro-Mode entry occurred on this server day
void State_MarkMicroEntryServer(const datetime server_time)
{
   ChallengeState st = State_Get();
   st.last_micro_entry_server_date = TimeUtils_ServerDateInt(server_time);
   State_Set(st);
}

#endif // STATE_MQH
