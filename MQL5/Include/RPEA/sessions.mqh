#ifndef SESSIONS_MQH
#define SESSIONS_MQH
// sessions.mqh - Session predicates (M1 stubs)
// References: finalspec.md (Session Governance, Session window predicate)

#include <RPEA/logging.mqh>
#include <RPEA/equity_guardian.mqh>

struct AppContext;

// Note: Input parameters are declared in RPEA.mq5 as input variables
// and are automatically available to all included files

// Session identifiers (string constants for logging)
#define SESSION_LABEL_LONDON "LO"
#define SESSION_LABEL_NEWYORK "NY"

// Session enumeration (MQL5 2024 compliant enum)
enum SessionKind
{
   SESSION_KIND_LONDON = 0,
   SESSION_KIND_NEWYORK = 1
};

#define SESSION_KIND_COUNT 2

// Per-session window state structure (MQL5 2024 compliant struct)
struct SessionWindowState
{
   datetime session_start;      // Session start time
   datetime or_start;           // Opening Range start time
   datetime or_end;             // Opening Range end time
   double   session_open_price; // Session opening price
   double   or_high;            // Opening Range high
   double   or_low;             // Opening Range low
   bool     or_complete;       // Opening Range completion flag
   bool     session_active;    // Session active flag
   bool     session_enabled;   // Governance flag (true when session allowed)
   bool     warned_no_bars;    // Warning flag for missing bars
   bool     has_or_values;     // Flag indicating valid OR values
   bool     blocked_logged;    // Governance log guard for current anchor
   datetime last_update;       // Last update timestamp
   datetime governance_anchor; // Anchor used to scope governance logging per day
};

// Per-symbol session state container (MQL5 2024 compliant struct)
struct SessionSymbolState
{
   string symbol;                              // Symbol name
   SessionWindowState windows[SESSION_KIND_COUNT]; // Array of session windows
};

// Snapshot structure for downstream modules (MQL5 2024 compliant)
struct SessionORSnapshot
{
   string   symbol;              // Symbol name
   string   session;             // Session label ("LO" or "NY")
   double   session_open_price;  // Session opening price
   double   or_high;             // Opening Range high
   double   or_low;              // Opening Range low
   datetime session_start;       // Session start time
   datetime or_start;            // Opening Range start time
   datetime or_end;              // Opening Range end time
   bool     or_complete;         // Opening Range completion flag
   bool     session_active;      // Session active flag
   bool     session_enabled;     // Governance flag (true when session allowed)
   bool     has_or_values;       // Valid OR values flag
};

// Global storage array (MQL5 2024 compliant global declaration)
SessionSymbolState g_session_slots[];

// Helper: extract hour component without relying on TimeHour()
int Sessions_ServerHour(const datetime value)
{
   MqlDateTime tm;
   TimeToStruct(value, tm);
   return tm.hour;
}

string Sessions_Label(const SessionKind kind)
{
   if(kind == SESSION_KIND_NEWYORK)
      return SESSION_LABEL_NEWYORK;
   return SESSION_LABEL_LONDON;
}

void Sessions_ResetWindow(SessionWindowState &win)
{
   win.session_start = 0;
   win.or_start = 0;
   win.or_end = 0;
   win.session_open_price = 0.0;
   win.or_high = 0.0;
   win.or_low = 0.0;
   win.or_complete = false;
   win.session_active = false;
   win.session_enabled = true;
   win.warned_no_bars = false;
   win.has_or_values = false;
   win.blocked_logged = false;
   win.last_update = 0;
   win.governance_anchor = 0;
}

// Governance hooks backed by Equity Guardian state.
bool Sessions_IsOneAndDoneAllowed(const AppContext &ctx, const string symbol, const SessionKind kind)
{
   if(symbol == "")
   {
      // symbol unused guard
   }
   if((int)kind < 0)
   {
      // enum unused guard
   }
   if(ctx.symbols_count < 0)
   {
      // ctx unused guard
   }
   return !Equity_IsOneAndDoneAchieved(ctx);
}

