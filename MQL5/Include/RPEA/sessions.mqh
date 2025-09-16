#ifndef SESSIONS_MQH
#define SESSIONS_MQH
// sessions.mqh - Session predicates (M1 stubs)
// References: finalspec.md (Session Governance, Session window predicate)

struct AppContext;

// Helper: extract hour component without relying on TimeHour()
int Sessions_ServerHour(const datetime value)
{
   MqlDateTime tm;
   TimeToStruct(value, tm);
   return tm.hour;
}

// Placeholder predicates using server time and input parameters
bool Sessions_InLondon(const AppContext& ctx, const string symbol)
{
   int hr = Sessions_ServerHour(ctx.current_server_time);
   return (hr >= StartHourLO && hr < CutoffHour);
}

bool Sessions_InNewYork(const AppContext& ctx, const string symbol)
{
   if(UseLondonOnly) return false;
   int hr = Sessions_ServerHour(ctx.current_server_time);
   return (hr >= StartHourNY && hr < CutoffHour);
}

bool Sessions_InORWindow(const AppContext& ctx, const string symbol)
{
   MqlDateTime tm; TimeToStruct(ctx.current_server_time, tm);
   tm.min = 0; tm.sec = 0;
   // Anchor OR to London start for simplicity in M1
   tm.hour = StartHourLO;
   datetime t0 = StructToTime(tm);
   return InSession(t0, ORMinutes);
}

bool Sessions_CutoffReached(const AppContext& ctx, const string symbol)
{
   int hr = Sessions_ServerHour(ctx.current_server_time);
   return (hr >= CutoffHour);
}

// InSession signature per spec; interval-based
bool InSession(const datetime t0, const int window_minutes)
{
   datetime now = TimeCurrent();
   return (now >= t0 && now <= (t0 + window_minutes*60));
}

#endif // SESSIONS_MQH
