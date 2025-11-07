#ifndef RPEA_TRAILING_MQH
#define RPEA_TRAILING_MQH
// trailing.mqh - Trailing stop manager (M3 Task 13)
// References: task12-13.md §Trailing, .kiro/specs/rpea-m3/tasks.md §13

#include <RPEA/config.mqh>
#include <RPEA/logging.mqh>
#include <RPEA/app_context.mqh>
#include <RPEA/queue.mqh>
#include <RPEA/news.mqh>
#include <RPEA/indicators.mqh>

bool OrderEngine_GetIntentMetadata(const ulong ticket,
                                   string &out_intent_id,
                                   string &out_accept_key);

struct TrailState
  {
     long   ticket;
     double last_trail_price;
     double baseline_r;
     double entry_price;
     double entry_sl;
     bool   active;
     datetime updated_at;
  };

static TrailState g_trail_states[];
static int        g_trail_count = 0;

bool OrderEngine_RequestModifySLTP(const string symbol,
                                   const long ticket,
                                   const double new_sl,
                                   const double new_tp,
                                   const string context);

void   Trail_Init();
bool   Trail_ShouldActivateAtPlus1R(const string symbol, const long ticket);
bool   Trail_ShouldActivateFromState(const bool is_long,
                                     const double entry_price,
                                     const double current_price,
                                     const double baseline_r);
double Trail_ComputeNewSL(const string symbol,
                          const long ticket,
                          const double atr_from_indicator_slot,
                          const double trail_mult);
double Trail_ComputeNewSLFromState(const bool is_long,
                                   const double current_price,
                                   const double current_sl,
                                   const double last_trail,
                                   const double atr_from_indicator_slot,
                                   const double trail_mult,
                                   const double point,
                                   const int digits);

void   Trail_HandleOnTickOrTimer();

bool   Trail_QueueDuringNews(const string symbol,
                             const long ticket,
                             const double new_sl,
                             const string context,
                             long &out_queue_id);

bool   Trail_ApplyWhenClear(const string symbol,
                            const long ticket,
                            const double new_sl,
                            const string context);

void   Trail_OnPositionClosed(const long ticket);

void   Trail_Test_Reset();

//------------------------------------------------------------------------------
// Implementation
//------------------------------------------------------------------------------

void Trail_EnsureCapacity(const int desired)
  {
     int capacity = ArraySize(g_trail_states);
     if(desired <= capacity)
        return;
     int target = MathMax(desired, capacity + 8);
     ArrayResize(g_trail_states, target);
  }

int Trail_FindIndex(const long ticket)
  {
     for(int i = 0; i < g_trail_count; i++)
       {
          if(g_trail_states[i].ticket == ticket)
             return i;
       }
     return -1;
  }

void Trail_RemoveAt(const int index)
  {
     if(index < 0 || index >= g_trail_count)
        return;
     for(int i = index; i < g_trail_count - 1; i++)
        g_trail_states[i] = g_trail_states[i + 1];
     g_trail_count = MathMax(0, g_trail_count - 1);
  }

void Trail_Init()
  {
     g_trail_count = 0;
     ArrayResize(g_trail_states, 0);
  }

bool Trail_ShouldActivateAtPlus1R(const string symbol, const long ticket)
  {
     if(!PositionSelectByTicket((ulong)ticket))
        return false;

     int idx = Trail_FindIndex(ticket);
     if(idx < 0)
       {
          Trail_EnsureCapacity(g_trail_count + 1);
          idx = g_trail_count++;
          g_trail_states[idx].ticket = ticket;
          g_trail_states[idx].entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
          g_trail_states[idx].entry_sl = PositionGetDouble(POSITION_SL);
          g_trail_states[idx].last_trail_price = PositionGetDouble(POSITION_SL);
          g_trail_states[idx].baseline_r = MathAbs(g_trail_states[idx].entry_price - g_trail_states[idx].entry_sl);
          g_trail_states[idx].active = false;
          g_trail_states[idx].updated_at = TimeCurrent();
       }

     TrailState state = g_trail_states[idx];
     if(state.baseline_r <= 0.0)
        state.baseline_r = MathAbs(state.entry_price - state.entry_sl);
     if(state.baseline_r <= 0.0)
     {
        g_trail_states[idx] = state;
        return false;
     }

     double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
     ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
     bool activated = Trail_ShouldActivateFromState(pos_type == POSITION_TYPE_BUY,
                                                    state.entry_price,
                                                    current_price,
                                                    state.baseline_r);
     if(activated)
        state.active = true;

     g_trail_states[idx] = state;
     return state.active;
  }

bool Trail_ShouldActivateFromState(const bool is_long,
                                   const double entry_price,
                                   const double current_price,
                                   const double baseline_r)
  {
     if(baseline_r <= 0.0)
        return false;

     double gain = (is_long ? (current_price - entry_price)
                            : (entry_price - current_price));
     return (gain >= baseline_r - 1e-6);
  }

