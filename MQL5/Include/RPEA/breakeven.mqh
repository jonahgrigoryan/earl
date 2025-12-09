#ifndef RPEA_BREAKEVEN_MQH
#define RPEA_BREAKEVEN_MQH
// breakeven.mqh - Breakeven stop manager (M3 Task 23)
// References: task23.md, .kiro/specs/rpea-m3/tasks.md §23

#include <RPEA/config.mqh>
#include <RPEA/logging.mqh>
#include <RPEA/queue.mqh>
#include <RPEA/news.mqh>

// Order engine hooks provided elsewhere
bool OrderEngine_GetIntentMetadata(const ulong ticket,
                                   string &out_intent_id,
                                   string &out_accept_key);
bool OrderEngine_RequestModifySLTP(const string symbol,
                                   const long ticket,
                                   const double new_sl,
                                   const double new_tp,
                                   const string context);

#ifdef RPEA_TEST_RUNNER
// Optional test stub for SL/TP modification
bool Breakeven_Test_Modify(const string symbol,
                           const long ticket,
                           const double new_sl,
                           const double new_tp,
                           const string context);
#endif

struct BreakevenState
  {
     long     ticket;
     double   entry_price;
     double   entry_sl;
     double   baseline_r;
     bool     applied;
     datetime updated_at;
  };

static BreakevenState g_be_states[];
static int            g_be_count = 0;

//------------------------------------------------------------------------------
// Helpers (exposed for tests)
//------------------------------------------------------------------------------

inline bool Breakeven_ShouldTriggerFromState(const bool is_long,
                                             const double entry_price,
                                             const double current_price,
                                             const double baseline_r)
  {
     if(baseline_r <= 0.0)
        return false;

     double gain = (is_long ? (current_price - entry_price)
                            : (entry_price - current_price));
     return (gain >= 0.5 * baseline_r - 1e-6);
  }

inline double Breakeven_ComputeSpreadPrice(const string symbol)
  {
     long spread_pts = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
     double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
     double extra_pts = Config_GetBreakevenExtraPoints();
     if(!MathIsValidNumber(point) || point <= 0.0)
        return 0.0;
     return ((double)spread_pts + extra_pts) * point;
  }

inline double Breakeven_ComputeTargetSLFromState(const bool is_long,
                                                 const double entry_price,
                                                 const double current_sl,
                                                 const double spread_price,
                                                 const double point,
                                                 const int digits)
  {
     double target = entry_price;
     if(spread_price > 0.0)
     {
        target = (is_long ? (entry_price + spread_price)
                          : (entry_price - spread_price));
     }

     if(is_long)
        target = MathMax(target, current_sl);
     else
        target = MathMin(target, current_sl);

     if(point > 0.0)
     {
        double steps = target / point;
        steps = MathRound(steps);
        target = steps * point;
     }

     if(digits >= 0)
        target = NormalizeDouble(target, digits);

     return target;
  }

bool Breakeven_QueueDuringNews(const string symbol,
                               const long ticket,
                               const double target_sl,
                               const string context,
                               long &out_queue_id)
  {
     out_queue_id = 0;
     string intent_id = "";
     string accept_key = "";
     OrderEngine_GetIntentMetadata((ulong)ticket, intent_id, accept_key);
     return Queue_Add(symbol,
                      ticket,
                      QA_SL_MODIFY,
                      target_sl,
                      0.0,
                      context,
                      out_queue_id,
                      intent_id,
                      accept_key);
  }

//------------------------------------------------------------------------------
// Internal helpers
//------------------------------------------------------------------------------

int Breakeven_FindIndex(const long ticket)
  {
     for(int i = 0; i < g_be_count; i++)
       {
          if(g_be_states[i].ticket == ticket)
             return i;
       }
     return -1;
  }

void Breakeven_EnsureCapacity(const int desired)
  {
     int capacity = ArraySize(g_be_states);
     if(desired <= capacity)
        return;
     int target = MathMax(desired, capacity + 8);
     ArrayResize(g_be_states, target);
  }

