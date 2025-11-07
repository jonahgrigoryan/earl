#ifndef RPEA_APP_CONTEXT_MQH
#define RPEA_APP_CONTEXT_MQH
// app_context.mqh — Shared AppContext definition for RPEA modules

struct AppContext
  {
     datetime current_server_time;
     string   symbols[];
     int      symbols_count;
     // session flags (updated by scheduler)
     bool     session_london;
     bool     session_newyork;
     // baselines
     double   initial_baseline;
     double   baseline_today;
     double   equity_snapshot;
     // anchors for the current day
     double   baseline_today_e0; // equity at midnight
     double   baseline_today_b0; // balance at midnight
     // governance flags
     bool     trading_paused;
     bool     permanently_disabled;
     // persistence anchors
     datetime server_midnight_ts;
     datetime timer_last_check;
  };

extern AppContext g_ctx;

#endif // RPEA_APP_CONTEXT_MQH