bool Sessions_IsNYGateAllowed(const AppContext &ctx, const string symbol)
{
   if(symbol == "")
   {
      // symbol unused guard
   }
   if(ctx.symbols_count < 0)
   {
      // ctx unused guard
   }
   return Equity_IsNYGateAllowed(ctx);
}


void Sessions_EnsureSlots(const AppContext &ctx)
{
   int required = ctx.symbols_count;
   if(required <= 0)
   {
      ArrayResize(g_session_slots, 0);
      return;
   }

   int current = ArraySize(g_session_slots);
   if(current != required)
   {
      int previous = current;
      ArrayResize(g_session_slots, required);
      for(int i=0;i<required;i++)
      {
         if(i >= previous)
         {
            Sessions_ResetWindow(g_session_slots[i].windows[SESSION_KIND_LONDON]);
            Sessions_ResetWindow(g_session_slots[i].windows[SESSION_KIND_NEWYORK]);
         }
         g_session_slots[i].symbol = ctx.symbols[i];
      }
   }

   for(int j=0;j<required;j++)
   {
      if(g_session_slots[j].symbol != ctx.symbols[j])
      {
         g_session_slots[j].symbol = ctx.symbols[j];
         Sessions_ResetWindow(g_session_slots[j].windows[SESSION_KIND_LONDON]);
         Sessions_ResetWindow(g_session_slots[j].windows[SESSION_KIND_NEWYORK]);
      }
   }
}

int Sessions_FindSlot(const string symbol)
{
   int total = ArraySize(g_session_slots);
   for(int i=0;i<total;i++)
   {
      if(g_session_slots[i].symbol == symbol)
         return i;
   }
   return -1;
}

datetime Sessions_AnchorForHour(const datetime now, const int hour)
{
   MqlDateTime tm;
   TimeToStruct(now, tm);
   tm.hour = hour;
   tm.min = 0;
   tm.sec = 0;
   return StructToTime(tm);
}

int Sessions_ORMinutesValue()
{
   if(ORMinutes <= 0)
      return 1;
   return ORMinutes;
}

void Sessions_BeginSession(const string symbol, SessionWindowState &win, const SessionKind kind, const datetime start_time)
{
   Sessions_ResetWindow(win);
   win.session_start = start_time;
   win.or_start = start_time;
   win.or_end = start_time + Sessions_ORMinutesValue()*60;
   win.session_active = true;
   win.session_open_price = 0.0;

   MqlRates first_bar[];
   ArraySetAsSeries(first_bar, false);
   int copied = CopyRates(symbol, PERIOD_M5, start_time, 1, first_bar);
   if(copied > 0)
   {
      win.session_open_price = first_bar[0].open;
   }
   else
   {
      double price = 0.0;
      if(SymbolInfoDouble(symbol, SYMBOL_BID, price))
         win.session_open_price = price;
      else if(SymbolInfoDouble(symbol, SYMBOL_LAST, price))
         win.session_open_price = price;
   }

   string note = StringFormat("{\"symbol\":\"%s\",\"session\":\"%s\",\"session_open\":%.5f}",
                              symbol, Sessions_Label(kind), win.session_open_price);
   LogDecision("Sessions", "SESSION_START", note);
}

void Sessions_LogWarnOnce(SessionWindowState &win, const string symbol, const SessionKind kind, const string reason)
{
   if(win.warned_no_bars)
      return;
   string note = StringFormat("{\"symbol\":\"%s\",\"session\":\"%s\",\"reason\":\"%s\"}",
                              symbol, Sessions_Label(kind), reason);
   LogDecision("Sessions", "OR_WARN", note);
   win.warned_no_bars = true;
}

