#pragma once
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
};

// Global singleton for simplicity in M1
static ChallengeState g_state = {0.0,0.0,0,0,true,false,false,0.0};

// Accessors
ChallengeState State_Get() { return g_state; }
void State_Set(const ChallengeState &s) { g_state = s; }

// Reset baseline at new server day
void State_ResetDailyBaseline()
{
   // TODO[M1]: Load equity/balance as per spec; placeholder uses current equity
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_state.baseline_today = eq;
   if(eq > g_state.day_peak_equity) g_state.day_peak_equity = eq;
}

// Overload with explicit state reference (per M1 API surface)
void State_ResetDailyBaseline(ChallengeState &state)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   state.baseline_today = eq;
   if(eq > state.day_peak_equity) state.day_peak_equity = eq;
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

// TODO[M4]: enforce min trade days and micro-mode flags
