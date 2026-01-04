#ifndef RPEA_QUEUE_MQH
#define RPEA_QUEUE_MQH
// queue.mqh - Deferred order modification queue (M3 Task 12)
// References: task12-13.md, .kiro/specs/rpea-m3/tasks.md §12

#include <RPEA/config.mqh>
#include <RPEA/app_context.mqh>
#include <RPEA/logging.mqh>
#include <RPEA/news.mqh>
#include <RPEA/equity_guardian.mqh>
#include <RPEA/sessions.mqh>
#include <RPEA/timeutils.mqh>
#include <RPEA/persistence.mqh>

enum QueueActionType
  {
     QA_SL_MODIFY = 0,
     QA_TP_MODIFY = 1,
     QA_CLOSE      = 2
  };

enum QueuePriorityTier
  {
     QP_PROTECTIVE_EXIT = 0,
     QP_TIGHTEN_SL      = 1,
     QP_OTHER           = 2
  };

struct QueuedAction
  {
     long               id;
     long               ticket;
     QueueActionType    action_type;
     datetime           created_at;
     datetime           expires_at;
     QueuePriorityTier  priority;
     string             symbol;
     double             new_sl;
     double             new_tp;
     string             context_hex;
     int                retry_count;
     string             intent_id;
     string             intent_key;
  };

//------------------------------------------------------------------------------
// Internal state (with performance improvements)
//------------------------------------------------------------------------------

static QueuedAction g_queue_buffer[];
static int          g_queue_count = 0;
static long         g_queue_next_id = 1;
static bool         g_queue_initialized = false;
static int          g_queue_ttl_minutes = DEFAULT_QueueTTLMinutes;
static int          g_queue_max_size = DEFAULT_MaxQueueSize;
static bool         g_queue_prioritization = DEFAULT_EnableQueuePrioritization;
static int          g_queue_process_batch = 1;

// Performance: Dirty flag for write coalescing
static bool         g_queue_dirty = false;

struct QueueTestOverrides
  {
     bool active;
     bool floors_ok;
     bool caps_ok;
     bool budget_ok;
     bool session_ok;
     bool news_blocked;
  };

struct QueueTestPosition
  {
     bool  in_use;
     long  ticket;
     bool  is_long;
     double price_current;
     double current_sl;
     double current_tp;
  };

static QueueTestOverrides g_queue_test_overrides = {false, true, true, true, true, false};
static QueueTestPosition  g_queue_test_positions[16];

//------------------------------------------------------------------------------
// Utility helpers
//------------------------------------------------------------------------------

void Queue_RecomputeBatchSize()
  {
     int denom = g_queue_max_size / 10;
     if(denom <= 0)
        denom = 1;
     g_queue_process_batch = MathMax(1, denom);
  }

string Queue_ContextToHex(const string value)
  {
     string hex = "";
     const int len = StringLen(value);
     for(int i = 0; i < len; i++)
       {
          const ushort ch = StringGetCharacter(value, i);
          hex += StringFormat("%02X", (int)ch);
       }
     return hex;
  }

int Queue_HexCharToInt(const ushort ch)
  {
     if(ch >= '0' && ch <= '9')
        return ch - '0';
     if(ch >= 'A' && ch <= 'F')
        return 10 + (ch - 'A');
     if(ch >= 'a' && ch <= 'f')
        return 10 + (ch - 'a');
     return 0;
  }

string Queue_ContextFromHex(const string hex)
  {
     if(StringLen(hex) % 2 != 0)
        return "";
     string result = "";
     const int len = StringLen(hex);
     for(int i = 0; i < len; i += 2)
       {
          ushort hi = StringGetCharacter(hex, i);
          ushort lo = StringGetCharacter(hex, i + 1);
          int value = Queue_HexCharToInt(hi) * 16 + Queue_HexCharToInt(lo);
          result += CharToString((ushort)value);
       }
     return result;
  }

datetime Queue_ComputeExpiry(const datetime created)
  {
     int ttl = g_queue_ttl_minutes;
     if(ttl <= 0)
        ttl = DEFAULT_QueueTTLMinutes;
     return created + (datetime)(ttl * 60);
  }

void Queue_EnsureCapacity(const int desired)
  {
     int capacity = ArraySize(g_queue_buffer);
     if(desired <= capacity)
        return;
     int target = MathMax(desired, capacity + 16);
     ArrayResize(g_queue_buffer, target);
  }

int Queue_FindIndexById(const long id)
  {
     for(int i = 0; i < g_queue_count; i++)
       {
          if(g_queue_buffer[i].id == id)
             return i;
       }
     return -1;
  }

int Queue_FindIndexByTicketAction(const long ticket,
                                         const QueueActionType type)
  {
     for(int i = 0; i < g_queue_count; i++)
       {
          if(g_queue_buffer[i].ticket == ticket && g_queue_buffer[i].action_type == type)
             return i;
       }
     return -1;
  }

void Queue_RemoveAt(const int index)
  {
     if(index < 0 || index >= g_queue_count)
        return;
     for(int i = index; i < g_queue_count - 1; i++)
        g_queue_buffer[i] = g_queue_buffer[i + 1];
     g_queue_count = MathMax(0, g_queue_count - 1);
  }

void Queue_Test_ResetPositions()
  {
     for(int i = 0; i < ArraySize(g_queue_test_positions); i++)
        g_queue_test_positions[i].in_use = false;
  }