void Sessions_UpdateOR(const string symbol, SessionWindowState &win, const SessionKind kind, const datetime now)
{
   if(now < win.or_start)
      return;

   datetime window_end = (now < win.or_end ? now : win.or_end);
   if(window_end <= win.or_start)
      return;

   int bars_to_fetch = (int)MathCeil((double)Sessions_ORMinutesValue()/5.0) + 2;
   if(bars_to_fetch < 1)
      bars_to_fetch = 1;

   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int copied = CopyRates(symbol, PERIOD_M5, win.or_start, bars_to_fetch, rates);
   if(copied <= 0)
   {
      Sessions_LogWarnOnce(win, symbol, kind, "no_bars");
      return;
   }

   bool updated=false;
   for(int i=0;i<copied;i++)
   {
      datetime bar_time = rates[i].time;
      if(bar_time < win.or_start)
         continue;
      if(bar_time >= win.or_end)
         break;

      if(!win.has_or_values)
      {
         win.or_high = rates[i].high;
         win.or_low  = rates[i].low;
         win.has_or_values = true;
      }
      else
      {
         win.or_high = MathMax(win.or_high, rates[i].high);
         win.or_low  = MathMin(win.or_low, rates[i].low);
      }
      updated = true;
   }

   if(updated && !win.or_complete)
   {
      string tick_note = StringFormat("{\"symbol\":\"%s\",\"session\":\"%s\",\"or_h\":%.5f,\"or_l\":%.5f}",
                                      symbol, Sessions_Label(kind), win.or_high, win.or_low);
      LogDecision("Sessions", "OR_TICK", tick_note);
   }
   else if(!win.has_or_values)
   {
      Sessions_LogWarnOnce(win, symbol, kind, "insufficient_data");
   }

   if(!win.or_complete && now >= win.or_end)
   {
      win.or_complete = true;
      string done_note = StringFormat("{\"symbol\":\"%s\",\"session\":\"%s\",\"or_high\":%.5f,\"or_low\":%.5f}",
                                     symbol, Sessions_Label(kind), win.or_high, win.or_low);
      LogDecision("Sessions", "OR_COMPLETE", done_note);
   }
}

void Sessions_UpdateGovernanceState(const AppContext &ctx, const string symbol, SessionWindowState &win, const SessionKind kind, const datetime session_anchor)
{
   if(win.governance_anchor != session_anchor)
   {
      win.governance_anchor = session_anchor;
      win.blocked_logged = false;
   }

   string block_reason = "";

   if(!Sessions_IsOneAndDoneAllowed(ctx, symbol, kind))
      block_reason = "one_and_done";

   if(block_reason == "" && kind == SESSION_KIND_NEWYORK)
   {
      if(!Sessions_IsNYGateAllowed(ctx, symbol))
         block_reason = "ny_gate";
      else if(UseLondonOnly)
         block_reason = "use_london_only";
   }

   bool enabled = (block_reason == "");
   win.session_enabled = enabled;
   if(!enabled)
   {
      win.session_active = false;
      if(!win.blocked_logged)
      {
         string note = StringFormat("{\"symbol\":\"%s\",\"session\":\"%s\",\"reason\":\"%s\"}",
                                    symbol, Sessions_Label(kind), block_reason);
         LogDecision("Sessions", "SESSION_BLOCKED", note);
         win.blocked_logged = true;
      }
   }
}

void Sessions_UpdateSession(const AppContext &ctx, const string symbol, SessionWindowState &win, const SessionKind kind, const int start_hour)
{
   datetime now = ctx.current_server_time;
   if(win.last_update == now)
      return;

   datetime session_start = Sessions_AnchorForHour(now, start_hour);
   Sessions_UpdateGovernanceState(ctx, symbol, win, kind, session_start);

   if(!win.session_enabled)
   {
      win.session_active = false;
      win.last_update = now;
      return;
   }

   datetime cutoff = Sessions_AnchorForHour(now, CutoffHour);
   if(cutoff <= session_start)
      cutoff += 24*60*60;

   bool in_session = (now >= session_start && now < cutoff);

   if(in_session)
   {
      if(!win.session_active || win.session_start != session_start)
      {
         Sessions_BeginSession(symbol, win, kind, session_start);
      }
      Sessions_UpdateOR(symbol, win, kind, now);
   }
   else
   {
      win.session_active = false;
   }

   win.last_update = now;
}

