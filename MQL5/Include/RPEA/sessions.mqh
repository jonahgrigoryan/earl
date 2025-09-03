#pragma once
// sessions.mqh - Session predicates (M1 stubs)
// References: finalspec.md (Session Governance, Session window predicate)

struct AppContext;

// Placeholder predicates using server time and input parameters
static bool Sessions_InLondon(const AppContext& ctx, const string symbol)
{
   int hr = TimeHour(ctx.current_server_time);
   return (hr >= StartHourLO && hr < CutoffHour);
}

static bool Sessions_InNewYork(const AppContext& ctx, const string symbol)
{
   if(UseLondonOnly) return false;
   int hr = TimeHour(ctx.current_server_time);
   return (hr >= StartHourNY && hr < CutoffHour);
}

static bool Sessions_InORWindow(const AppContext& ctx, const string symbol)
{
   MqlDateTime tm; TimeToStruct(ctx.current_server_time, tm);
   tm.min = 0; tm.sec = 0;
   // Anchor OR to London start for simplicity in M1
   tm.hour = StartHourLO;
   datetime t0 = StructToTime(tm);
   return InSession(t0, ORMinutes);
}

static bool Sessions_CutoffReached(const AppContext& ctx, const string symbol)
{
   int hr = TimeHour(ctx.current_server_time);
   return (hr >= CutoffHour);
}

// InSession signature per spec; interval-based
bool InSession(const datetime t0, const int ORMinutes)
{
   datetime now = TimeCurrent();
   return (now >= t0 && now <= (t0 + ORMinutes*60));
}