double Trail_ComputeNewSL(const string symbol,
                          const long ticket,
                          const double atr_from_indicator_slot,
                          const double trail_mult)
  {
     if(!PositionSelectByTicket((ulong)ticket))
        return 0.0;

     int idx = Trail_FindIndex(ticket);
     if(idx < 0)
        return 0.0;

   TrailState state = g_trail_states[idx];
   ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   double current_sl = PositionGetDouble(POSITION_SL);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   return Trail_ComputeNewSLFromState(pos_type == POSITION_TYPE_BUY,
                                      current_price,
                                      current_sl,
                                      state.last_trail_price,
                                      atr_from_indicator_slot,
                                      trail_mult,
                                      point,
                                      digits);
  }

double Trail_ComputeNewSLFromState(const bool is_long,
                                   const double current_price,
                                   const double current_sl,
                                   const double last_trail,
                                   const double atr_from_indicator_slot,
                                   const double trail_mult,
                                   const double point,
                                   const int digits)
  {
     double atr = (atr_from_indicator_slot > 0.0 ? atr_from_indicator_slot : 0.0);
     double step = atr * trail_mult;
     double new_sl = current_sl;

     if(is_long)
     {
        new_sl = current_price - step;
        if(last_trail > 0.0)
           new_sl = MathMax(new_sl, last_trail);
        new_sl = MathMax(new_sl, current_sl);
     }
     else
     {
        new_sl = current_price + step;
        if(last_trail > 0.0)
           new_sl = MathMin(new_sl, last_trail);
        new_sl = MathMin(new_sl, current_sl);
     }

     if(point > 0.0)
     {
        double steps = new_sl / point;
        steps = MathRound(steps);
        new_sl = steps * point;
     }

     if(digits >= 0)
        new_sl = NormalizeDouble(new_sl, digits);

     return new_sl;
  }

void Trail_HandleOnTickOrTimer()
  {
     const double trail_mult = TrailMult;
     const int total_positions = PositionsTotal();
     for(int pos_index = 0; pos_index < total_positions; pos_index++)
       {
          ulong pos_ticket = PositionGetTicket(pos_index);
          if(pos_ticket == 0 || !PositionSelectByTicket(pos_ticket))
             continue;
          long ticket = (long)pos_ticket;
          string symbol = PositionGetString(POSITION_SYMBOL);

          if(!Trail_ShouldActivateAtPlus1R(symbol, ticket))
             continue;

          IndicatorSnapshot snap;
          Indicators_GetSnapshot(symbol, snap);
          double atr = (snap.has_atr ? snap.atr_d1 : 0.0);
          double current_sl = PositionGetDouble(POSITION_SL);
          double new_sl = Trail_ComputeNewSL(symbol, ticket, atr, trail_mult);

          if(MathAbs(new_sl - current_sl) < 1e-6)
             continue;

          string context = StringFormat("{\"ticket\":%I64d,\"source\":\"trailing\",\"atr\":%.5f,\"trail_mult\":%.3f}",
                                        ticket, atr, trail_mult);

          if(News_IsBlocked(symbol))
          {
             long queued_id = 0;
             if(Trail_QueueDuringNews(symbol, ticket, new_sl, context, queued_id))
             {
                int idx = Trail_FindIndex(ticket);
                if(idx >= 0)
                {
                   g_trail_states[idx].last_trail_price = new_sl;
                   g_trail_states[idx].updated_at = TimeCurrent();
                   g_trail_states[idx].active = true;
                }
             }
             continue;
          }

          if(Trail_ApplyWhenClear(symbol, ticket, new_sl, context))
          {
             int idx = Trail_FindIndex(ticket);
             if(idx >= 0)
             {
                g_trail_states[idx].last_trail_price = new_sl;
                g_trail_states[idx].updated_at = TimeCurrent();
                g_trail_states[idx].active = true;
             }
          }
       }
  }

bool Trail_QueueDuringNews(const string symbol,
                           const long ticket,
                           const double new_sl,
                           const string context,
                           long &out_queue_id)
  {
     out_queue_id = 0;
     string intent_id = "";
     string accept_key = "";
     OrderEngine_GetIntentMetadata(ticket, intent_id, accept_key);
     return Queue_Add(symbol,
                      ticket,
                      QA_SL_MODIFY,
                      new_sl,
                      0.0,
                      context,
                      out_queue_id,
                      intent_id,
                      accept_key);
  }

bool Trail_ApplyWhenClear(const string symbol,
                          const long ticket,
                          const double new_sl,
                          const string context)
  {
     return OrderEngine_RequestModifySLTP(symbol, ticket, new_sl, 0.0, context);
  }

void Trail_OnPositionClosed(const long ticket)
  {
     int idx = Trail_FindIndex(ticket);
     if(idx >= 0)
        Trail_RemoveAt(idx);
  }

void Trail_Test_Reset()
  {
     Trail_Init();
  }

#endif // RPEA_TRAILING_MQH