void Sessions_UpdateSymbol(const AppContext &ctx, const string symbol)
{
   if(symbol == "")
      return;
   Sessions_EnsureSlots(ctx);
   int idx = Sessions_FindSlot(symbol);
   if(idx < 0)
      return;

   SessionWindowState &lo_win = g_session_slots[idx].windows[SESSION_KIND_LONDON];
   SessionWindowState &ny_win = g_session_slots[idx].windows[SESSION_KIND_NEWYORK];

   Sessions_UpdateSession(ctx, symbol, lo_win, SESSION_KIND_LONDON, StartHourLO);
   Sessions_UpdateSession(ctx, symbol, ny_win, SESSION_KIND_NEWYORK, StartHourNY);
}

int Sessions_SessionFromLabel(const string label)
{
   string up = label;
   StringToUpper(up);
   if(up == SESSION_LABEL_LONDON)
      return (int)SESSION_KIND_LONDON;
   if(up == SESSION_LABEL_NEWYORK)
      return (int)SESSION_KIND_NEWYORK;
   return -1;
}

// Predicate: currently inside London session window
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
   Sessions_UpdateSymbol(ctx, symbol);
   int idx = Sessions_FindSlot(symbol);
   if(idx < 0)
      return false;

   datetime now = ctx.current_server_time;
   SessionWindowState lo = g_session_slots[idx].windows[SESSION_KIND_LONDON];
   if(lo.session_active && !lo.or_complete && now >= lo.or_start && now < lo.or_end)
      return true;

   if(!UseLondonOnly)
   {
      SessionWindowState ny = g_session_slots[idx].windows[SESSION_KIND_NEWYORK];
      if(ny.session_active && !ny.or_complete && now >= ny.or_start && now < ny.or_end)
         return true;
   }
   return false;
}

bool Sessions_CutoffReached(const AppContext& ctx, const string symbol)
{
   if(symbol == "")
   {
      // symbol unused guard (no-op)
   }
   datetime now = ctx.current_server_time;
   datetime cutoff = Sessions_AnchorForHour(now, CutoffHour);
   if(cutoff <= Sessions_AnchorForHour(now, StartHourLO))
      cutoff += 24*60*60;
   return (now >= cutoff);
}

// Snapshot getters for downstream modules
bool Sessions_GetORSnapshot(const AppContext& ctx, const string symbol, const string session_label, SessionORSnapshot &out_snapshot)
{
   Sessions_UpdateSymbol(ctx, symbol);
   int kind_idx = Sessions_SessionFromLabel(session_label);
   if(kind_idx < 0)
      return false;

   int slot = Sessions_FindSlot(symbol);
   if(slot < 0)
      return false;

   SessionWindowState win = g_session_slots[slot].windows[kind_idx];
   out_snapshot.symbol = symbol;
   out_snapshot.session = Sessions_Label((SessionKind)kind_idx);
   out_snapshot.session_open_price = win.session_open_price;
   out_snapshot.or_high = win.or_high;
   out_snapshot.or_low = win.or_low;
   out_snapshot.session_start = win.session_start;
   out_snapshot.or_start = win.or_start;
   out_snapshot.or_end = win.or_end;
   out_snapshot.or_complete = win.or_complete;
   out_snapshot.session_active = win.session_active;
   out_snapshot.session_enabled = win.session_enabled;
   out_snapshot.has_or_values = win.has_or_values;
   return true;
}

bool Sessions_GetLondonORSnapshot(const AppContext& ctx, const string symbol, SessionORSnapshot &out_snapshot)
{
   return Sessions_GetORSnapshot(ctx, symbol, SESSION_LABEL_LONDON, out_snapshot);
}

// InSession signature per spec; interval-based
bool InSession(const datetime t0, const int window_minutes)
{
   datetime now = TimeCurrent();
   return (now >= t0 && now <= (t0 + window_minutes*60));
}

#endif // SESSIONS_MQH