bool Queue_Test_GetPosition(const long ticket,
                                   bool &out_is_long,
                                   double &out_price_current,
                                   double &out_sl,
                                   double &out_tp)
  {
     for(int i = 0; i < ArraySize(g_queue_test_positions); i++)
     {
        if(!g_queue_test_positions[i].in_use)
           continue;
        if(g_queue_test_positions[i].ticket == ticket)
        {
           out_is_long = g_queue_test_positions[i].is_long;
           out_price_current = g_queue_test_positions[i].price_current;
           out_sl = g_queue_test_positions[i].current_sl;
           out_tp = g_queue_test_positions[i].current_tp;
           return true;
        }
     }
     return false;
  }

//------------------------------------------------------------------------------
// Public API
//------------------------------------------------------------------------------

void   Queue_Init(const int ttl_minutes,
                  const int max_queue_size,
                  const bool enable_prioritization);

bool   Queue_Add(const string symbol,
                 const long ticket,
                 const QueueActionType action_type,
                 const double new_sl,
                 const double new_tp,
                 const string context,
                 long &out_id,
                 const string intent_id = "",
                 const string intent_key = "");

int    Queue_RevalidateAndApply();
int    Queue_CancelExpired();
bool   Queue_ClearForTicket(const long ticket);
int    Queue_Size();
bool   Queue_CoalesceIfRedundant(const long ticket,
                                 const double current_sl,
                                 const double current_tp);

bool   Queue_SaveOrUpdateOnDisk(const QueuedAction &qa);
bool   Queue_DeleteFromDiskById(const long id);
int    Queue_LoadFromDiskAndReconcile();

// Performance: Flush pending writes
void   Queue_FlushIfDirty();

// M4-Task03: Clear all queued actions (kill-switch)
void   Queue_ClearAll(const string reason);

//------------------------------------------------------------------------------
// Internal helpers (exposed for testing)
//------------------------------------------------------------------------------

QueuePriorityTier Queue_ComputePriority(const QueueActionType type,
                                        const double old_sl,
                                        const double new_sl,
                                        const bool is_long);

bool   Queue_RevalidateItem(QueuedAction &qa,
                            string &out_reason_code,
                            bool &out_skip_for_news,
                            bool &out_permanent_failure);

bool   Queue_CheckNewsWindow(const string symbol,
                             const QueueActionType action_type,
                             string &out_reason_code);

bool   Queue_CheckRiskAndCaps(const string symbol,
                              const long ticket,
                              const QueueActionType action_type,
                              const bool is_risk_reducing,
                              string &out_reason_code,
                              bool &out_permanent_failure);

bool   Queue_CheckSymbolSession(const string symbol,
                                string &out_reason_code);

int    Queue_AdmitOrBackpressure(const QueuedAction &incoming,
                                 string &out_reason_code,
                                 long &out_evicted_id);

//------------------------------------------------------------------------------
// Order Engine integration hooks (implemented in order_engine.mqh)
//------------------------------------------------------------------------------

bool Queue_OrderEngine_ApplyAction(const QueuedAction &qa,
                                   string &out_reason_code,
                                   bool &out_permanent_failure);

bool Queue_OrderEngine_IsRiskReducing(const QueuedAction &qa,
                                      const double current_sl,
                                      const double current_tp,
                                      bool &out_is_risk_reducing);

double Queue_OrderEngine_GetMinStopDistancePoints(const string symbol);

void Queue_LogAuditEvent(const QueuedAction &qa,
                         const string symbol,
                         const string decision,
                         const string context_json)
  {
     AuditRecord record;
     record.timestamp = TimeCurrent();
     record.intent_id = (StringLen(qa.intent_id) > 0 ? qa.intent_id : "queue");
     record.action_id = StringFormat("%s:QUEUE:%I64d", record.intent_id, qa.id);
     record.symbol = (StringLen(symbol) > 0 ? symbol : qa.symbol);
     record.mode = "QUEUE";
     record.requested_price = (qa.action_type == QA_SL_MODIFY ? qa.new_sl :
                               qa.action_type == QA_TP_MODIFY ? qa.new_tp : 0.0);
     record.executed_price = 0.0;
     record.requested_vol = 0.0;
     record.filled_vol = 0.0;
     record.remaining_vol = 0.0;
     if(qa.ticket > 0)
     {
        ArrayResize(record.tickets, 1);
        record.tickets[0] = (ulong)qa.ticket;
     }
     record.retry_count = qa.retry_count;
     record.decision = decision;
     record.gating_reason = context_json;
     record.news_window_state = News_GetWindowState(record.symbol, false);
     AuditLogger_Log(record);
  }

//------------------------------------------------------------------------------
// Test hooks
//------------------------------------------------------------------------------

void   Queue_Test_Reset();
int    Queue_Test_GetBufferCapacity();
bool   Queue_Test_AddDirect(const QueuedAction &qa);
void   Queue_Test_ClearOverrides();
void   Queue_Test_SetRiskOverrides(const bool active,
                                   const bool floors_ok,
                                   const bool caps_ok,
                                   const bool budget_ok,
                                   const bool session_ok);
void   Queue_Test_SetNewsBlocked(const bool blocked);
void   Queue_Test_RegisterPosition(const long ticket,
                                   const bool is_long,
                                   const double price_current,
                                   const double current_sl,
                                   const double current_tp);
void   Queue_Test_ClearPositions();
bool   Queue_Test_GetAction(const int index, QueuedAction &out_action);

//------------------------------------------------------------------------------
// Implementation
//------------------------------------------------------------------------------

