#ifndef SESSIONS_MQH
#define SESSIONS_MQH
// sessions.mqh - Session predicates and OR tracking (M2 implementation)
// References: finalspec.md (Session Governance), m2.md (§5.2)

struct AppContext;

// Session identifiers (labels reused in logs and downstream modules)
#define SESSION_LABEL_LONDON "LO"
#define SESSION_LABEL_NEWYORK "NY"

enum SessionKind
{
   SESSION_KIND_LONDON = 0,
   SESSION_KIND_NEWYORK = 1
};

#define SESSION_KIND_COUNT 2

// Per-session OR tracking state for a symbol
struct SessionWindowState
{
   datetime session_start;
   datetime or_start;
   datetime or_end;
   double   session_open_price;
   double   or_high;
   double   or_low;
   bool     or_complete;
   bool     session_active;
   bool     warned_no_bars;
   bool     has_or_values;
   datetime last_update;
};

// Aggregate state per symbol
struct SessionSymbolState
{
   string symbol;
   SessionWindowState windows[SESSION_KIND_COUNT];
};

// Snapshot exposed to downstream modules (BWISC)
struct SessionORSnapshot
{
   string   symbol;
   string   session;
   double   session_open_price;
   double   or_high;
   double   or_low;
   datetime session_start;
   datetime or_start;
   datetime or_end;
   bool     or_complete;
   bool     session_active;
   bool     has_or_values;
};

SessionSymbolState g_session_slots[];

// Helper: extract hour component without relying on TimeHour()
int Sessions_ServerHour(const datetime value)
{
   MqlDateTime tm;
   TimeToStruct(value, tm);
   return tm.hour;
}

static string Sessions_Label(const SessionKind kind)
{
   if(kind == SESSION_KIND_NEWYORK)
      return SESSION_LABEL_NEWYORK;
   return SESSION_LABEL_LONDON;
}

static void Sessions_ResetWindow(SessionWindowState &win)
{
   win.session_start = 0;
   win.or_start = 0;
   win.or_end = 0;
   win.session_open_price = 0.0;
   win.or_high = 0.0;
   win.or_low = 0.0;
   win.or_complete = false;
   win.session_active = false;
   win.warned_no_bars = false;
   win.has_or_values = false;
   win.last_update = 0;
}

static void Sessions_EnsureSlots(const AppContext &ctx)
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

static int Sessions_FindSlot(const string symbol)
{
   int total = ArraySize(g_session_slots);
   for(int i=0;i<total;i++)
   {
      if(g_session_slots[i].symbol == symbol)
         return i;
   }
   return -1;
}

static datetime Sessions_AnchorForHour(const datetime now, const int hour)
{
   MqlDateTime tm;
   TimeToStruct(now, tm);
   tm.hour = hour;
   tm.min = 0;
   tm.sec = 0;
   return StructToTime(tm);
}

static int Sessions_ORMinutesValue()
{
   if(ORMinutes <= 0)
      return 1;
   return ORMinutes;
}

static void Sessions_BeginSession(const string symbol, SessionWindowState &win, const SessionKind kind, const datetime start_time)
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

static void Sessions_LogWarnOnce(SessionWindowState &win, const string symbol, const SessionKind kind, const string reason)
{
   if(win.warned_no_bars)
      return;
   string note = StringFormat("{\"symbol\":\"%s\",\"session\":\"%s\",\"reason\":\"%s\"}",
                              symbol, Sessions_Label(kind), reason);
   LogDecision("Sessions", "OR_WARN", note);
   win.warned_no_bars = true;
}

static void Sessions_UpdateOR(const string symbol, SessionWindowState &win, const SessionKind kind, const datetime now)
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

static void Sessions_UpdateSession(const AppContext &ctx, const string symbol, const int slot_idx, const SessionKind kind, const int start_hour)
{
   SessionWindowState &win = g_session_slots[slot_idx].windows[kind];
   datetime now = ctx.current_server_time;
   if(win.last_update == now)
      return;

   datetime session_start = Sessions_AnchorForHour(now, start_hour);
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

static void Sessions_UpdateSymbol(const AppContext &ctx, const string symbol)
{
   if(symbol == "")
      return;
   Sessions_EnsureSlots(ctx);
   int idx = Sessions_FindSlot(symbol);
   if(idx < 0)
      return;

   Sessions_UpdateSession(ctx, symbol, idx, SESSION_KIND_LONDON, StartHourLO);
   if(!UseLondonOnly)
      Sessions_UpdateSession(ctx, symbol, idx, SESSION_KIND_NEWYORK, StartHourNY);
   else
      g_session_slots[idx].windows[SESSION_KIND_NEWYORK].session_active = false;
}

static int Sessions_SessionFromLabel(const string label)
{
   string up = StringToUpper(label);
   if(up == SESSION_LABEL_LONDON)
      return (int)SESSION_KIND_LONDON;
   if(up == SESSION_LABEL_NEWYORK)
      return (int)SESSION_KIND_NEWYORK;
   return -1;
}

// Predicate: currently inside London session window
bool Sessions_InLondon(const AppContext& ctx, const string symbol)
{
   Sessions_UpdateSymbol(ctx, symbol);
   int idx = Sessions_FindSlot(symbol);
   if(idx < 0)
      return false;
   return g_session_slots[idx].windows[SESSION_KIND_LONDON].session_active;
}

// Predicate: currently inside New York session window
bool Sessions_InNewYork(const AppContext& ctx, const string symbol)
{
   if(UseLondonOnly)
      return false;
   Sessions_UpdateSymbol(ctx, symbol);
   int idx = Sessions_FindSlot(symbol);
   if(idx < 0)
      return false;
   return g_session_slots[idx].windows[SESSION_KIND_NEWYORK].session_active;
}

// Predicate: within the active session's OR window
bool Sessions_InORWindow(const AppContext& ctx, const string symbol)
{
   Sessions_UpdateSymbol(ctx, symbol);
   int idx = Sessions_FindSlot(symbol);
   if(idx < 0)
      return false;

   datetime now = ctx.current_server_time;
   SessionWindowState &lo = g_session_slots[idx].windows[SESSION_KIND_LONDON];
   if(lo.session_active && !lo.or_complete && now >= lo.or_start && now < lo.or_end)
      return true;

   if(!UseLondonOnly)
   {
      SessionWindowState &ny = g_session_slots[idx].windows[SESSION_KIND_NEWYORK];
      if(ny.session_active && !ny.or_complete && now >= ny.or_start && now < ny.or_end)
         return true;
   }
   return false;
}

bool Sessions_CutoffReached(const AppContext& ctx, const string symbol)
{
   (void)symbol;
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

   SessionWindowState &win = g_session_slots[slot].windows[kind_idx];
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
   out_snapshot.has_or_values = win.has_or_values;
   return true;
}

bool Sessions_GetLondonORSnapshot(const AppContext& ctx, const string symbol, SessionORSnapshot &out_snapshot)
{
   return Sessions_GetORSnapshot(ctx, symbol, SESSION_LABEL_LONDON, out_snapshot);
}

bool Sessions_GetNewYorkORSnapshot(const AppContext& ctx, const string symbol, SessionORSnapshot &out_snapshot)
{
   if(UseLondonOnly)
      return false;
   return Sessions_GetORSnapshot(ctx, symbol, SESSION_LABEL_NEWYORK, out_snapshot);
}

#endif // SESSIONS_MQH