void Breakeven_RemoveAt(const int index)
  {
     if(index < 0 || index >= g_be_count)
        return;
     for(int i = index; i < g_be_count - 1; i++)
        g_be_states[i] = g_be_states[i + 1];
     g_be_count = MathMax(0, g_be_count - 1);
  }

//------------------------------------------------------------------------------
// Public API
//------------------------------------------------------------------------------

void Breakeven_Init()
  {
     g_be_count = 0;
     ArrayResize(g_be_states, 0);
  }

void Breakeven_HandleOnTickOrTimer()
  {
     const int total_positions = PositionsTotal();
     for(int pos_index = 0; pos_index < total_positions; pos_index++)
       {
          ulong pos_ticket = PositionGetTicket(pos_index);
          if(pos_ticket == 0 || !PositionSelectByTicket(pos_ticket))
             continue;

          int idx = Breakeven_FindIndex((long)pos_ticket);
          if(idx < 0)
          {
             Breakeven_EnsureCapacity(g_be_count + 1);
             idx = g_be_count++;
             g_be_states[idx].ticket = (long)pos_ticket;
             g_be_states[idx].entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
             g_be_states[idx].entry_sl = PositionGetDouble(POSITION_SL);
             g_be_states[idx].baseline_r = MathAbs(g_be_states[idx].entry_price - g_be_states[idx].entry_sl);
             g_be_states[idx].applied = false;
             g_be_states[idx].updated_at = TimeCurrent();
          }

          BreakevenState state = g_be_states[idx];
          if(state.applied)
          {
             g_be_states[idx] = state;
             continue;
          }

          if(state.baseline_r <= 0.0)
          {
             state.baseline_r = MathAbs(state.entry_price - state.entry_sl);
             if(state.baseline_r <= 0.0)
             {
                g_be_states[idx] = state;
                continue;
             }
          }

          string symbol = PositionGetString(POSITION_SYMBOL);
          ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
          double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
          bool trigger = Breakeven_ShouldTriggerFromState(pos_type == POSITION_TYPE_BUY,
                                                          state.entry_price,
                                                          current_price,
                                                          state.baseline_r);
          if(!trigger)
          {
             g_be_states[idx] = state;
             continue;
          }

          double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
          int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
          double spread_price = Breakeven_ComputeSpreadPrice(symbol);
          double current_sl = PositionGetDouble(POSITION_SL);
          double target_sl = Breakeven_ComputeTargetSLFromState(pos_type == POSITION_TYPE_BUY,
                                                                state.entry_price,
                                                                current_sl,
                                                                spread_price,
                                                                point,
                                                                digits);
          if(MathAbs(target_sl - current_sl) < 1e-6)
          {
             g_be_states[idx] = state;
             continue;
          }

          string context = StringFormat("{\"ticket\":%I64d,\"source\":\"breakeven\",\"spread\":%.5f,\"extra_pts\":%.2f}",
                                        (long)pos_ticket,
                                        spread_price,
                                        Config_GetBreakevenExtraPoints());

          bool applied = false;
          if(News_IsBlocked(symbol))
          {
             long queued_id = 0;
             applied = Breakeven_QueueDuringNews(symbol,
                                                 (long)pos_ticket,
                                                 target_sl,
                                                 context,
                                                 queued_id);
          }
          else
          {
#ifdef RPEA_TEST_RUNNER
             applied = Breakeven_Test_Modify(symbol,
                                             (long)pos_ticket,
                                             target_sl,
                                             0.0,
                                             context);
#else
                applied = OrderEngine_RequestModifySLTP(symbol,
                                                        (long)pos_ticket,
                                                        target_sl,
                                                        0.0,
                                                        context);
#endif
          }

          if(applied)
          {
             state.applied = true;
             state.updated_at = TimeCurrent();
          }
          g_be_states[idx] = state;
       }
  }

void Breakeven_OnPositionClosed(const long ticket)
  {
     int idx = Breakeven_FindIndex(ticket);
     if(idx >= 0)
        Breakeven_RemoveAt(idx);
  }

void Breakeven_Test_Reset()
  {
     Breakeven_Init();
  }

#endif // RPEA_BREAKEVEN_MQH