void Queue_Init(const int ttl_minutes,
                const int max_queue_size,
                const bool enable_prioritization)
  {
     g_queue_ttl_minutes = (ttl_minutes > 0 ? ttl_minutes : DEFAULT_QueueTTLMinutes);
     g_queue_max_size = (max_queue_size > 0 ? max_queue_size : DEFAULT_MaxQueueSize);
     g_queue_prioritization = enable_prioritization;
     Queue_RecomputeBatchSize();
     g_queue_initialized = true;
     g_queue_dirty = false; // Initialize dirty flag
  }

int Queue_Size()
  {
     return g_queue_count;
  }

void Queue_Test_Reset()
  {
     g_queue_count = 0;
     ArrayResize(g_queue_buffer, 0);
     g_queue_next_id = 1;
     g_queue_initialized = false;
     g_queue_ttl_minutes = DEFAULT_QueueTTLMinutes;
     g_queue_max_size = DEFAULT_MaxQueueSize;
     g_queue_prioritization = DEFAULT_EnableQueuePrioritization;
     g_queue_dirty = false; // Reset dirty flag
     Queue_RecomputeBatchSize();
     Queue_Test_ClearOverrides();
  }

int Queue_Test_GetBufferCapacity()
  {
     return ArraySize(g_queue_buffer);
  }

bool Queue_Test_AddDirect(const QueuedAction &qa)
  {
     Queue_EnsureInitialized();
     QueuedAction copy = qa;
     Queue_NormalizeAction(copy);
     Queue_EnsureCapacity(g_queue_count + 1);
     g_queue_buffer[g_queue_count++] = copy;
     Queue_SaveAll();
     return true;
  }

void Queue_Test_ClearOverrides()
  {
     g_queue_test_overrides.active = false;
     g_queue_test_overrides.floors_ok = true;
     g_queue_test_overrides.caps_ok = true;
     g_queue_test_overrides.budget_ok = true;
     g_queue_test_overrides.session_ok = true;
     g_queue_test_overrides.news_blocked = false;
     Queue_Test_ResetPositions();
  }

void Queue_Test_SetRiskOverrides(const bool active,
                                 const bool floors_ok,
                                 const bool caps_ok,
                                 const bool budget_ok,
                                 const bool session_ok)
  {
     g_queue_test_overrides.active = active;
     g_queue_test_overrides.floors_ok = floors_ok;
     g_queue_test_overrides.caps_ok = caps_ok;
     g_queue_test_overrides.budget_ok = budget_ok;
     g_queue_test_overrides.session_ok = session_ok;
  }

void Queue_Test_SetNewsBlocked(const bool blocked)
  {
     g_queue_test_overrides.news_blocked = blocked;
  }

void Queue_Test_RegisterPosition(const long ticket,
                                 const bool is_long,
                                 const double price_current,
                                 const double current_sl,
                                 const double current_tp)
  {
     for(int i = 0; i < ArraySize(g_queue_test_positions); i++)
     {
        if(!g_queue_test_positions[i].in_use || g_queue_test_positions[i].ticket == ticket)
        {
           g_queue_test_positions[i].in_use = true;
           g_queue_test_positions[i].ticket = ticket;
           g_queue_test_positions[i].is_long = is_long;
           g_queue_test_positions[i].price_current = price_current;
           g_queue_test_positions[i].current_sl = current_sl;
           g_queue_test_positions[i].current_tp = current_tp;
           return;
        }
     }
  }

void Queue_Test_ClearPositions()
  {
     Queue_Test_ResetPositions();
  }

bool Queue_Test_GetAction(const int index, QueuedAction &out_action)
  {
     if(index < 0 || index >= g_queue_count)
        return false;
     out_action = g_queue_buffer[index];
     return true;
  }

bool Queue_SaveAll()
  {
     int handle = FileOpen(FILE_QUEUE_ACTIONS, FILE_WRITE|FILE_TXT|FILE_ANSI);
     if(handle == INVALID_HANDLE)
     {
        // One-time warning for operational visibility
        static bool s_queue_warned = false;
        if(!s_queue_warned)
        {
           s_queue_warned = true;
           PrintFormat("[Queue] Failed to write %s; queue persistence degraded", FILE_QUEUE_ACTIONS);
        }
        return false;
     }

     FileWrite(handle, "id,ticket,action_type,symbol,created_at,expires_at,priority,new_sl,new_tp,context,retry_count,intent_id,intent_key");
     for(int i = 0; i < g_queue_count; i++)
       {
          const QueuedAction qa = g_queue_buffer[i];
          string line = StringFormat("%I64d,%I64d,%d,%s,%I64d,%I64d,%d,%.10f,%.10f,%s,%d,%s,%s",
                                     qa.id,
                                     qa.ticket,
                                     (int)qa.action_type,
                                     qa.symbol,
                                     (long)qa.created_at,
                                     (long)qa.expires_at,
                                     (int)qa.priority,
                                     qa.new_sl,
                                     qa.new_tp,
                                     qa.context_hex,
                                     qa.retry_count,
                                     qa.intent_id,
                                     qa.intent_key);
          FileWrite(handle, line);
       }
     FileClose(handle);
     g_queue_dirty = false; // Clear dirty flag after successful save
     return true;
  }

// Performance: Write coalescing - mark dirty only, flush later
bool Queue_SaveOrUpdateOnDisk(const QueuedAction &qa)
  {
     g_queue_dirty = true; // Mark for later flush
     return true;
  }

bool Queue_DeleteFromDiskById(const long id)
  {
     g_queue_dirty = true; // Mark for later flush
     return true;
  }

// Performance: Flush helper for coalesced writes
void Queue_FlushIfDirty()
  {
     if(!g_queue_dirty)
        return;
     if(!Queue_SaveAll())
     {
        LogAuditRow("QUEUE_STATE", "Queue", LOG_WARN, "SAVE_FAIL", "{}" );
     }
     else
     {
        LogAuditRow("QUEUE_STATE", "Queue", LOG_INFO, "SAVE_OK", "{}");
     }
  }

// M4-Task03: Clear all queued actions on kill-switch
void Queue_ClearAll(const string reason)
  {
     for(int i = g_queue_count - 1; i >= 0; i--)
     {
        long removed_id = g_queue_buffer[i].id;
        Queue_RemoveAt(i);
        Queue_DeleteFromDiskById(removed_id);
        string fields = StringFormat("{\"queue_id\":%I64d,\"reason\":\"%s\"}", removed_id, reason);
        LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "KILLSWITCH_QUEUE_CLEAR", fields);
     }
     Queue_FlushIfDirty();
  }

void Queue_EnsureInitialized()
  {
     if(g_queue_initialized)
        return;
     Queue_Init(DEFAULT_QueueTTLMinutes, DEFAULT_MaxQueueSize, DEFAULT_EnableQueuePrioritization);
  }

void Queue_NormalizeAction(QueuedAction &qa)
  {
     if(qa.created_at <= 0)
        qa.created_at = TimeCurrent();
     if(qa.expires_at <= qa.created_at)
        qa.expires_at = Queue_ComputeExpiry(qa.created_at);
     if(qa.priority < QP_PROTECTIVE_EXIT || qa.priority > QP_OTHER)
        qa.priority = QP_OTHER;
     if(qa.retry_count < 0)
        qa.retry_count = 0;
     if(StringLen(qa.context_hex) == 0)
        qa.context_hex = Queue_ContextToHex("{}");
     if(StringLen(qa.intent_id) == 0)
        qa.intent_id = "";
     if(StringLen(qa.intent_key) == 0)
        qa.intent_key = "";
  }

int Queue_AdmitOrBackpressure(const QueuedAction &incoming,
                              string &out_reason_code,
                              long &out_evicted_id)
  {
     out_reason_code = "";
     out_evicted_id = 0;
     if(g_queue_count < g_queue_max_size)
        return 0;

     if(!g_queue_prioritization)
       {
          // Evict oldest overall
          datetime oldest_time = 0;
          int oldest_idx = -1;
          for(int i = 0; i < g_queue_count; i++)
            {
               if(oldest_idx < 0 || g_queue_buffer[i].created_at < oldest_time)
               {
                  oldest_time = g_queue_buffer[i].created_at;
                  oldest_idx = i;
               }
            }
          if(oldest_idx >= 0)
            {
               out_evicted_id = g_queue_buffer[oldest_idx].id;
               Queue_RemoveAt(oldest_idx);
               out_reason_code = "OVERFLOW_EVICT";
               return 1;
            }
          out_reason_code = "OVERFLOW_REJECT";
          return -1;
       }

     // Prioritization enabled: find lowest-priority tier to evict
     QueuePriorityTier lowest_tier = incoming.priority;
     bool found_lower = false;
     for(int i = 0; i < g_queue_count; i++)
       {
          if(g_queue_buffer[i].priority > lowest_tier)
          {
             lowest_tier = g_queue_buffer[i].priority;
             found_lower = true;
          }
       }

     if(!found_lower)
     {
        out_reason_code = "OVERFLOW_REJECT";
        return -1;
     }

     datetime oldest_time = 0;
     int oldest_idx = -1;
     for(int i = 0; i < g_queue_count; i++)
       {
          if(g_queue_buffer[i].priority != lowest_tier)
             continue;
          if(oldest_idx < 0 || g_queue_buffer[i].created_at < oldest_time)
            {
               oldest_time = g_queue_buffer[i].created_at;
               oldest_idx = i;
            }
       }

     if(oldest_idx >= 0)
     {
        out_evicted_id = g_queue_buffer[oldest_idx].id;
        Queue_RemoveAt(oldest_idx);
        out_reason_code = "OVERFLOW_EVICT";
        return 1;
     }

     out_reason_code = "OVERFLOW_REJECT";
     return -1;
  }

QueuePriorityTier Queue_ComputePriority(const QueueActionType type,
                                        const double old_sl,
                                        const double new_sl,
                                        const bool is_long)
  {
     if(type == QA_CLOSE)
        return QP_PROTECTIVE_EXIT;

     if(type == QA_SL_MODIFY)
       {
          double delta = new_sl - old_sl;
          const double tolerance = 1e-6;
          if(is_long && delta > tolerance)
             return QP_TIGHTEN_SL;
          if(!is_long && delta < -tolerance)
             return QP_TIGHTEN_SL;
       }

     return QP_OTHER;
  }

bool Queue_IsRiskIncreasing(const QueueActionType type,
                                   const double old_sl,
                                   const double new_sl,
                                   const bool is_long)
  {
     if(type != QA_SL_MODIFY)
        return false;
     const double tolerance = 1e-6;
     if(is_long && new_sl < old_sl - tolerance)
        return true;
     if(!is_long && new_sl > old_sl + tolerance)
        return true;
     return false;
  }

bool Queue_Add(const string symbol,
               const long ticket,
               const QueueActionType action_type,
               const double new_sl,
               const double new_tp,
               const string context,
               long &out_id,
               const string intent_id,
               const string intent_key)
  {
     Queue_EnsureInitialized();
     out_id = 0;

     if(StringLen(symbol) == 0 || ticket <= 0)
        return false;

     bool is_long = true;
     double old_sl = 0.0;
     double old_tp = 0.0;
     double dummy_price = 0.0;
     bool has_position = Queue_Test_GetPosition(ticket, is_long, dummy_price, old_sl, old_tp);
     if(!has_position)
     {
        if(!PositionSelectByTicket((ulong)ticket))
           return false;
        old_sl = PositionGetDouble(POSITION_SL);
        old_tp = PositionGetDouble(POSITION_TP);
        const ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        is_long = (pos_type == POSITION_TYPE_BUY);
        has_position = true;
     }
     if(!has_position)
        return false;

     if(action_type == QA_SL_MODIFY)
     {
        if(Queue_IsRiskIncreasing(action_type, old_sl, new_sl, is_long))
        {
           string reason = "RISK_INCREASING_NOT_ALLOWED";
           string fields = StringFormat("{\"ticket\":%I64d,\"symbol\":\"%s\",\"reason\":\"%s\"}",
                                        ticket, symbol, reason);
           LogAuditRow("QUEUE", "OrderEngine", LOG_WARN, reason, fields);
           return false;
        }
     }

     QueuedAction qa;
     qa.id = g_queue_next_id++;
     qa.ticket = ticket;
     qa.action_type = action_type;
     qa.symbol = symbol;
     qa.created_at = TimeCurrent();
     qa.expires_at = Queue_ComputeExpiry(qa.created_at);
     qa.new_sl = (action_type == QA_SL_MODIFY ? new_sl : 0.0);
     qa.new_tp = (action_type == QA_TP_MODIFY ? new_tp : 0.0);
     qa.context_hex = Queue_ContextToHex(context);
     qa.retry_count = 0;
     qa.priority = Queue_ComputePriority(action_type, old_sl, qa.new_sl, is_long);
     qa.intent_id = intent_id;
     qa.intent_key = intent_key;

     Queue_NormalizeAction(qa);

     int existing_index = Queue_FindIndexByTicketAction(ticket, action_type);
     if(existing_index >= 0)
     {
        qa.id = g_queue_buffer[existing_index].id;
        qa.created_at = g_queue_buffer[existing_index].created_at;
        // Preserve retry count but reset on new payload
        qa.retry_count = g_queue_buffer[existing_index].retry_count;
        if(StringLen(qa.intent_id) == 0)
           qa.intent_id = g_queue_buffer[existing_index].intent_id;
        if(StringLen(qa.intent_key) == 0)
           qa.intent_key = g_queue_buffer[existing_index].intent_key;
        g_queue_buffer[existing_index] = qa;
        Queue_SaveOrUpdateOnDisk(qa);
        out_id = qa.id;
        string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"action\":%d,\"reason\":\"COALESCE_UPDATE\"}",
                                     qa.id, qa.ticket, (int)qa.action_type);
        LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "QUEUE_UPDATE", fields);
        return true;
     }

     string backpressure_reason = "";
     long evicted_id = 0;
     int bp = Queue_AdmitOrBackpressure(qa, backpressure_reason, evicted_id);
     if(bp < 0)
     {
        string fields = StringFormat("{\"ticket\":%I64d,\"action\":%d,\"reason\":\"%s\"}",
                                     ticket, (int)action_type, backpressure_reason);
        LogAuditRow("QUEUE", "OrderEngine", LOG_WARN, backpressure_reason, fields);
        return false;
     }

     if(bp > 0 && evicted_id > 0)
     {
        string fields = StringFormat("{\"evicted_id\":%I64d,\"reason\":\"OVERFLOW_EVICT\"}", evicted_id);
        LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "OVERFLOW_EVICT", fields);
     }

     Queue_EnsureCapacity(g_queue_count + 1);
     g_queue_buffer[g_queue_count++] = qa;
     Queue_SaveOrUpdateOnDisk(qa);
     out_id = qa.id;

     string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"action\":%d,\"priority\":%d,\"reason\":\"QUEUED_NEWS\"}",
                                  qa.id, qa.ticket, (int)qa.action_type, (int)qa.priority);
     LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "QUEUED_NEWS", fields);
     Queue_LogAuditEvent(qa, symbol, "QUEUED_NEWS", context);
     return true;
  }

bool Queue_ClearForTicket(const long ticket)
  {
     bool removed = false;
     for(int i = g_queue_count - 1; i >= 0; i--)
       {
          if(g_queue_buffer[i].ticket != ticket)
             continue;
          long removed_id = g_queue_buffer[i].id;
          Queue_RemoveAt(i);
          Queue_DeleteFromDiskById(removed_id);
          removed = true;
          string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"COALESCE_DROP\"}", removed_id, ticket);
          LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "COALESCE_DROP", fields);
       }
     if(removed)
        Queue_FlushIfDirty(); // Use coalesced flush
     return removed;
  }

bool Queue_CoalesceIfRedundant(const long ticket,
                               const double current_sl,
                               const double current_tp)
  {
     bool removed = false;
     const double eps = 1e-5;
     for(int i = g_queue_count - 1; i >= 0; i--)
       {
          if(g_queue_buffer[i].ticket != ticket)
             continue;
          bool is_redundant = false;
          if(g_queue_buffer[i].action_type == QA_SL_MODIFY)
          {
             double queued_sl = g_queue_buffer[i].new_sl;
             if(MathAbs(queued_sl - current_sl) <= eps)
                is_redundant = true;
          }
          else if(g_queue_buffer[i].action_type == QA_TP_MODIFY)
          {
             double queued_tp = g_queue_buffer[i].new_tp;
             if(MathAbs(queued_tp - current_tp) <= eps)
                is_redundant = true;
          }

          if(is_redundant)
          {
             long removed_id = g_queue_buffer[i].id;
             Queue_RemoveAt(i);
             Queue_DeleteFromDiskById(removed_id);
             removed = true;
             string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"COALESCE_DROP\"}", removed_id, ticket);
             LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "COALESCE_DROP", fields);
          }
       }
     if(removed)
        Queue_FlushIfDirty(); // Use coalesced flush
     return removed;
  }

int Queue_CancelExpired()
  {
     Queue_EnsureInitialized();
     datetime now = TimeCurrent();
     int dropped = 0;
     for(int i = g_queue_count - 1; i >= 0; i--)
       {
          if(g_queue_buffer[i].expires_at > now)
             continue;
          string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"DROPPED_TTL\"}",
                                       g_queue_buffer[i].id,
                                       g_queue_buffer[i].ticket);
          LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "DROPPED_TTL", fields);
          Queue_RemoveAt(i);
          dropped++;
       }
     if(dropped > 0)
        Queue_FlushIfDirty(); // Use coalesced flush
     return dropped;
  }

bool Queue_CheckNewsWindow(const string symbol,
                           const QueueActionType action_type,
                           string &out_reason_code)
  {
     out_reason_code = "";
     if(action_type == QA_CLOSE)
        return true;
     bool blocked = g_queue_test_overrides.active ? g_queue_test_overrides.news_blocked
                                                  : News_IsModifyBlocked(symbol);
     if(blocked)
     {
        out_reason_code = "NEWS_WINDOW_BLOCK";
        return false;
     }
     return true;
  }

bool Queue_CheckSymbolSession(const string symbol,
                              string &out_reason_code)
  {
     out_reason_code = "";
     if(symbol == "")
        return true;

     if(g_queue_test_overrides.active)
     {
        if(!g_queue_test_overrides.session_ok)
        {
           out_reason_code = "FAIL_SESSION";
           return false;
        }
     }
     else
     {
        bool in_london = Sessions_InLondon(g_ctx, symbol);
        bool in_newyork = Sessions_InNewYork(g_ctx, symbol);
        bool session_ok = (in_london || in_newyork);
        if(!session_ok)
        {
           out_reason_code = "FAIL_SESSION";
           return false;
        }
        if(Sessions_CutoffReached(g_ctx, symbol))
        {
           out_reason_code = "FAIL_SESSION";
           return false;
        }
     }
     return true;
  }

bool Queue_CheckRiskAndCaps(const string symbol,
                            const long ticket,
                            const QueueActionType action_type,
                            const bool is_risk_reducing,
                            string &out_reason_code,
                            bool &out_permanent_failure)
  {
     out_reason_code = "";
     out_permanent_failure = false;

     bool caps_ok = true;
     if(g_queue_test_overrides.active)
     {
        caps_ok = g_queue_test_overrides.caps_ok;
     }
     else
     {
        int total_positions = 0;
        int symbol_positions = 0;
        int symbol_pending = 0;
        caps_ok = Equity_CheckPositionCaps(symbol, total_positions, symbol_positions, symbol_pending);
     }
     if(!caps_ok)
     {
        out_reason_code = "FAIL_CAPS";
        out_permanent_failure = true;
        return false;
     }

     bool floors_ok = g_queue_test_overrides.active ? g_queue_test_overrides.floors_ok
                                                    : Equity_CheckFloors(g_ctx);
     if(!floors_ok && !is_risk_reducing && action_type != QA_CLOSE)
     {
        out_reason_code = "FAIL_FLOOR";
        return false;
     }

     if(!is_risk_reducing)
     {
        bool budget_ok = true;
        if(g_queue_test_overrides.active)
        {
           budget_ok = g_queue_test_overrides.budget_ok;
        }
        else
        {
           EquityBudgetGateResult gate = Equity_EvaluateBudgetGate(g_ctx, 0.0);
           budget_ok = gate.gate_pass;
        }
        if(!budget_ok)
        {
           out_reason_code = "FAIL_BUDGET";
           return false;
        }
     }

     if(!Queue_CheckSymbolSession(symbol, out_reason_code))
     {
        return false;
     }

     out_reason_code = "OK";
     return true;
  }

bool Queue_RevalidateItem(QueuedAction &qa,
                          string &out_reason_code,
                          bool &out_skip_for_news,
                          bool &out_permanent_failure)
  {
     out_permanent_failure = false;
     out_skip_for_news = false;

     bool is_long = true;
     double current_sl = 0.0;
     double current_tp = 0.0;
     double current_price = 0.0;

     bool has_test_position = Queue_Test_GetPosition(qa.ticket,
                                                     is_long,
                                                     current_price,
                                                     current_sl,
                                                     current_tp);

     if(!has_test_position)
     {
        if(!PositionSelectByTicket((ulong)qa.ticket))
        {
           out_reason_code = "APPLY_FAIL_PERMANENT";
           out_permanent_failure = true;
           return false;
        }
        ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        is_long = (pos_type == POSITION_TYPE_BUY);
        current_sl = PositionGetDouble(POSITION_SL);
        current_tp = PositionGetDouble(POSITION_TP);
        current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
     }

     bool risk_reducing = false;
     if(has_test_position && g_queue_test_overrides.active)
     {
        if(qa.action_type == QA_CLOSE)
           risk_reducing = true;
        else if(qa.action_type == QA_SL_MODIFY)
        {
           risk_reducing = (is_long ? (qa.new_sl >= current_sl - 1e-6)
                                    : (qa.new_sl <= current_sl + 1e-6));
        }
     }
     else
     {
        Queue_OrderEngine_IsRiskReducing(qa, current_sl, current_tp, risk_reducing);
     }

     string news_reason = "";
     if(!Queue_CheckNewsWindow(qa.symbol, qa.action_type, news_reason))
     {
        out_skip_for_news = true;
        out_reason_code = news_reason;
        return false;
     }

     if(!Queue_CheckRiskAndCaps(qa.symbol,
                                qa.ticket,
                                qa.action_type,
                                risk_reducing,
                                out_reason_code,
                                out_permanent_failure))
     {
        return false;
     }

     if(qa.action_type == QA_SL_MODIFY)
     {
        double min_stop = Queue_OrderEngine_GetMinStopDistancePoints(qa.symbol);
        double point = SymbolInfoDouble(qa.symbol, SYMBOL_POINT);
        if(min_stop > 0.0 && point > 0.0)
        {
           double distance = MathAbs(qa.new_sl - current_price);
           double min_distance = min_stop * point;
           if(distance < min_distance - 1e-6)
           {
              out_reason_code = "FAIL_CAPS";
              return false;
           }
        }
        if(is_long && qa.new_sl > current_price)
        {
           out_reason_code = "FAIL_CAPS";
           out_permanent_failure = true;
           return false;
        }
        if(!is_long && qa.new_sl < current_price)
        {
          out_reason_code = "FAIL_CAPS";
          out_permanent_failure = true;
          return false;
        }
     }

     out_reason_code = "OK";
     return true;
  }

int Queue_RevalidateAndApply()
  {
     Queue_EnsureInitialized();
     if(g_queue_count <= 0)
        return 0;

     int applied = 0;
     int processed = 0;

     // Process items by priority tiers
     for(int tier = QP_PROTECTIVE_EXIT; tier <= QP_OTHER; tier++)
       {
          for(int i = g_queue_count - 1; i >= 0; i--)
            {
               if(processed >= g_queue_process_batch)
                  break;
               if(g_queue_buffer[i].priority != tier)
                  continue;

               processed++;
               QueuedAction qa = g_queue_buffer[i];
               string reason = "";
               bool skip_for_news = false;
               bool permanent_failure = false;

               if(!Queue_RevalidateItem(qa, reason, skip_for_news, permanent_failure))
               {
                  if(skip_for_news)
                     continue;
                  if(permanent_failure)
                  {
                     string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"%s\"}",
                                                  qa.id, qa.ticket, reason);
                     LogAuditRow("QUEUE", "OrderEngine", LOG_WARN, "APPLY_FAIL_PERMANENT", fields);
                     Queue_RemoveAt(i);
                     Queue_DeleteFromDiskById(qa.id);
                  }
                  else
                  {
                     string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"%s\"}",
                                                  qa.id, qa.ticket, reason);
                     LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, reason, fields);
                  }
                  continue;
               }

               string apply_reason = "";
               bool apply_permanent_failure = false;
               if(Queue_OrderEngine_ApplyAction(qa, apply_reason, apply_permanent_failure))
               {
                  string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"APPLY_OK\"}",
                                               qa.id, qa.ticket);
                  LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "APPLY_OK", fields);
                  Queue_RemoveAt(i);
                  Queue_DeleteFromDiskById(qa.id);
                  applied++;
               }
               else
               {
                  if(apply_permanent_failure)
                  {
                     string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"%s\"}",
                                                  qa.id, qa.ticket, apply_reason);
                     LogAuditRow("QUEUE", "OrderEngine", LOG_WARN, "APPLY_FAIL_PERMANENT", fields);
                     Queue_RemoveAt(i);
                     Queue_DeleteFromDiskById(qa.id);
                  }
                  else
                  {
                     g_queue_buffer[i].retry_count++;
                     string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"retries\":%d,\"reason\":\"APPLY_RETRY\"}",
                                                  qa.id, qa.ticket, g_queue_buffer[i].retry_count);
                     LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "APPLY_RETRY", fields);
                  }
               }
            }
       }

     if(applied > 0)
        Queue_FlushIfDirty(); // Use coalesced flush
     return applied;
  }

int Queue_LoadFromDiskAndReconcile()
  {
     Queue_EnsureInitialized();
     g_queue_count = 0;
     ArrayResize(g_queue_buffer, 0);

     QueuedAction loaded[];
     int loaded_count = 0;
     datetime now = TimeCurrent();
     long max_id = 0;

     int handle = FileOpen(FILE_QUEUE_ACTIONS, FILE_READ|FILE_TXT|FILE_ANSI);
     if(handle != INVALID_HANDLE)
     {
        if(!FileIsEnding(handle))
           FileReadString(handle); // header

        while(!FileIsEnding(handle))
        {
           string line = FileReadString(handle);
           if(StringLen(line) == 0)
              continue;

           string parts[];
           int part_count = StringSplit(line, ',', parts);
           if(part_count < 11)
              continue;
           for(int p = 0; p < part_count; p++)
           {
              StringTrimLeft(parts[p]);
              StringTrimRight(parts[p]);
           }

           QueuedAction qa;
           qa.id = (long)StringToInteger(parts[0]);
           qa.ticket = (long)StringToInteger(parts[1]);
           qa.action_type = (QueueActionType)StringToInteger(parts[2]);
           qa.symbol = parts[3];
           qa.created_at = (datetime)StringToInteger(parts[4]);
           qa.expires_at = (datetime)StringToInteger(parts[5]);
           qa.priority = (QueuePriorityTier)StringToInteger(parts[6]);
           qa.new_sl = StringToDouble(parts[7]);
           qa.new_tp = StringToDouble(parts[8]);
           qa.context_hex = parts[9];
           qa.retry_count = (int)StringToInteger(parts[10]);
           qa.intent_id = (part_count > 11 ? parts[11] : "");
           qa.intent_key = (part_count > 12 ? parts[12] : "");
           Queue_NormalizeAction(qa);

           if(qa.id > max_id)
              max_id = qa.id;

           if(qa.expires_at <= now)
           {
              string drop_fields = StringFormat("{\"queue_id\":%I64d,\"reason\":\"RECONCILE_DROP_EXPIRED\"}", qa.id);
              LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "RECONCILE_DROP_EXPIRED", drop_fields);
              continue;
           }

           int existing = -1;
           for(int j = 0; j < loaded_count; j++)
           {
              if(loaded[j].ticket == qa.ticket && loaded[j].action_type == qa.action_type)
              {
                 existing = j;
                 break;
              }
           }

           if(existing >= 0)
           {
              bool incoming_newer = (qa.created_at >= loaded[existing].created_at);
              if(incoming_newer)
              {
                 string drop_fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"RECONCILE_DROP_REDUNDANT\"}",
                                                  loaded[existing].id,
                                                  loaded[existing].ticket);
                 LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "RECONCILE_DROP_REDUNDANT", drop_fields);
                 loaded[existing] = qa;
              }
              else
              {
                 string drop_fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"RECONCILE_DROP_REDUNDANT\"}",
                                                  qa.id,
                                                  qa.ticket);
                 LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "RECONCILE_DROP_REDUNDANT", drop_fields);
              }
              continue;
           }

           int next = ArraySize(loaded);
           ArrayResize(loaded, next + 1);
           loaded[next] = qa;
           loaded_count++;
        }

        FileClose(handle);
     }

     g_queue_next_id = max_id + 1;

     IntentJournal intent_journal;
     bool have_intent_journal = IntentJournal_Load(intent_journal);

     // Rebuild queue applying live-state reconciliation and backpressure
     for(int i = 0; i < loaded_count; i++)
     {
        QueuedAction qa = loaded[i];

        bool keep = true;
        if(qa.action_type == QA_SL_MODIFY || qa.action_type == QA_TP_MODIFY || qa.action_type == QA_CLOSE)
        {
           bool has_position_data = false;
           double current_sl = 0.0;
           double current_tp = 0.0;

           bool dummy_is_long = true;
           double dummy_price = 0.0;
           if(Queue_Test_GetPosition(qa.ticket, dummy_is_long, dummy_price, current_sl, current_tp))
           {
              has_position_data = true;
           }
           else if(PositionSelectByTicket((ulong)qa.ticket))
           {
              has_position_data = true;
              current_sl = PositionGetDouble(POSITION_SL);
              current_tp = PositionGetDouble(POSITION_TP);
           }

           if(has_position_data)
           {
              const double eps = 1e-6;
              if(qa.action_type == QA_SL_MODIFY && MathAbs(current_sl - qa.new_sl) <= eps)
                 keep = false;
              if(qa.action_type == QA_TP_MODIFY && MathAbs(current_tp - qa.new_tp) <= eps)
                 keep = false;
           }
        }

        if(!keep)
        {
          string drop_fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"RECONCILE_DROP_REDUNDANT\"}",
                                           qa.id,
                                           qa.ticket);
          LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "RECONCILE_DROP_REDUNDANT", drop_fields);
          continue;
        }

        if(have_intent_journal && (StringLen(qa.intent_id) > 0 || StringLen(qa.intent_key) > 0))
        {
           int intent_index = -1;
           if(StringLen(qa.intent_id) > 0)
              intent_index = IntentJournal_FindIntentById(intent_journal, qa.intent_id);
           if(intent_index < 0 && StringLen(qa.intent_key) > 0)
              intent_index = IntentJournal_FindIntentByAcceptKey(intent_journal, qa.intent_key);
           if(intent_index < 0)
           {
              string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"RECONCILE_DROP_INTENT_MISSING\"}",
                                           qa.id,
                                           qa.ticket);
              LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "RECONCILE_DROP_INTENT_MISSING", fields);
              continue;
           }
           else
           {
              OrderIntent matched_intent = intent_journal.intents[intent_index];
              if(StringLen(qa.intent_id) == 0)
                 qa.intent_id = matched_intent.intent_id;
              if(StringLen(qa.intent_key) == 0)
                 qa.intent_key = matched_intent.accept_once_key;
           }
        }

        string reason = "";
        long evicted_id = 0;
        int admit = Queue_AdmitOrBackpressure(qa, reason, evicted_id);
        if(admit < 0)
        {
           string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"%s\"}",
                                        qa.id,
                                        qa.ticket,
                                        reason);
           LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, reason == "" ? "OVERFLOW_REJECT" : reason, fields);
           continue;
        }
        if(admit > 0 && evicted_id > 0)
        {
           string fields = StringFormat("{\"evicted_id\":%I64d,\"reason\":\"%s\"}", evicted_id, reason);
           LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, reason, fields);
        }

        Queue_EnsureCapacity(g_queue_count + 1);
        g_queue_buffer[g_queue_count++] = qa;
     }

     Queue_SaveAll(); // Final save after reconciliation
     
     // M4-Task04: Log structured recovery summary for audit
     int dropped_count = loaded_count - g_queue_count;
     LogAuditRow("QUEUE_RECOVERY_SUMMARY", "Queue", LOG_INFO, "reconcile",
                 StringFormat("{\"queue_loaded\":%d,\"queue_dropped\":%d}", g_queue_count, dropped_count));
     
     return g_queue_count;
  }

#endif // RPEA_QUEUE_MQH
