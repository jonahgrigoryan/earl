// Include guard
#ifndef RPEA_ORDER_ENGINE_MQH
#define RPEA_ORDER_ENGINE_MQH
// order_engine.mqh - Order Engine scaffolding (M3 Task 1)
// References: .kiro/specs/rpea-m3/tasks.md, design.md

#include <Trade\Trade.mqh>
#include <RPEA/config.mqh>
#include <RPEA/app_context.mqh>
#include <RPEA/logging.mqh>
#include <RPEA/persistence.mqh>
#include <RPEA/queue.mqh>
#include <RPEA/trailing.mqh>
#include <RPEA/breakeven.mqh>
#include <RPEA/news.mqh>
#include <RPEA/symbol_bridge.mqh>
#ifndef RPEA_ORDER_ENGINE_SKIP_SESSIONS
// Sessions used for cutoff alignment (read-only helpers)
#include <RPEA/sessions.mqh>
#endif

#ifdef CorrelationFallbackRho
#define OE_CORRELATION_FALLBACK CorrelationFallbackRho
#else
#define OE_CORRELATION_FALLBACK DEFAULT_CorrelationFallbackRho
#endif

static bool   g_order_engine_global_lock = false;
static string g_order_engine_lock_reason = "";

#ifndef CutoffHour
// Default NY cutoff hour used when running in unit-test harness without input bindings
#define CutoffHour 17
#endif

#define OE_INTENT_TTL_MINUTES   1440
#define OE_ACTION_TTL_MINUTES   1440

#ifdef RPEA_TEST_RUNNER
bool OE_Test_Modify(const QueuedAction &qa);
#endif

#ifndef RPEA_ORDER_ENGINE_SKIP_RISK
#include <RPEA/risk.mqh>
#else
double Equity_CalcRiskDollars(const string symbol,
                              const double volume,
                              const double price_entry,
                              const double stop_price,
                              bool &ok);
#endif

#ifndef RPEA_ORDER_ENGINE_SKIP_EQUITY
#include <RPEA/equity_guardian.mqh>
#else
#ifndef EQUITY_GUARDIAN_MQH
struct EquityBudgetGateResult
  {
   bool   approved;
   bool   gate_pass;
   string gating_reason;
   double room_available;
   double room_today;
   double room_overall;
   double open_risk;
   double pending_risk;
   double next_worst_case;
   bool   calculation_error;
  };
#endif
bool Equity_IsPendingOrderType(const int type);
bool Equity_CheckPositionCaps(const string symbol,
                              int &out_total_positions,
                              int &out_symbol_positions,
                              int &out_symbol_pending);
EquityBudgetGateResult Equity_EvaluateBudgetGate(const AppContext& ctx, const double next_trade_worst_case);
#endif

//==============================================================================
// Structs for Order Engine State Management
//==============================================================================

// Order request structure
struct OrderRequest
{
   string   symbol;
   ENUM_ORDER_TYPE type;
   double   volume;
   double   price;
   double   sl;
   double   tp;
   long     magic;
   string   comment;
   bool     is_oco_primary;
   ulong    oco_sibling_ticket;
   datetime expiry;
   string   signal_symbol;
   bool     is_protective;
   bool     is_proxy;
   double   proxy_rate;
   string   proxy_context;
};

// Order result structure
struct OrderResult
{
   bool     success;
   ulong    ticket;
   string   error_message;
   double   executed_price;
   double   executed_volume;
   int      retry_count;
   int      last_retcode;
   string   intent_id;
   string   accept_once_key;
};

enum NewsGateState
  {
   NEWS_GATE_CLEAR = 0,
   NEWS_GATE_BLOCKED,
   NEWS_GATE_PROTECTIVE_ALLOWED
  };

#ifdef RPEA_TEST_RUNNER
extern bool g_test_gate_force_fail;
#endif

// OCO relationship tracking
struct OCORelationship
{
   ulong    primary_ticket;
   ulong    sibling_ticket;
   string   symbol;
   double   primary_volume;
   double   sibling_volume;
   double   primary_volume_original;  // Never modified, baseline for partial fill math (Task 8)
   double   sibling_volume_original;  // Never modified, baseline for partial fill math (Task 8)
   // Original single expiry retained for compatibility; superseded by broker/aligned fields
   datetime expiry;
   // Extended metadata (Task 7)
   datetime expiry_broker;
   datetime expiry_aligned;
   datetime established_time;
   string   establish_reason;
   double   primary_filled;
   double   sibling_filled;
   bool     is_active;
};

// Partial fill tracking (Task 8)
struct PartialFillEvent
{
   double   volume;
   double   sibling_volume_after;
   datetime timestamp;
   ulong    deal_id;
};

struct PartialFillState
{
   ulong             ticket;
   double            requested_volume;
   double            filled_volume;
   double            remaining_volume;
   datetime          first_fill_time;
   datetime          last_fill_time;
   int               fill_count;
   PartialFillEvent  fills[50];
};

struct SLEnforcementEntry
  {
   ulong    ticket;
   datetime open_time;
   datetime sl_set_time;
   bool     sl_set_within_30s;
   string   status;
   bool     active;
  };

//==============================================================================
// Retry Policy Support
//==============================================================================

enum RetryPolicy
{
   RETRY_POLICY_NONE = 0,
   RETRY_POLICY_FAIL_FAST,
   RETRY_POLICY_EXPONENTIAL,
   RETRY_POLICY_LINEAR
};

enum OrderErrorClass
{
   ERRORCLASS_FAILFAST = 0,
   ERRORCLASS_TRANSIENT,
   ERRORCLASS_RECOVERABLE,
   ERRORCLASS_UNKNOWN
};

enum OrderErrorDecisionType
{
   ERROR_DECISION_FAIL_FAST = 0,
   ERROR_DECISION_RETRY,
   ERROR_DECISION_DROP
};

struct OrderError
{
   string           context;
   string           intent_id;
   string           action_id;
   ulong            ticket;
   int              retcode;
   OrderErrorClass  cls;
   int              attempt;
   double           requested_price;
   double           executed_price;
   double           requested_volume;
   bool             is_protective_exit;
   bool             is_retry_candidate;

   OrderError(const int ret = 0)
   {
      context = "";
      intent_id = "";
      action_id = "";
      ticket = 0;
      attempt = 0;
      requested_price = 0.0;
      executed_price = 0.0;
      requested_volume = 0.0;
      is_protective_exit = false;
      is_retry_candidate = true;
      SetRetcode(ret);
   }

   void SetRetcode(const int ret)
   {
      retcode = ret;
      cls = OE_ClassifyRetcode(ret);
   }
};

struct OrderErrorDecision
{
   OrderErrorDecisionType type;
   int                    retry_delay_ms;
   string                 gating_reason;

   OrderErrorDecision()
   {
      type = ERROR_DECISION_DROP;
      retry_delay_ms = 0;
      gating_reason = "";
   }
};

OrderErrorClass OE_ClassifyRetcode(const int retcode);
bool OE_ShouldFailFast(const OrderErrorClass cls);
bool OE_ShouldRetryClass(const OrderErrorClass cls);
string OE_ErrorClassName(const OrderErrorClass cls);

class RetryManager
{
private:
   int     m_max_retries;
   int     m_initial_delay_ms;
   double  m_backoff_multiplier;

public:
   RetryManager()
   {
      m_max_retries = 0;
      m_initial_delay_ms = 0;
      m_backoff_multiplier = 1.0;
   }

   void Configure(const int max_retries,
                  const int initial_delay_ms,
                  const double backoff_multiplier)
   {
      m_max_retries = MathMax(0, max_retries);
      m_initial_delay_ms = MathMax(0, initial_delay_ms);
      m_backoff_multiplier = (backoff_multiplier <= 0.0 ? 1.0 : backoff_multiplier);
   }

   int MaxRetries() const
   {
      return m_max_retries;
   }

   int InitialDelayMs() const
   {
      return m_initial_delay_ms;
   }

   double BackoffMultiplier() const
   {
      return m_backoff_multiplier;
   }

   RetryPolicy GetPolicyForError(const int retcode) const
   {
      switch(retcode)
      {
         case TRADE_RETCODE_TRADE_DISABLED:
         case TRADE_RETCODE_NO_MONEY:
         case TRADE_RETCODE_INVALID_PRICE:
         case TRADE_RETCODE_INVALID_VOLUME:
         case TRADE_RETCODE_POSITION_CLOSED:
            return RETRY_POLICY_FAIL_FAST;

         case TRADE_RETCODE_CONNECTION:
         case TRADE_RETCODE_TIMEOUT:
            return RETRY_POLICY_EXPONENTIAL;

         case TRADE_RETCODE_MARKET_CLOSED:
         case TRADE_RETCODE_REQUOTE:
         case TRADE_RETCODE_PRICE_CHANGED:
         case TRADE_RETCODE_PRICE_OFF:
            return RETRY_POLICY_LINEAR;
      }

      return RETRY_POLICY_FAIL_FAST;
   }

   bool ShouldRetry(const RetryPolicy policy, const int attempt_index) const
   {
      if(policy == RETRY_POLICY_FAIL_FAST || policy == RETRY_POLICY_NONE)
         return false;

      return (attempt_index < m_max_retries);
   }

   int CalculateDelayMs(const int retry_number, const RetryPolicy policy) const
   {
      if(retry_number <= 0 || m_initial_delay_ms <= 0)
         return 0;

      switch(policy)
      {
         case RETRY_POLICY_EXPONENTIAL:
         {
            const double multiplier = MathMax(1.0, m_backoff_multiplier);
            const double scaled = (double)m_initial_delay_ms * MathPow(multiplier, retry_number - 1);
            return (int)MathRound(scaled);
         }
         case RETRY_POLICY_LINEAR:
            return m_initial_delay_ms;
         default:
            break;
      }

      return 0;
   }

   string PolicyName(const RetryPolicy policy) const
   {
      switch(policy)
      {
         case RETRY_POLICY_FAIL_FAST:
            return "FAIL_FAST";
         case RETRY_POLICY_EXPONENTIAL:
            return "EXPONENTIAL";
         case RETRY_POLICY_LINEAR:
            return "LINEAR";
      }
      return "UNKNOWN";
   }
};

OrderErrorClass OE_ClassifyRetcode(const int retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_TRADE_DISABLED:
      case TRADE_RETCODE_MARKET_CLOSED:
      case TRADE_RETCODE_NO_MONEY:
         return ERRORCLASS_FAILFAST;

      case TRADE_RETCODE_CONNECTION:
      case TRADE_RETCODE_TIMEOUT:
         return ERRORCLASS_TRANSIENT;

      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_INVALID_PRICE:
         return ERRORCLASS_RECOVERABLE;
   }
   return ERRORCLASS_UNKNOWN;
}

bool OE_ShouldFailFast(const OrderErrorClass cls)
{
   return (cls == ERRORCLASS_FAILFAST);
}

bool OE_ShouldRetryClass(const OrderErrorClass cls)
{
   return (cls == ERRORCLASS_TRANSIENT || cls == ERRORCLASS_RECOVERABLE);
}

string OE_ErrorClassName(const OrderErrorClass cls)
{
   switch(cls)
   {
      case ERRORCLASS_FAILFAST: return "FAIL_FAST";
      case ERRORCLASS_TRANSIENT: return "TRANSIENT";
      case ERRORCLASS_RECOVERABLE: return "RECOVERABLE";
   }
   return "UNKNOWN";
}

bool OE_OrderSend(const MqlTradeRequest &request, MqlTradeResult &result);
void OE_ApplyRetryDelay(const int delay_ms);
bool OE_GetLatestQuote(const string context,
                       const string symbol,
                       double &out_point,
                       int &out_digits,
                       double &out_bid,
                       double &out_ask);

//------------------------------------------------------------------------------
// Cancel/Modify override & decision capture for deterministic testing (Task 7)
//------------------------------------------------------------------------------

struct OECancelCapture
{
   ulong    ticket;
   datetime ts;
   string   reason;
};

struct OEModifyCapture
{
   ulong    ticket;
   double   new_volume;
   datetime ts;
   string   reason;
};

struct OECancelModifyOverrideState
{
   bool              active;
   bool              force_cancel_fail;
   bool              force_modify_ok;
   OECancelCapture   cancels[];
   OEModifyCapture   modifies[];
};

static OECancelModifyOverrideState g_oe_cancel_modify_override;

void OE_Test_EnableCancelModifyOverride()
{
   g_oe_cancel_modify_override.active = true;
   g_oe_cancel_modify_override.force_cancel_fail = false;
   g_oe_cancel_modify_override.force_modify_ok = true;
   ArrayResize(g_oe_cancel_modify_override.cancels, 0);
   ArrayResize(g_oe_cancel_modify_override.modifies, 0);
}

void OE_Test_DisableCancelModifyOverride()
{
   g_oe_cancel_modify_override.active = false;
   g_oe_cancel_modify_override.force_cancel_fail = false;
   g_oe_cancel_modify_override.force_modify_ok = false;
   ArrayResize(g_oe_cancel_modify_override.cancels, 0);
   ArrayResize(g_oe_cancel_modify_override.modifies, 0);
}

void OE_Test_ForceCancelFail(const bool value)
{
   g_oe_cancel_modify_override.force_cancel_fail = value;
}

void OE_Test_ForceModifyOk(const bool value)
{
   g_oe_cancel_modify_override.force_modify_ok = value;
}

int OE_Test_GetCapturedCancelCount()
{
   return ArraySize(g_oe_cancel_modify_override.cancels);
}

bool OE_Test_GetCapturedCancel(const int index, ulong &out_ticket, datetime &out_ts, string &out_reason)
{
   int n = ArraySize(g_oe_cancel_modify_override.cancels);
   if(index < 0 || index >= n)
      return false;
   out_ticket = g_oe_cancel_modify_override.cancels[index].ticket;
   out_ts = g_oe_cancel_modify_override.cancels[index].ts;
   out_reason = g_oe_cancel_modify_override.cancels[index].reason;
   return true;
}

int OE_Test_GetCapturedModifyCount()
{
   return ArraySize(g_oe_cancel_modify_override.modifies);
}

bool OE_Test_GetCapturedModify(const int index, ulong &out_ticket, double &out_new_volume, datetime &out_ts, string &out_reason)
{
   int n = ArraySize(g_oe_cancel_modify_override.modifies);
   if(index < 0 || index >= n)
      return false;
   out_ticket = g_oe_cancel_modify_override.modifies[index].ticket;
   out_new_volume = g_oe_cancel_modify_override.modifies[index].new_volume;
   out_ts = g_oe_cancel_modify_override.modifies[index].ts;
   out_reason = g_oe_cancel_modify_override.modifies[index].reason;
   return true;
}

// Decision capture (duplicates LogDecision entries for OCO events)
struct OEDecisionEntry
{
   string   event;
   string   json;
   datetime ts;
};

struct OEDecisionCaptureState
{
   bool            active;
   OEDecisionEntry entries[];
};

static OEDecisionCaptureState g_oe_decision_capture;

void OE_Test_EnableDecisionCapture()
{
   g_oe_decision_capture.active = true;
   ArrayResize(g_oe_decision_capture.entries, 0);
}

void OE_Test_DisableDecisionCapture()
{
   g_oe_decision_capture.active = false;
   ArrayResize(g_oe_decision_capture.entries, 0);
}

void OE_Test_CaptureDecision(const string event, const string fields)
{
   if(!g_oe_decision_capture.active)
      return;
   int idx = ArraySize(g_oe_decision_capture.entries);
   ArrayResize(g_oe_decision_capture.entries, idx + 1);
   g_oe_decision_capture.entries[idx].event = event;
   g_oe_decision_capture.entries[idx].json = fields;
   g_oe_decision_capture.entries[idx].ts = TimeCurrent();
}

int OE_Test_GetCapturedDecisionCount()
{
   return ArraySize(g_oe_decision_capture.entries);
}

bool OE_Test_GetCapturedDecision(const int index, string &out_event, string &out_json, datetime &out_ts)
{
   int n = ArraySize(g_oe_decision_capture.entries);
   if(index < 0 || index >= n)
      return false;
   out_event = g_oe_decision_capture.entries[index].event;
   out_json = g_oe_decision_capture.entries[index].json;
   out_ts = g_oe_decision_capture.entries[index].ts;
   return true;
}

// Helpers to perform cancel/modify, honoring test overrides
bool OE_RequestCancel(const ulong order_ticket, const string reason)
{
   if(g_oe_cancel_modify_override.active)
   {
      int idx = ArraySize(g_oe_cancel_modify_override.cancels);
      ArrayResize(g_oe_cancel_modify_override.cancels, idx + 1);
      g_oe_cancel_modify_override.cancels[idx].ticket = order_ticket;
      g_oe_cancel_modify_override.cancels[idx].ts = TimeCurrent();
      g_oe_cancel_modify_override.cancels[idx].reason = reason;
      return (!g_oe_cancel_modify_override.force_cancel_fail);
   }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_REMOVE;
   req.order  = order_ticket;
   return OE_OrderSend(req, res);
}

bool OE_RequestModifyVolume(const ulong order_ticket, const double new_volume, const string reason)
{
   if(g_oe_cancel_modify_override.active)
   {
      int idx = ArraySize(g_oe_cancel_modify_override.modifies);
      ArrayResize(g_oe_cancel_modify_override.modifies, idx + 1);
      g_oe_cancel_modify_override.modifies[idx].ticket = order_ticket;
      g_oe_cancel_modify_override.modifies[idx].new_volume = new_volume;
      g_oe_cancel_modify_override.modifies[idx].ts = TimeCurrent();
      g_oe_cancel_modify_override.modifies[idx].reason = reason;
      return (g_oe_cancel_modify_override.force_modify_ok);
   }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_MODIFY;
   req.order  = order_ticket;
   req.volume = new_volume;
   return OE_OrderSend(req, res);
}

//==============================================================================
// OrderEngine Class
//==============================================================================
class OrderEngine
{
private:
   // State management
    OCORelationship m_oco_relationships[];
    int             m_oco_count;
    bool            m_execution_locked;
    int             m_consecutive_failures;
    int             m_failure_window_count;
    datetime        m_failure_window_start;
    datetime        m_last_failure_time;
    datetime        m_circuit_breaker_until;
    string          m_breaker_reason;
    datetime        m_last_alert_time;
    bool            m_self_heal_active;
    int             m_self_heal_attempts;
    string          m_self_heal_reason;
    datetime        m_next_self_heal_time;
   
   // Configuration (from inputs)
   int             m_max_retry_attempts;
   int             m_initial_retry_delay_ms;
   double          m_retry_backoff_multiplier;
   double          m_max_slippage_points;
   int             m_min_hold_seconds;
   bool            m_enable_execution_lock;
   int             m_pending_expiry_grace_seconds;
   bool            m_auto_cancel_oco_sibling;
   int             m_oco_cancellation_timeout_ms;
   bool            m_enable_risk_reduction_sibling_cancel;
   bool            m_enable_detailed_logging;
   int             m_log_buffer_size;
   int             m_resilience_max_failures;
   int             m_resilience_failure_window_sec;
   int             m_resilience_breaker_cooldown_sec;
   int             m_resilience_self_heal_window_sec;
   int             m_resilience_self_heal_max_attempts;
   int             m_resilience_alert_throttle_sec;
   bool            m_resilience_protective_bypass;
   string          m_log_buffer[];
   int             m_log_buffer_count;
   bool            m_log_buffer_dirty;
   RetryManager    m_retry_manager;
   IntentJournal   m_intent_journal;
   bool            m_intent_journal_dirty;
   int             m_intent_sequence;
   int             m_action_sequence;
   
   // Partial fill tracking (Task 8)
   PartialFillState m_partial_fill_states[];
   int              m_partial_fill_count;
   SLEnforcementEntry m_sl_enforcement_queue[];
   int                m_sl_enforcement_count;
   bool               m_sl_state_loaded;
   OrderIntent        m_recovered_intents[];
   int                m_recovered_intent_count;
   PersistedQueuedAction m_recovered_actions[];
   int                m_recovered_action_count;
   bool               m_recovery_completed;
   datetime           m_recovery_timestamp;

   // Helper methods
   void LogOE(const string message)
   {
      if(m_enable_detailed_logging)
      {
         string formatted = FormatLogLine(message);
         AppendLogLine(formatted);
         PrintFormat("[OrderEngine] %s", message);
      }
   }
   
   int FindOCORelationship(const ulong ticket)
   {
      for(int i = 0; i < m_oco_count; i++)
      {
         if(m_oco_relationships[i].primary_ticket == ticket || 
            m_oco_relationships[i].sibling_ticket == ticket)
         {
            return i;
         }
      }
      return -1;
   }
   
   bool IsMarketOrderType(const ENUM_ORDER_TYPE type);
   bool IsPendingOrderType(const ENUM_ORDER_TYPE type);
   bool EvaluatePositionCaps(const OrderRequest &request,
                             const bool is_pending_request,
                             int &out_total_positions,
                             int &out_symbol_positions,
                             int &out_symbol_pending,
                             string &out_violation_reason);
   bool ValidateRiskConstraints(const OrderRequest &request,
                                const double entry_price,
                                const bool is_pending,
                                double &out_evaluated_risk,
                                EquityBudgetGateResult &out_gate,
                                string &out_rejection_reason);
   NewsGateState EvaluateNewsGate(const string signal_symbol,
                                  const bool is_protective_exit,
                                  string &out_detail) const;
   bool ExecuteOrderWithRetry(const OrderRequest &request,
                              const bool is_pending_request,
                              const double evaluated_risk,
                              const int projected_total_positions,
                              const int projected_symbol_positions,
                              const int projected_symbol_pending,
                              OrderResult &result);
   bool IsBuyDirection(const ENUM_ORDER_TYPE type) const;
   ENUM_ORDER_TYPE MarketTypeFromPending(const ENUM_ORDER_TYPE type) const;
   bool ShouldFallbackToMarket(const int retcode) const;
   bool ExecuteMarketFallback(const OrderRequest &pending_request,
                              const double evaluated_risk,
                              OrderResult &result);
   void AppendLogLine(const string line);
   void FlushLogBuffer();
   void PersistIntentJournal();
   void LoadIntentJournal();
   void ResetState();
   string FormatLogLine(const string message);
   string GenerateIntentId(const datetime now);
   string BuildIntentAcceptKey(const OrderRequest &request) const;
   ulong  HashString64(const string text) const;
   string HashToHex(const ulong value) const;
   bool   IntentExists(const string accept_key, int &out_index) const;
   void   Audit_LogIntentEvent(const OrderIntent &intent,
                               const string action_suffix,
                               const string decision,
                               const double requested_price,
                               const double executed_price,
                               const double requested_vol,
                               const double filled_vol,
                               const double remaining_vol,
                               const int retry_count,
                               const string gating_reason_override = "",
                               const string news_state_override = "");
   bool   FindIntentByTicket(const ulong ticket,
                             string &out_intent_id,
                             string &out_accept_key) const;
   // Partial fill state helpers (Task 8)
   int    FindPartialFillState(const ulong ticket) const;
   int    FindOrCreatePartialFillState(const ulong ticket, const double requested_volume);
   void   ClearPartialFillState(const int index);
   void   ClearPartialFillStateByTicket(const ulong ticket);
   void   CleanupExpiredJournalEntries(const datetime now);
   void   MarkJournalDirty();
   void   TouchJournalSequences();
   void   TrackSLEnforcement(const ulong ticket, const datetime open_time);
   void   EnsureSLEnforcementLoaded();
   void   CheckPendingSLEnforcementInternal();
   bool   IsMasterAccount() const;
   void   RemoveSLEnforcementAt(const int index);
   bool   GetPositionSLByTicket(const ulong ticket, double &out_sl, datetime &out_open_time) const;
   bool   ClearOCOByIndex(const int idx)
   {
      if(idx < 0 || idx >= m_oco_count)
         return false;
      // Clear partial fill states for both tickets (Task 8)
      ClearPartialFillStateByTicket(m_oco_relationships[idx].primary_ticket);
      ClearPartialFillStateByTicket(m_oco_relationships[idx].sibling_ticket);
      // Mark inactive and compact
      m_oco_relationships[idx].is_active = false;
      int last = m_oco_count - 1;
      if(idx != last)
         m_oco_relationships[idx] = m_oco_relationships[last];
      m_oco_count = MathMax(0, m_oco_count - 1);
      return true;
   }
   void   LoadResilienceConfig();
   void   RestoreEngineStateFromJournal();
   void   SyncEngineStateToJournal();
   OrderErrorDecision OrderEngine_HandleError(const OrderError &err);
   void   OrderEngine_RecordFailure(const datetime now);
   void   OrderEngine_RecordSuccess();
   void   OrderEngine_TripCircuitBreaker(const string reason);
   void   OrderEngine_ResetCircuitBreaker(const string source);
   bool   OrderEngine_IsCircuitBreakerActive();
   bool   OrderEngine_ShouldBypassBreaker(const OrderError &err) const;
   bool   OrderEngine_ShouldBypassBreaker(const bool protective) const;
   void   OrderEngine_LogErrorHandling(const OrderError &err, const OrderErrorDecision &decision);
   void   OrderEngine_ScheduleSelfHeal(const string reason);

   // Session cutoff override (tests)
   bool     m_cutoff_override_active;
   datetime m_cutoff_override;

   // DEAL dedupe (Task 7)
   ulong    m_oco_handled_deals[];
   int      m_oco_handled_deals_count;

   bool OCO_IsDealHandled(const ulong deal_ticket)
   {
      for(int i=0;i<m_oco_handled_deals_count;i++)
      {
         if(m_oco_handled_deals[i] == deal_ticket)
            return true;
      }
      return false;
   }

   // ORDER_ADD pairing (Task 7)
   struct OCOPendingLink
   {
      string   symbol;
      bool     has_primary;
      ulong    primary_ticket;
      double   primary_volume;
      datetime primary_expiry;
      bool     has_sibling;
      ulong    sibling_ticket;
      double   sibling_volume;
      datetime sibling_expiry;
   };

   OCOPendingLink m_oco_pending_links[];
   int            m_oco_pending_count;

   int OCO_FindPendingForSymbol(const string symbol)
   {
      for(int i=0;i<m_oco_pending_count;i++)
      {
         if(m_oco_pending_links[i].symbol == symbol && (!m_oco_pending_links[i].has_primary || !m_oco_pending_links[i].has_sibling))
            return i;
      }
      return -1;
   }

   void OCO_ClearPendingAt(const int idx)
   {
      if(idx < 0 || idx >= m_oco_pending_count)
         return;
      int last = m_oco_pending_count - 1;
      if(idx != last)
         m_oco_pending_links[idx] = m_oco_pending_links[last];
      m_oco_pending_count = MathMax(0, m_oco_pending_count - 1);
   }

   void OCO_UpdateIntentSiblingIds(const string symbol)
   {
      // Find last two intents for symbol with blank oco_sibling_id
      int last_idx = -1, prev_idx = -1;
      for(int i = ArraySize(m_intent_journal.intents) - 1; i >= 0; i--)
      {
         if(m_intent_journal.intents[i].symbol == symbol && m_intent_journal.intents[i].oco_sibling_id == "")
         {
            if(last_idx < 0)
               last_idx = i;
            else { prev_idx = i; break; }
         }
      }
      if(last_idx >= 0 && prev_idx >= 0)
      {
         string id_a = m_intent_journal.intents[last_idx].intent_id;
         string id_b = m_intent_journal.intents[prev_idx].intent_id;
         m_intent_journal.intents[last_idx].oco_sibling_id = id_b;
         m_intent_journal.intents[prev_idx].oco_sibling_id = id_a;
         MarkJournalDirty();
         PersistIntentJournal();
      }
   }

   void OCO_MarkDealHandled(const ulong deal_ticket)
   {
      if(m_oco_handled_deals_count >= ArraySize(m_oco_handled_deals))
         ArrayResize(m_oco_handled_deals, m_oco_handled_deals_count + 16);
      m_oco_handled_deals[m_oco_handled_deals_count++] = deal_ticket;
   }

   datetime GetSessionCutoffAligned(const string symbol, const datetime now) const
   {
      if(symbol == "")
      {
         // symbol unused guard
      }
      if(m_cutoff_override_active)
         return m_cutoff_override;
#ifndef RPEA_ORDER_ENGINE_SKIP_SESSIONS
      // Align to the configured session cutoff hour using helper
      datetime cutoff = Sessions_AnchorForHour(now, CutoffHour);
#else
      // Manual alignment at CutoffHour when sessions module is skipped (unit tests)
      MqlDateTime tm;
      TimeToStruct(now, tm);
      tm.hour = CutoffHour;
      tm.min = 0;
      tm.sec = 0;
      datetime cutoff = StructToTime(tm);
#endif
      if(cutoff <= now)
         cutoff += 24*60*60;
      return cutoff;
   }

public:
   bool GetIntentMetadata(const ulong ticket,
                          string &out_intent_id,
                          string &out_accept_key) const
   {
      return FindIntentByTicket(ticket, out_intent_id, out_accept_key);
   }
   bool FindIntentById(const string intent_id, OrderIntent &out_intent) const;
   int  FindIntentIndexById(const string intent_id) const;
   bool MatchIntentByTicket(const ulong ticket, OrderIntent &out_intent) const;

   void LoadSLEnforcementState()
   {
      EnsureSLEnforcementLoaded();
   }

   void SaveSLEnforcementState() const
   {
      if(!m_sl_state_loaded)
         return;
      string rows[];
      int active_count = 0;
      for(int i = 0; i < m_sl_enforcement_count; i++)
      {
         if(!m_sl_enforcement_queue[i].active)
            continue;
         active_count++;
      }
      ArrayResize(rows, active_count);
      int cursor = 0;
      for(int i = 0; i < m_sl_enforcement_count; i++)
      {
         if(!m_sl_enforcement_queue[i].active)
            continue;
         SLEnforcementEntry entry = m_sl_enforcement_queue[i];
         string open_iso = Persistence_FormatIso8601(entry.open_time);
         string sl_iso = (entry.sl_set_time > 0 ? Persistence_FormatIso8601(entry.sl_set_time) : "");
         rows[cursor++] = StringFormat("{\"ticket\":%llu,\"open_time\":\"%s\",\"sl_set_time\":\"%s\",\"status\":\"%s\",\"sl_set_within_30s\":\"%s\"}",
                                       entry.ticket,
                                       open_iso,
                                       sl_iso,
                                       entry.status,
                                       entry.sl_set_within_30s ? "true" : "false");
      }
      string payload = "[";
      for(int i = 0; i < ArraySize(rows); i++)
      {
         if(i > 0)
            payload += ",";
         payload += rows[i];
      }
      payload += "]";
      Persistence_WriteWholeFile(FILE_SL_ENFORCEMENT, payload);
   }

   void CheckPendingSLEnforcement()
   {
      CheckPendingSLEnforcementInternal();
   }
   
   // Constructor
   OrderEngine()
   {
      m_oco_count = 0;
      m_execution_locked = false;
      m_consecutive_failures = 0;
      m_failure_window_count = 0;
      m_failure_window_start = (datetime)0;
      m_last_failure_time = (datetime)0;
      m_circuit_breaker_until = (datetime)0;
      m_breaker_reason = "";
      m_last_alert_time = (datetime)0;
      m_self_heal_active = false;
      m_self_heal_attempts = 0;
      m_self_heal_reason = "";
      m_next_self_heal_time = (datetime)0;
      
      // Initialize with defaults from config.mqh
      m_max_retry_attempts = DEFAULT_MaxRetryAttempts;
      m_initial_retry_delay_ms = DEFAULT_InitialRetryDelayMs;
      m_retry_backoff_multiplier = DEFAULT_RetryBackoffMultiplier;
      m_max_slippage_points = DEFAULT_MaxSlippagePoints;
      m_min_hold_seconds = DEFAULT_MinHoldSeconds;
      m_enable_execution_lock = DEFAULT_EnableExecutionLock;
      m_pending_expiry_grace_seconds = DEFAULT_PendingExpiryGraceSeconds;
      m_auto_cancel_oco_sibling = DEFAULT_AutoCancelOCOSibling;
      m_oco_cancellation_timeout_ms = DEFAULT_OCOCancellationTimeoutMs;
      m_enable_risk_reduction_sibling_cancel = DEFAULT_EnableRiskReductionSiblingCancel;
      m_enable_detailed_logging = DEFAULT_EnableDetailedLogging;
      m_log_buffer_size = DEFAULT_LogBufferSize;
      m_resilience_max_failures = DEFAULT_MaxConsecutiveFailures;
      m_resilience_failure_window_sec = DEFAULT_FailureWindowSec;
      m_resilience_breaker_cooldown_sec = DEFAULT_CircuitBreakerCooldownSec;
      m_resilience_self_heal_window_sec = DEFAULT_SelfHealRetryWindowSec;
      m_resilience_self_heal_max_attempts = DEFAULT_SelfHealMaxAttempts;
      m_resilience_alert_throttle_sec = DEFAULT_ErrorAlertThrottleSec;
      m_resilience_protective_bypass = DEFAULT_BreakerProtectiveExitBypass;
      m_log_buffer_count = 0;
      m_log_buffer_dirty = false;
      m_retry_manager.Configure(m_max_retry_attempts,
                                m_initial_retry_delay_ms,
                                m_retry_backoff_multiplier);
      IntentJournal_Clear(m_intent_journal);
      m_intent_journal_dirty = false;
      m_intent_sequence = 0;
      m_action_sequence = 0;
      
      ArrayResize(m_oco_relationships, 100);
     m_cutoff_override_active = false;
     m_cutoff_override = 0;
     ArrayResize(m_oco_handled_deals, 32);
     m_oco_handled_deals_count = 0;
     m_recovered_intent_count = 0;
     m_recovered_action_count = 0;
     m_recovery_completed = false;
     m_recovery_timestamp = 0;
   }
   
   // Destructor
   ~OrderEngine()
   {
      ArrayFree(m_oco_relationships);
      ArrayFree(m_log_buffer);
      m_log_buffer_count = 0;
      m_log_buffer_dirty = false;
   }

   bool BreakerBlocksAction(const bool is_protective)
   {
      return (!OrderEngine_ShouldBypassBreaker(is_protective) && OrderEngine_IsCircuitBreakerActive());
   }

   OrderErrorDecision ResilienceHandleError(const OrderError &err)
   {
      return OrderEngine_HandleError(err);
   }

   void ResilienceRecordSuccess()
   {
      OrderEngine_RecordSuccess();
   }

   void TestResetResilienceState()
   {
      m_consecutive_failures = 0;
      m_failure_window_count = 0;
      m_failure_window_start = (datetime)0;
      m_last_failure_time = (datetime)0;
      m_circuit_breaker_until = (datetime)0;
      m_breaker_reason = "";
      m_last_alert_time = (datetime)0;
      m_self_heal_active = false;
      m_self_heal_attempts = 0;
      m_self_heal_reason = "";
      m_next_self_heal_time = (datetime)0;
   }

   int GetConsecutiveFailures() const { return m_consecutive_failures; }
   int GetFailureWindowCount() const { return m_failure_window_count; }
   datetime GetBreakerUntil() const { return m_circuit_breaker_until; }
   string GetBreakerReason() const { return m_breaker_reason; }
   bool IsSelfHealActive() const { return m_self_heal_active; }
   int GetSelfHealAttempts() const { return m_self_heal_attempts; }
   datetime GetNextSelfHealTime() const { return m_next_self_heal_time; }
   
   //===========================================================================
   // Initialization and Lifecycle Methods
   //===========================================================================
   
   bool Init()
   {
      LogOE("OrderEngine::Init() - Initializing Order Engine");
      ResetState();
      LoadResilienceConfig();
      // Initialize partial fill tracking (Task 8)
      m_partial_fill_count = 0;
      ArrayResize(m_partial_fill_states, 100);
      m_log_buffer_count = 0;
      m_log_buffer_dirty = false;
      ArrayResize(m_log_buffer, 0);
      m_retry_manager.Configure(m_max_retry_attempts,
                                m_initial_retry_delay_ms,
                                m_retry_backoff_multiplier);
      LoadIntentJournal();
      RestoreEngineStateFromJournal();
      CleanupExpiredJournalEntries(TimeCurrent());
      PersistIntentJournal();
      LogOE("OrderEngine::Init() - Initialization complete");
      return true;
   }
   
   void OnShutdown()
   {
      LogOE("OrderEngine::OnShutdown() - Flushing state and logs");
      
      // Log final state
      LogOE(StringFormat("OrderEngine::OnShutdown() - Active OCO relationships: %d", m_oco_count));
      LogOE("OrderEngine::OnShutdown() - Shutdown complete");

      PersistIntentJournal();
      FlushLogBuffer();
      SaveSLEnforcementState();
      ResetState();
      m_log_buffer_count = 0;
      m_log_buffer_dirty = false;
      ArrayResize(m_log_buffer, 0);
   }

   // Test support helper: clear journal state between automated test cases.
   void TestResetIntentJournal()
   {
      IntentJournal_Clear(m_intent_journal);
      m_intent_sequence = 0;
      m_action_sequence = 0;
      m_intent_journal_dirty = true;
      PersistIntentJournal();
   }

   bool TestIsRecoveryComplete() const
   {
      return m_recovery_completed;
   }

   int TestRecoveredIntentCount() const
   {
      return m_recovered_intent_count;
   }

   //===========================================================================
   // Test shims (expose internals for unit tests)
   //===========================================================================

   void OE_Test_SetSessionCutoff(const datetime cutoff)
   {
      m_cutoff_override_active = true;
      m_cutoff_override = cutoff;
   }

   void OE_Test_ClearSessionCutoff()
   {
      m_cutoff_override_active = false;
      m_cutoff_override = 0;
   }

   bool OE_Test_EstablishOCO(const ulong primary_ticket,
                             const ulong sibling_ticket,
                             const string symbol,
                             const double primary_volume,
                             const double sibling_volume,
                             const datetime expiry)
   {
      return EstablishOCO(primary_ticket, sibling_ticket, symbol, primary_volume, sibling_volume, expiry);
   }

  bool OE_Test_ProcessOCOFill(const ulong filled_ticket,
                              const double explicit_deal_volume = -1.0,
                              const ulong deal_id = 0)
  {
     return ProcessOCOFill(filled_ticket, explicit_deal_volume, deal_id);
  }
   
   //===========================================================================
   // Event Handlers
   //===========================================================================
   
   void OnTradeTxn(const MqlTradeTransaction& trans,
                   const MqlTradeRequest& request,
                   const MqlTradeResult& result)
   {
      // Process transaction immediately before timer housekeeping
      // Critical: Fills/partial fills processed here for OCO sibling adjustments
      
      if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      {
         LogOE(StringFormat("OnTradeTxn: DEAL_ADD deal=%llu order=%llu", trans.deal, trans.order));
         // Dedupe repeated DEAL_ADD
         if(!OCO_IsDealHandled(trans.deal))
         {
            OCO_MarkDealHandled(trans.deal);
            double vol = 0.0;
            if(trans.deal > 0 && HistoryDealSelect(trans.deal))
               vol = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
            // Process OCO sibling handling for fills/partials with real deal volume when available
            ProcessOCOFill(trans.order, vol, trans.deal);
         }
      }
      else if(trans.type == TRADE_TRANSACTION_ORDER_ADD)
      {
         LogOE(StringFormat("OnTradeTxn: ORDER_ADD order=%llu", trans.order));
         // Attach ORDER_ADD tickets into pairing map and call EstablishOCO when both legs are present
         string sym = Symbol();
         double ord_volume = 0.0;
         datetime ord_expiry = 0;
         // Try to fetch order details (if available) to capture true volume/expiry
        if(OrderSelect((ulong)trans.order))
         {
            sym = OrderGetString(ORDER_SYMBOL);
            ord_volume = OrderGetDouble(ORDER_VOLUME_INITIAL);
            ord_expiry = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
         }
         int pidx = OCO_FindPendingForSymbol(sym);
         if(pidx < 0)
         {
            if(m_oco_pending_count >= ArraySize(m_oco_pending_links))
               ArrayResize(m_oco_pending_links, m_oco_pending_count + 8);
            pidx = m_oco_pending_count++;
            m_oco_pending_links[pidx].symbol = sym;
            m_oco_pending_links[pidx].has_primary = true;
            m_oco_pending_links[pidx].primary_ticket = trans.order;
            m_oco_pending_links[pidx].primary_volume = ord_volume;
            m_oco_pending_links[pidx].primary_expiry = (ord_expiry > 0 ? ord_expiry : (TimeCurrent() + m_pending_expiry_grace_seconds));
            m_oco_pending_links[pidx].has_sibling = false;
         }
         else
         {
            if(!m_oco_pending_links[pidx].has_primary)
            {
               m_oco_pending_links[pidx].has_primary = true;
               m_oco_pending_links[pidx].primary_ticket = trans.order;
               m_oco_pending_links[pidx].primary_volume = ord_volume;
               m_oco_pending_links[pidx].primary_expiry = (ord_expiry > 0 ? ord_expiry : (TimeCurrent() + m_pending_expiry_grace_seconds));
            }
            else if(!m_oco_pending_links[pidx].has_sibling)
            {
               m_oco_pending_links[pidx].has_sibling = true;
               m_oco_pending_links[pidx].sibling_ticket = trans.order;
               m_oco_pending_links[pidx].sibling_volume = ord_volume;
               m_oco_pending_links[pidx].sibling_expiry = (ord_expiry > 0 ? ord_expiry : (TimeCurrent() + m_pending_expiry_grace_seconds));
               // Establish when both present
               EstablishOCO(m_oco_pending_links[pidx].primary_ticket,
                            m_oco_pending_links[pidx].sibling_ticket,
                            sym,
                            MathMax(0.0, m_oco_pending_links[pidx].primary_volume),
                            MathMax(0.0, m_oco_pending_links[pidx].sibling_volume),
                            (m_oco_pending_links[pidx].primary_expiry > 0 ? m_oco_pending_links[pidx].primary_expiry : m_oco_pending_links[pidx].sibling_expiry));
               // Update intent journal sibling ids
               OCO_UpdateIntentSiblingIds(sym);
               OCO_ClearPendingAt(pidx);
            }
         }
      }
      else if(trans.type == TRADE_TRANSACTION_ORDER_DELETE)
      {
         LogOE(StringFormat("OnTradeTxn: ORDER_DELETE order=%llu", trans.order));
         // TODO[M3-Task7]: Clean up OCO relationship if applicable
      }
      else if(trans.type == TRADE_TRANSACTION_ORDER_UPDATE)
      {
         LogOE(StringFormat("OnTradeTxn: ORDER_UPDATE order=%llu", trans.order));
      }
   }
   
   void OnTimerTick(const datetime now)
   {
      // Housekeeping tasks - runs after OnTradeTransaction processing
      // OCO expiry cleanup
      for(int i = 0; i < m_oco_count; )
      {
         if(!m_oco_relationships[i].is_active)
         {
            ClearOCOByIndex(i);
            continue;
         }
         if(now >= m_oco_relationships[i].expiry_aligned)
         {
            string fields = StringFormat("{\"primary_ticket\":%llu,\"sibling_ticket\":%llu,\"expiry_aligned\":\"%s\"}",
                                         m_oco_relationships[i].primary_ticket,
                                         m_oco_relationships[i].sibling_ticket,
                                         TimeToString(m_oco_relationships[i].expiry_aligned));
            LogDecision("OrderEngine", "OCO_EXPIRE", fields);
            OE_Test_CaptureDecision("OCO_EXPIRE", fields);
            // Best effort cancel sibling
            OE_RequestCancel(m_oco_relationships[i].sibling_ticket, "oco_expiry");
            ClearOCOByIndex(i);
            continue;
         }
         i++;
      }
   }
   
   void OnTick()
   {
      // Tick event handler - called on every price tick
      // Can be used for lightweight price monitoring and validation
      
      // TODO[M3-Task13]: Monitor trailing stop conditions on every tick
      // TODO[M3-Task6]: Check slippage and price validation for pending orders
      // TODO[M3-Task12]: Check if news window ended and queued actions ready
      
      // For now, this is a stub - most processing happens in OnTimer for efficiency
   }
   
   //===========================================================================
   // Order Placement Methods (Stubs for M3 Tasks 4-6)
   //===========================================================================
   
   OrderResult PlaceOrder(const OrderRequest& request)
   {
      OrderResult result;
      result.success = false;
      result.ticket = 0;
      result.error_message = "";
      result.executed_price = 0.0;
      result.executed_volume = 0.0;
      result.retry_count = 0;
      result.last_retcode = 0;
      result.intent_id = "";
      result.accept_once_key = "";
      int intent_index = -1;
      string intent_id = "";
      string accept_key = "";
      bool intent_created = false;
      datetime intent_time = 0;
      string news_state_detail = "CLEAR";
      
      LogOE(StringFormat("PlaceOrder: %s %s vol=%.2f price=%.5f sl=%.5f tp=%.5f",
            request.symbol, EnumToString(request.type), request.volume, 
            request.price, request.sl, request.tp));
      
      // Retry policy handled via ExecuteOrderWithRetry (Task 5)
      // TODO[M3-Task6]: Market fallback with slippage protection

      const bool is_pending = IsPendingOrderType(request.type);
      const bool is_market = IsMarketOrderType(request.type);
      const string mode = is_pending ? "PENDING" : (is_market ? "MARKET" : "UNSPECIFIED");

      if(StringLen(request.symbol) == 0)
      {
         result.error_message = "Order request missing symbol";
         LogOE("PlaceOrder failed: missing symbol");
         LogDecision("OrderEngine",
                     "PLACE_REJECT",
                     StringFormat("{\"reason\":\"missing_symbol\",\"type\":\"%s\"}",
                                  EnumToString(request.type)));
         return result;
      }

      if(SymbolBridge_Normalize(request.symbol) == "XAUEUR")
      {
         result.error_message = "XAUEUR execution requires proxy mapping";
         LogOE("PlaceOrder failed: XAUEUR execution must be proxied to XAUUSD");
         LogDecision("OrderEngine",
                     "PLACE_REJECT",
                     StringFormat("{\"symbol\":\"%s\",\"reason\":\"xaueur_direct\"}",
                                  request.symbol));
         return result;
      }

      if(!MathIsValidNumber(request.volume) || request.volume <= 0.0)
      {
         result.error_message = StringFormat("Volume %.4f invalid for %s", request.volume, request.symbol);
         LogOE(StringFormat("PlaceOrder failed: invalid volume %.4f for %s",
                            request.volume,
                            request.symbol));
         LogDecision("OrderEngine",
                     "PLACE_REJECT",
                     StringFormat("{\"symbol\":\"%s\",\"mode\":\"%s\",\"reason\":\"invalid_volume\",\"volume\":%.4f}",
                                  request.symbol,
                                  mode,
                                  request.volume));
         return result;
      }

      if(!is_market && !is_pending)
      {
         result.error_message = StringFormat("Unsupported order type %s", EnumToString(request.type));
         LogOE(StringFormat("PlaceOrder failed: unsupported order type %s",
                            EnumToString(request.type)));
         LogDecision("OrderEngine",
                     "PLACE_REJECT",
                     StringFormat("{\"symbol\":\"%s\",\"reason\":\"unsupported_type\",\"type\":\"%s\"}",
                                  request.symbol,
                                  EnumToString(request.type)));
         return result;
      }

      OrderRequest normalized = request;
      if(StringLen(normalized.signal_symbol) == 0)
         normalized.signal_symbol = normalized.symbol;
      normalized.is_proxy = (SymbolBridge_Normalize(normalized.signal_symbol) != SymbolBridge_Normalize(normalized.symbol));
      if(normalized.proxy_rate <= 0.0)
         normalized.proxy_rate = 1.0;
      normalized.is_protective = request.is_protective;
      if(normalized.is_proxy && StringLen(normalized.proxy_context) == 0)
         normalized.proxy_context = StringFormat("%s->%s", normalized.signal_symbol, normalized.symbol);

      const string expected_exec = SymbolBridge_GetExecutionSymbol(normalized.signal_symbol);
      if(SymbolBridge_Normalize(expected_exec) != SymbolBridge_Normalize(normalized.symbol))
      {
         result.error_message = StringFormat("Execution symbol mismatch for %s (expected %s got %s)",
                                             normalized.signal_symbol,
                                             expected_exec,
                                             normalized.symbol);
         LogDecision("OrderEngine",
                     "PLACE_REJECT",
                     StringFormat("{\"signal_symbol\":\"%s\",\"expected\":\"%s\",\"received\":\"%s\"}",
                                  normalized.signal_symbol,
                                  expected_exec,
                                  normalized.symbol));
         return result;
      }

      const double normalized_volume = OE_NormalizeVolume(request.symbol, request.volume);
      if(!MathIsValidNumber(normalized_volume) || normalized_volume <= 0.0)
      {
         result.error_message = StringFormat("Unable to normalize volume %.8f for %s", request.volume, request.symbol);
         LogOE(StringFormat("PlaceOrder failed: normalization produced invalid volume %.8f for %s",
                            normalized_volume,
                            request.symbol));
         LogDecision("OrderEngine",
                     "PLACE_REJECT",
                     StringFormat("{\"symbol\":\"%s\",\"mode\":\"%s\",\"reason\":\"volume_normalization\",\"raw_volume\":%.8f}",
                                  request.symbol,
                                  mode,
                                  request.volume));
         return result;
      }

      if(MathAbs(normalized_volume - request.volume) > 1e-8)
      {
         LogOE(StringFormat("Normalized volume for %s adjusted from %.8f to %.8f",
                            request.symbol,
                            request.volume,
                            normalized_volume));
      }

      normalized.volume = normalized_volume;

      if(request.price > 0.0)
      {
         const double normalized_price = OE_NormalizePrice(request.symbol, request.price);
         if(MathIsValidNumber(normalized_price) && normalized_price > 0.0)
         {
            if(MathAbs(normalized_price - request.price) > 1e-8)
            {
               LogOE(StringFormat("Normalized price for %s adjusted from %.10f to %.10f",
                                  request.symbol,
                                  request.price,
                                  normalized_price));
            }
            normalized.price = normalized_price;
         }
      }

      if(request.sl > 0.0)
      {
         const double normalized_sl = OE_NormalizePrice(request.symbol, request.sl);
         if(MathIsValidNumber(normalized_sl) && normalized_sl > 0.0)
         {
            if(MathAbs(normalized_sl - request.sl) > 1e-8)
            {
               LogOE(StringFormat("Normalized SL for %s adjusted from %.10f to %.10f",
                                  request.symbol,
                                  request.sl,
                                  normalized_sl));
            }
            normalized.sl = normalized_sl;
         }
      }

      if(request.tp > 0.0)
      {
         const double normalized_tp = OE_NormalizePrice(request.symbol, request.tp);
         if(MathIsValidNumber(normalized_tp) && normalized_tp > 0.0)
         {
            if(MathAbs(normalized_tp - request.tp) > 1e-8)
            {
               LogOE(StringFormat("Normalized TP for %s adjusted from %.10f to %.10f",
                                  request.symbol,
                                  request.tp,
                                  normalized_tp));
            }
            normalized.tp = normalized_tp;
         }
      }

      intent_time = TimeCurrent();
      accept_key = BuildIntentAcceptKey(normalized);
      int duplicate_index = -1;
      if(IntentExists(accept_key, duplicate_index))
      {
         result.error_message = "Duplicate order intent detected";
         result.accept_once_key = accept_key;
         LogOE(StringFormat("PlaceOrder duplicate intent rejected: %s %s accept_key=%s",
                            normalized.symbol,
                            EnumToString(normalized.type),
                            accept_key));
         string duplicate_fields = StringFormat("{\"symbol\":\"%s\",\"type\":\"%s\",\"mode\":\"%s\",\"accept_once_key\":\"%s\"}",
                                                normalized.symbol,
                                                EnumToString(normalized.type),
                                                mode,
                                                accept_key);
         LogDecision("OrderEngine", "INTENT_DUPLICATE", duplicate_fields);
         LogAuditRow("ORDER_INTENT_DUP", "OrderEngine", LOG_WARN, "Duplicate order intent", duplicate_fields);
         return result;
      }

      intent_id = GenerateIntentId(intent_time);
      OrderIntent intent_record;
      intent_record.intent_id = intent_id;
      intent_record.accept_once_key = accept_key;
      intent_record.timestamp = intent_time;
      intent_record.symbol = normalized.symbol;
      intent_record.signal_symbol = normalized.signal_symbol;
      intent_record.order_type = normalized.type;
      intent_record.volume = normalized.volume;
      intent_record.price = normalized.price;
      intent_record.sl = normalized.sl;
      intent_record.tp = normalized.tp;
      intent_record.expiry = normalized.expiry;
      intent_record.status = "PENDING";
      intent_record.execution_mode = (normalized.is_proxy ? "PROXY" : "DIRECT");
      intent_record.is_proxy = normalized.is_proxy;
      intent_record.proxy_rate = normalized.proxy_rate;
      intent_record.proxy_context = normalized.proxy_context;
      intent_record.oco_sibling_id = "";
      intent_record.retry_count = 0;
      intent_record.reasoning = request.comment;
      StringReplace(intent_record.reasoning, "\r", " ");
      StringReplace(intent_record.reasoning, "\n", " ");
      ArrayResize(intent_record.error_messages, 0);
      ArrayResize(intent_record.executed_tickets, 0);
      ArrayResize(intent_record.partial_fills, 0);
      intent_record.confidence = 0.0;
      intent_record.efficiency = 0.0;
      intent_record.rho_est = OE_CORRELATION_FALLBACK;
      intent_record.est_value = 0.0;
      intent_record.expected_hold_minutes = 0.0;
      intent_record.gate_open_risk = 0.0;
      intent_record.gate_pending_risk = 0.0;
      intent_record.gate_next_risk = 0.0;
      intent_record.room_today = 0.0;
      intent_record.room_overall = 0.0;
      intent_record.gate_pass = false;
      intent_record.gating_reason = "";
      intent_record.news_window_state = news_state_detail;
      intent_record.decision_context = request.comment;
      ArrayResize(intent_record.tickets_snapshot, 0);
      intent_record.last_executed_price = 0.0;
      intent_record.last_filled_volume = 0.0;
      intent_record.hold_time_seconds = 0.0;

  intent_index = ArraySize(m_intent_journal.intents);
  ArrayResize(m_intent_journal.intents, intent_index + 1);
  m_intent_journal.intents[intent_index] = intent_record;
  MarkJournalDirty();
  LogOE(StringFormat("Intent created: id=%s accept_key=%s status=%s symbol=%s",
                     intent_record.intent_id,
                     intent_record.accept_once_key,
                     intent_record.status,
                     intent_record.symbol));
  PersistIntentJournal();

      intent_created = true;
      result.intent_id = intent_id;
      result.accept_once_key = accept_key;

      string reason_sanitized = intent_record.reasoning;
      StringReplace(reason_sanitized, "\"", "'");
      string intent_fields = StringFormat("{\"intent_id\":\"%s\",\"symbol\":\"%s\",\"order_type\":\"%s\",\"volume\":%.4f,\"price\":%.5f,\"sl\":%.5f,\"tp\":%.5f,\"accept_once_key\":\"%s\",\"reason\":\"%s\"}",
                                          intent_id,
                                          normalized.symbol,
                                          EnumToString(normalized.type),
                                          normalized.volume,
                                          normalized.price,
                                          normalized.sl,
                                          normalized.tp,
                                          accept_key,
                                          reason_sanitized);
      LogDecision("OrderEngine", "INTENT_ACCEPT", intent_fields);
      LogAuditRow("ORDER_INTENT", "OrderEngine", LOG_INFO, "Intent recorded", intent_fields);
      Audit_LogIntentEvent(intent_record,
                           ":INTENT",
                           "INTENT_CREATED",
                           intent_record.price,
                           0.0,
                           intent_record.volume,
                           0.0,
                           intent_record.volume,
                           0,
                           "",
                           intent_record.news_window_state);

      datetime news_gate_timestamp = TimeCurrent();
      NewsGateState news_gate_state = EvaluateNewsGate(normalized.signal_symbol,
                                                       normalized.is_protective,
                                                       news_state_detail);
      intent_record.news_window_state = news_state_detail;

      if(news_gate_state == NEWS_GATE_BLOCKED)
      {
         result.error_message = StringFormat("News blocked for %s (%s)",
                                             normalized.signal_symbol,
                                             news_state_detail);
         LogDecision("OrderEngine",
                     "NEWS_GATE_BLOCK",
                     StringFormat("{\"signal_symbol\":\"%s\",\"detail\":\"%s\"}",
                                  normalized.signal_symbol,
                                  news_state_detail));
         return result;
      }

      int total_positions = 0;
      int symbol_positions = 0;
      int symbol_pending = 0;
      string violation_reason = "";

      if(!EvaluatePositionCaps(normalized,
                               is_pending,
                               total_positions,
                               symbol_positions,
                               symbol_pending,
                               violation_reason))
      {
         const int total_limit = MaxOpenPositionsTotal;
         const int symbol_limit = MaxOpenPerSymbol;
         const int pending_limit = MaxPendingsPerSymbol;

         string fields = StringFormat(
            "{\"symbol\":\"%s\",\"type\":\"%s\",\"mode\":\"%s\",\"reason\":\"%s\",\"total\":%d,\"symbol\":%d,\"pending\":%d,\"limit_total\":%d,\"limit_symbol\":%d,\"limit_pending\":%d}",
            normalized.symbol,
            EnumToString(normalized.type),
            mode,
            violation_reason,
            total_positions,
            symbol_positions,
            symbol_pending,
            total_limit,
            symbol_limit,
            pending_limit);

         LogDecision("OrderEngine", "CAP_BLOCK", fields);
         LogOE(StringFormat("PlaceOrder blocked: %s", violation_reason));
         result.error_message = StringFormat("Position caps prevent order: %s", violation_reason);
         return result;
      }

      const int projected_total = total_positions + (is_market ? 1 : 0);
      const int projected_symbol_positions = symbol_positions + (is_market ? 1 : 0);
      const int projected_symbol_pending = symbol_pending + (is_pending ? 1 : 0);

      string cap_pass_fields = StringFormat(
         "{\"symbol\":\"%s\",\"type\":\"%s\",\"mode\":\"%s\",\"total_current\":%d,\"total_after\":%d,\"total_limit\":%d,\"symbol_current\":%d,\"symbol_after\":%d,\"symbol_limit\":%d,\"pending_current\":%d,\"pending_after\":%d,\"pending_limit\":%d}",
         normalized.symbol,
         EnumToString(normalized.type),
         mode,
         total_positions,
         projected_total,
         MaxOpenPositionsTotal,
         symbol_positions,
         projected_symbol_positions,
         MaxOpenPerSymbol,
         symbol_pending,
         projected_symbol_pending,
         MaxPendingsPerSymbol);

      LogDecision("OrderEngine", "CAP_PASS", cap_pass_fields);
      LogOE(StringFormat("Position caps OK for %s (%s): total %d->%d (limit=%d), symbol %d->%d (limit=%d), pending %d->%d (limit=%d)",
                         normalized.symbol,
                         mode,
                         total_positions,
                         projected_total,
                         MaxOpenPositionsTotal,
                         symbol_positions,
                         projected_symbol_positions,
                         MaxOpenPerSymbol,
                         symbol_pending,
                         projected_symbol_pending,
                         MaxPendingsPerSymbol));

      double entry_price = normalized.price;
      if(is_market)
      {
         double override_point = 0.0;
         int override_digits = 0;
         double override_bid = 0.0;
         double override_ask = 0.0;
         int override_stops = 0;
         const bool has_price_override = OE_Test_GetPriceOverride(normalized.symbol,
                                                                  override_point,
                                                                  override_digits,
                                                                  override_bid,
                                                                  override_ask,
                                                                  override_stops);

         double quote = 0.0;
         if(normalized.type == ORDER_TYPE_BUY)
         {
            if(has_price_override && override_ask > 0.0)
               entry_price = override_ask;
            else if(OE_SymbolInfoDoubleSafe("PlaceOrder::BUY", normalized.symbol, SYMBOL_ASK, quote))
               entry_price = quote;
         }
         else if(normalized.type == ORDER_TYPE_SELL)
         {
            if(has_price_override && override_bid > 0.0)
               entry_price = override_bid;
            else if(OE_SymbolInfoDoubleSafe("PlaceOrder::SELL", normalized.symbol, SYMBOL_BID, quote))
               entry_price = quote;
         }
      }

      if(entry_price > 0.0)
      {
         const double normalized_entry = OE_NormalizePrice(normalized.symbol, entry_price);
         if(MathIsValidNumber(normalized_entry) && normalized_entry > 0.0)
            entry_price = normalized_entry;
      }

      if(normalized.is_proxy)
      {
         if(normalized.proxy_rate <= 0.0)
         {
            result.error_message = "Proxy mapping missing EURUSD rate";
            LogDecision("OrderEngine",
                        "PLACE_REJECT",
                        "{\"reason\":\"proxy_rate_invalid\"}");
            return result;
         }
         double point = 0.0;
         if(!SymbolInfoDouble(normalized.symbol, SYMBOL_POINT, point) || point <= 0.0)
         {
            result.error_message = "Unable to validate proxy distance (point missing)";
            LogDecision("OrderEngine",
                        "PLACE_REJECT",
                        "{\"reason\":\"proxy_point_missing\"}");
            return result;
         }

         const double distance_tolerance = 0.5;
         const double rate_tolerance = 0.05;
         double exec_sl_points = 0.0;
         double exec_tp_points = 0.0;
         if(entry_price > 0.0 && normalized.sl > 0.0)
            exec_sl_points = MathAbs(entry_price - normalized.sl) / point;
         if(entry_price > 0.0 && normalized.tp > 0.0)
            exec_tp_points = MathAbs(normalized.tp - entry_price) / point;

         if(exec_sl_points > 0.0)
         {
            double mapped = 0.0;
            double eurusd_rate = 0.0;
            double signal_points = exec_sl_points / normalized.proxy_rate;
            if(signal_points <= 0.0 ||
               !SymbolBridge_MapDistance(normalized.signal_symbol,
                                         normalized.symbol,
                                         signal_points,
                                         mapped,
                                         eurusd_rate) ||
               mapped <= 0.0 ||
               MathAbs(mapped - exec_sl_points) > distance_tolerance ||
               MathAbs(eurusd_rate - normalized.proxy_rate) > rate_tolerance)
            {
               result.error_message = "Proxy SL distance validation failed";
               LogDecision("OrderEngine",
                           "PLACE_REJECT",
                           StringFormat("{\"reason\":\"proxy_sl_validation\",\"mapped\":%.4f,\"expected\":%.4f}",
                                        mapped,
                                        exec_sl_points));
               return result;
            }
         }

         if(exec_tp_points > 0.0)
         {
            double mapped = 0.0;
            double eurusd_rate = 0.0;
            double signal_points = exec_tp_points / normalized.proxy_rate;
            if(signal_points <= 0.0 ||
               !SymbolBridge_MapDistance(normalized.signal_symbol,
                                         normalized.symbol,
                                         signal_points,
                                         mapped,
                                         eurusd_rate) ||
               mapped <= 0.0 ||
               MathAbs(mapped - exec_tp_points) > distance_tolerance ||
               MathAbs(eurusd_rate - normalized.proxy_rate) > rate_tolerance)
            {
               result.error_message = "Proxy TP distance validation failed";
               LogDecision("OrderEngine",
                           "PLACE_REJECT",
                           StringFormat("{\"reason\":\"proxy_tp_validation\",\"mapped\":%.4f,\"expected\":%.4f}",
                                        mapped,
                                        exec_tp_points));
               return result;
            }
         }
      }

      double evaluated_risk = 0.0;
      EquityBudgetGateResult gate_snapshot;
      ZeroMemory(gate_snapshot);
      string gate_rejection = "";

      if(!ValidateRiskConstraints(normalized,
                                   entry_price,
                                   is_pending,
                                   evaluated_risk,
                                   gate_snapshot,
                                   gate_rejection))
      {
         string fields = StringFormat(
            "{\"symbol\":\"%s\",\"signal_symbol\":\"%s\",\"type\":\"%s\",\"mode\":\"%s\",\"reason\":\"%s\"}",
            normalized.symbol,
            normalized.signal_symbol,
            EnumToString(normalized.type),
            mode,
            gate_rejection);

         LogDecision("OrderEngine", "RISK_BLOCK", fields);
         LogOE(StringFormat("PlaceOrder blocked: %s", gate_rejection));
         result.error_message = gate_rejection;
         return result;
      }

      intent_record.gate_open_risk = gate_snapshot.open_risk;
      intent_record.gate_pending_risk = gate_snapshot.pending_risk;
      intent_record.gate_next_risk = evaluated_risk;
      intent_record.room_today = gate_snapshot.room_today;
      intent_record.room_overall = gate_snapshot.room_overall;
      intent_record.gate_pass = gate_snapshot.gate_pass;
      intent_record.gating_reason = gate_snapshot.gating_reason;
      if(normalized.is_proxy)
      {
         string proxy_info = StringFormat("%s eurusd=%.5f",
                                          normalized.proxy_context,
                                          normalized.proxy_rate);
         if(StringLen(intent_record.gating_reason) > 0)
            intent_record.gating_reason = intent_record.gating_reason + "|" + proxy_info;
         else
            intent_record.gating_reason = proxy_info;
      }

      LogDecision("OrderEngine",
                  "RISK_EVAL",
                  StringFormat("{\"symbol\":\"%s\",\"signal_symbol\":\"%s\",\"type\":\"%s\",\"mode\":\"%s\",\"entry\":%.5f,\"sl\":%.5f,\"volume\":%.4f,\"risk\":%.2f,\"open\":%.2f,\"pending\":%.2f,\"room_today\":%.2f,\"room_overall\":%.2f}",
                               normalized.symbol,
                               normalized.signal_symbol,
                               EnumToString(normalized.type),
                               mode,
                               entry_price,
                               normalized.sl,
                               normalized.volume,
                               evaluated_risk,
                               gate_snapshot.open_risk,
                               gate_snapshot.pending_risk,
                               gate_snapshot.room_today,
                               gate_snapshot.room_overall));

      if(TimeCurrent() - news_gate_timestamp >= 5)
      {
         string recheck_state = "";
         NewsGateState gate_recheck = EvaluateNewsGate(normalized.signal_symbol,
                                                       normalized.is_protective,
                                                       recheck_state);
         intent_record.news_window_state = recheck_state;
         if(gate_recheck == NEWS_GATE_BLOCKED)
         {
            result.error_message = StringFormat("News blocked for %s on recheck (%s)",
                                                normalized.signal_symbol,
                                                recheck_state);
            LogDecision("OrderEngine",
                        "NEWS_GATE_BLOCK",
                        StringFormat("{\"signal_symbol\":\"%s\",\"detail\":\"%s\",\"phase\":\"pre_execute\"}",
                                     normalized.signal_symbol,
                                     recheck_state));
            return result;
         }
      }

      ExecuteOrderWithRetry(normalized,
                            is_pending,
                            evaluated_risk,
                            projected_total,
                            projected_symbol_positions,
                            projected_symbol_pending,
                            result);

      if(is_pending && !result.success && ShouldFallbackToMarket(result.last_retcode))
      {
         LogOE(StringFormat("Pending order failed with retcode %d - attempting market fallback",
                            result.last_retcode));
         LogDecision("OrderEngine",
                     "MARKET_FALLBACK_TRIGGER",
                     StringFormat("{\"symbol\":\"%s\",\"pending_type\":\"%s\",\"retcode\":%d}",
                                  normalized.symbol,
                                  EnumToString(normalized.type),
                                  result.last_retcode));
         ExecuteMarketFallback(normalized, evaluated_risk, result);
      }

      if(intent_created && intent_index >= 0 && intent_index < ArraySize(m_intent_journal.intents))
      {
         OrderIntent record = m_intent_journal.intents[intent_index];
         record.retry_count = result.retry_count;
         ArrayResize(record.error_messages, 0);
         if(result.success)
         {
            record.status = "EXECUTED";
            ArrayResize(record.executed_tickets, 1);
            record.executed_tickets[0] = result.ticket;
            // Store actual partial fill volumes (Task 8)
            int pf_idx = FindPartialFillState(result.ticket);
            if(pf_idx >= 0 && m_partial_fill_states[pf_idx].fill_count > 0)
            {
               ArrayResize(record.partial_fills, m_partial_fill_states[pf_idx].fill_count);
               for(int pf = 0; pf < m_partial_fill_states[pf_idx].fill_count; pf++)
               {
                  record.partial_fills[pf] = m_partial_fill_states[pf_idx].fills[pf].volume;
               }
            }
            else
            {
               ArrayResize(record.partial_fills, 1);
               record.partial_fills[0] = result.executed_volume;
            }
            string success_fields = StringFormat("{\"intent_id\":\"%s\",\"ticket\":%llu,\"executed_price\":%.5f,\"executed_volume\":%.4f}",
                                                 record.intent_id,
                                                 result.ticket,
                                                 result.executed_price,
                                                 result.executed_volume);
            LogAuditRow("ORDER_INTENT_EXECUTED", "OrderEngine", LOG_INFO, "Intent executed", success_fields);
            record.last_executed_price = result.executed_price;
            record.last_filled_volume = result.executed_volume;
            record.hold_time_seconds = (double)(TimeCurrent() - record.timestamp);
            Audit_LogIntentEvent(record,
                                 ":EXECUTED",
                                 "ORDER_EXECUTED",
                                 record.price,
                                 result.executed_price,
                                 record.volume,
                                 result.executed_volume,
                                 MathMax(0.0, record.volume - result.executed_volume),
                                 result.retry_count,
                                 "",
                                 record.news_window_state);
         }
         else
         {
            record.status = "FAILED";
            if(result.error_message != "")
            {
               ArrayResize(record.error_messages, 1);
               record.error_messages[0] = result.error_message;
               StringReplace(record.error_messages[0], "\"", "'");
            }
            string failure_reason = result.error_message;
            StringReplace(failure_reason, "\"", "'");
            string fail_fields = StringFormat("{\"intent_id\":\"%s\",\"error\":\"%s\",\"retcode\":%d}",
                                              record.intent_id,
                                              failure_reason,
                                              result.last_retcode);
            LogAuditRow("ORDER_INTENT_FAILED", "OrderEngine", LOG_WARN, "Intent failed", fail_fields);
            record.hold_time_seconds = (double)(TimeCurrent() - record.timestamp);
            Audit_LogIntentEvent(record,
                                 ":FAILED",
                                 "ORDER_FAILED",
                                 record.price,
                                 0.0,
                                 record.volume,
                                 0.0,
                                 record.volume,
                                 result.retry_count,
                                 failure_reason,
                                 record.news_window_state);
         }
   m_intent_journal.intents[intent_index] = record;
   MarkJournalDirty();
      LogOE(StringFormat("Intent updated: id=%s status=%s retries=%d",
                         record.intent_id,
                         record.status,
                         record.retry_count));
     PersistIntentJournal();
      }

      return result;
   }
   
   bool ModifyOrder(const ulong ticket, const double new_sl, const double new_tp)
   {
      LogOE(StringFormat("ModifyOrder: ticket=%llu sl=%.5f tp=%.5f", ticket, new_sl, new_tp));
      // TODO[M3-Task5]: Implement with retry logic
      return false;
   }
   
   bool CancelOrder(const ulong ticket)
   {
      LogOE(StringFormat("CancelOrder: ticket=%llu", ticket));
      // TODO[M3-Task5]: Implement with retry logic
      return false;
   }
   
   //===========================================================================
   // OCO Management Methods (Stubs for M3 Task 7)
   //===========================================================================
   
   bool EstablishOCO(const ulong primary_ticket, const ulong sibling_ticket, 
                     const string symbol, const double primary_volume, 
                     const double sibling_volume, const datetime expiry)
   {
      LogOE(StringFormat("EstablishOCO: primary=%llu sibling=%llu symbol=%s expiry=%s",
            primary_ticket, sibling_ticket, symbol, TimeToString(expiry)));

      if(m_oco_count >= ArraySize(m_oco_relationships))
         return false;

      int idx = m_oco_count;
      m_oco_relationships[idx].primary_ticket = primary_ticket;
      m_oco_relationships[idx].sibling_ticket = sibling_ticket;
      m_oco_relationships[idx].symbol = symbol;
      m_oco_relationships[idx].primary_volume = primary_volume;
      m_oco_relationships[idx].sibling_volume = sibling_volume;
      m_oco_relationships[idx].primary_volume_original = primary_volume;  // Task 8: Never modified
      m_oco_relationships[idx].sibling_volume_original = sibling_volume;  // Task 8: Never modified
      m_oco_relationships[idx].expiry = expiry;
      m_oco_relationships[idx].expiry_broker = expiry;
      m_oco_relationships[idx].expiry_aligned = GetSessionCutoffAligned(symbol, TimeCurrent());
      m_oco_relationships[idx].established_time = TimeCurrent();
      m_oco_relationships[idx].establish_reason = "establish";
      m_oco_relationships[idx].primary_filled = 0.0;
      m_oco_relationships[idx].sibling_filled = 0.0;
      m_oco_relationships[idx].is_active = true;
      m_oco_count++;

      string fields = StringFormat("{\"primary_ticket\":%llu,\"sibling_ticket\":%llu,\"symbol\":\"%s\",\"primary_vol\":%.2f,\"sibling_vol\":%.2f,\"expiry_broker\":\"%s\",\"established\":\"%s\"}",
                                   primary_ticket,
                                   sibling_ticket,
                                   symbol,
                                   primary_volume,
                                   sibling_volume,
                                   TimeToString(expiry),
                                   TimeToString(m_oco_relationships[idx].established_time));
      LogDecision("OrderEngine", "OCO_ESTABLISH", fields);
      OE_Test_CaptureDecision("OCO_ESTABLISH", fields);
      return true;
   }
   
   bool ProcessOCOFill(const ulong filled_ticket, const double explicit_deal_volume = -1.0, const ulong deal_id = 0)
   {
      LogOE(StringFormat("ProcessOCOFill: ticket=%llu", filled_ticket));
      int idx = FindOCORelationship(filled_ticket);
      if(idx < 0)
         return false;

      const bool is_primary = (m_oco_relationships[idx].primary_ticket == filled_ticket);
      const ulong filled = filled_ticket;
      const ulong opposite = (is_primary ? m_oco_relationships[idx].sibling_ticket : m_oco_relationships[idx].primary_ticket);
      
      // Use ORIGINAL volumes (never modified) - Task 8
      const double filled_original = (is_primary ? m_oco_relationships[idx].primary_volume_original : m_oco_relationships[idx].sibling_volume_original);
      const double opposite_original = (is_primary ? m_oco_relationships[idx].sibling_volume_original : m_oco_relationships[idx].primary_volume_original);
      
      // Current opposite volume for logging
      double current_opposite = (is_primary ? m_oco_relationships[idx].sibling_volume : m_oco_relationships[idx].primary_volume);

      // Resolve deal volume
      double deal_vol = explicit_deal_volume;
      if(deal_vol <= 0.0 && deal_id > 0)
      {
         if(HistoryDealSelect(deal_id))
            deal_vol = HistoryDealGetDouble(deal_id, DEAL_VOLUME);
      }
      // Fallback for tests
      if(deal_vol <= 0.0)
      {
         if(is_primary && filled_original > 0.0 && g_oe_cancel_modify_override.active && g_oe_cancel_modify_override.force_cancel_fail)
            deal_vol = filled_original * 0.4;
      }
      if(deal_vol < 0.0) deal_vol = 0.0;

      // Compute cumulative filled
      double cumulative_filled = (is_primary ? m_oco_relationships[idx].primary_filled : m_oco_relationships[idx].sibling_filled) + deal_vol;

      // Compute ratio using ORIGINAL filled leg volume
      double ratio = 0.0;
      if(filled_original > 0.0)
         ratio = MathMin(1.0, cumulative_filled / filled_original);
         
      // Calculate new opposite volume using ORIGINAL opposite volume
      double new_opposite = MathMax(0.0, opposite_original * (1.0 - ratio));

      // Guard: log warning if opposite missing but continue
      if(opposite == 0 || !OrderSelect((ulong)opposite))
      {
         string warn_fields = StringFormat("{\"filled_ticket\":%llu,\"opposite_ticket\":%llu}", filled, opposite);
         LogOE(StringFormat("ProcessOCOFill: No valid opposite for ticket %llu", filled));
         LogDecision("OrderEngine", "OCO_SIBLING_MISSING", warn_fields);
         OE_Test_CaptureDecision("OCO_SIBLING_MISSING", warn_fields);
      }

      // Attempt cancel
      string fields = StringFormat("{\"filled_ticket\":%llu,\"opposite_ticket\":%llu}", filled, opposite);
      LogDecision("OrderEngine", "OCO_CANCEL_ATTEMPT", fields);
      OE_Test_CaptureDecision("OCO_CANCEL_ATTEMPT", fields);

      bool cancelled = OE_RequestCancel(opposite, "oco_sibling_cancel");
      if(cancelled)
      {
         string done_fields = StringFormat("{\"opposite_ticket\":%llu}", opposite);
         LogDecision("OrderEngine", "OCO_CANCEL", done_fields);
         OE_Test_CaptureDecision("OCO_CANCEL", done_fields);
         ClearPartialFillStateByTicket(filled);
         ClearPartialFillStateByTicket(opposite);
         ClearOCOByIndex(idx);
         return true;
      }

      // Cancel failed, resize opposite
      bool resized = OE_RequestModifyVolume(opposite, new_opposite, "oco_risk_reduction_resize");
      if(resized)
      {
         // Update opposite leg volume (sibling if primary filled, primary if sibling filled) - Task 8
         if(is_primary)
            m_oco_relationships[idx].sibling_volume = new_opposite;
         else
            m_oco_relationships[idx].primary_volume = new_opposite;
         
         string resize_fields = StringFormat("{\"opposite_ticket\":%llu,\"old_vol\":%.2f,\"new_vol\":%.2f}", opposite, current_opposite, new_opposite);
         LogDecision("OrderEngine", "OCO_RESIZE", resize_fields);
         OE_Test_CaptureDecision("OCO_RESIZE", resize_fields);
      }

      // Track partial fill state - Task 8
      int pf_idx = FindOrCreatePartialFillState(filled, filled_original);
      if(pf_idx >= 0)
      {
         m_partial_fill_states[pf_idx].filled_volume += deal_vol;
         m_partial_fill_states[pf_idx].remaining_volume = filled_original - m_partial_fill_states[pf_idx].filled_volume;
         m_partial_fill_states[pf_idx].last_fill_time = TimeCurrent();
         
         // Store event with cap check
         if(m_partial_fill_states[pf_idx].fill_count < 50)
         {
            int fc = m_partial_fill_states[pf_idx].fill_count;
            m_partial_fill_states[pf_idx].fills[fc].volume = deal_vol;
            m_partial_fill_states[pf_idx].fills[fc].sibling_volume_after = new_opposite;
            m_partial_fill_states[pf_idx].fills[fc].timestamp = TimeCurrent();
            m_partial_fill_states[pf_idx].fills[fc].deal_id = deal_id;
            m_partial_fill_states[pf_idx].fill_count++;
         }
         
         string pf_fields = StringFormat("{\"ticket\":%llu,\"fill_vol\":%.4f,\"total_filled\":%.4f,\"remaining\":%.4f,\"fill_count\":%d,\"opposite\":%llu,\"opposite_new_vol\":%.4f}",
                                         filled, deal_vol,
                                         m_partial_fill_states[pf_idx].filled_volume,
                                         m_partial_fill_states[pf_idx].remaining_volume,
                                         m_partial_fill_states[pf_idx].fill_count,
                                         opposite, new_opposite);
         LogDecision("OrderEngine", "PARTIAL_FILL_ADJUST", pf_fields);
         OE_Test_CaptureDecision("PARTIAL_FILL_ADJUST", pf_fields);
         
         // Check completion
         bool is_complete = (m_partial_fill_states[pf_idx].remaining_volume <= 0.001);
         if(is_complete)
         {
            string complete_fields = StringFormat("{\"ticket\":%llu,\"final_vol\":%.4f}", filled, m_partial_fill_states[pf_idx].filled_volume);
            LogDecision("OrderEngine", "PARTIAL_FILL_COMPLETE", complete_fields);
            OE_Test_CaptureDecision("PARTIAL_FILL_COMPLETE", complete_fields);
            ClearPartialFillStateByTicket(filled);
            ClearPartialFillStateByTicket(opposite);
            ClearOCOByIndex(idx);
            return true;  // CRITICAL: Return immediately - idx is now invalid after array compaction
         }
      }

      // Update OCO filled volumes (only if not complete)
      if(is_primary)
         m_oco_relationships[idx].primary_filled += deal_vol;
      else
         m_oco_relationships[idx].sibling_filled += deal_vol;
         
      return resized;
   }
   
   //===========================================================================
   // Trailing Stop Methods (Stubs for M3 Task 13)
   //===========================================================================
   
   bool UpdateTrailing(const ulong position_ticket, const double new_sl)
   {
      LogOE(StringFormat("UpdateTrailing: ticket=%llu new_sl=%.5f", position_ticket, new_sl));
      // TODO[M3-Task13]: Implement trailing stop logic
      return false;
   }
   
   //===========================================================================
   // Execution Lock Methods
   //===========================================================================
   
   bool IsExecutionLocked() const
   {
      return m_execution_locked;
   }
   
   void SetExecutionLock(const bool locked)
   {
      if(m_execution_locked != locked)
      {
         m_execution_locked = locked;
         LogOE(StringFormat("SetExecutionLock: %s", locked ? "LOCKED" : "UNLOCKED"));
      }
   }
   
   //===========================================================================
   // State Recovery Methods (Stub for M3 Task 16)
   //===========================================================================
   
   bool ReconcileOnStartup()
   {
      LogOE("ReconcileOnStartup: Starting state reconciliation");
      if(m_recovery_completed)
      {
         LogOE("ReconcileOnStartup: Recovery already completed");
         return true;
      }

      PersistenceRecoveredState recovered;
      if(!Persistence_LoadRecoveredState(recovered))
      {
         LogOE("ReconcileOnStartup: Failed to load recovered state");
         return false;
      }

      ArrayResize(m_recovered_intents, recovered.intents_count);
      for(int i = 0; i < recovered.intents_count; ++i)
         m_recovered_intents[i] = recovered.intents[i];
      m_recovered_intent_count = recovered.intents_count;
      ArrayResize(m_recovered_actions, recovered.queued_count);
      for(int i = 0; i < recovered.queued_count; ++i)
         m_recovered_actions[i] = recovered.queued_actions[i];
      m_recovered_action_count = recovered.queued_count;

      IntentJournal_Clear(m_intent_journal);
      ArrayResize(m_intent_journal.intents, recovered.intents_count);
      for(int i = 0; i < recovered.intents_count; ++i)
         m_intent_journal.intents[i] = recovered.intents[i];
      ArrayResize(m_intent_journal.queued_actions, recovered.queued_count);
      for(int i = 0; i < recovered.queued_count; ++i)
         m_intent_journal.queued_actions[i] = recovered.queued_actions[i];
      if(recovered.has_engine_state)
         m_intent_journal.engine_state = recovered.engine_state;
      else
         Persistence_ResetEngineState(m_intent_journal.engine_state);
      RestoreEngineStateFromJournal();
      TouchJournalSequences();
      m_intent_journal_dirty = true;

      const datetime now = TimeCurrent();
      const bool was_locked = IsExecutionLocked();
      if(!was_locked)
         SetExecutionLock(true);

      ulong position_tickets[];
      int positions_total = PositionsTotal();
      ArrayResize(position_tickets, positions_total);
      int position_count = 0;
      for(int i = 0; i < positions_total; ++i)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
            position_tickets[position_count++] = ticket;
      }
      ArrayResize(position_tickets, position_count);
      ulong pending_tickets[];
      int orders_total = OrdersTotal();
      ArrayResize(pending_tickets, orders_total);
      int pending_count = 0;
      for(int i = 0; i < orders_total; ++i)
      {
         ulong order_ticket = OrderGetTicket(i);
         if(order_ticket == 0)
            continue;
         if(!OrderSelect(order_ticket))
            continue;
         ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_SELL)
            continue;
         pending_tickets[pending_count++] = order_ticket;
      }
      ArrayResize(pending_tickets, pending_count);

      int intents_marked_closed = 0;
      int intents_marked_cancelled = 0;
      for(int i = 0; i < ArraySize(m_intent_journal.intents); ++i)
      {
         OrderIntent intent = m_intent_journal.intents[i];
         if(ArraySize(intent.executed_tickets) > 0)
         {
            bool ticket_active = false;
            for(int j = 0; j < ArraySize(intent.executed_tickets) && !ticket_active; ++j)
            {
               for(int k = 0; k < position_count; ++k)
               {
                  if(position_tickets[k] == intent.executed_tickets[j])
                  {
                     ticket_active = true;
                     break;
                  }
               }
            }
            if(!ticket_active && (intent.status == "PENDING" || intent.status == "EXECUTED"))
            {
               intent.status = "CLOSED";
               intents_marked_closed++;
            }
         }
         if(intent.status == "PENDING" && ArraySize(intent.executed_tickets) > 0)
         {
            bool order_active = false;
            for(int j = 0; j < ArraySize(intent.executed_tickets) && !order_active; ++j)
            {
               for(int k = 0; k < pending_count; ++k)
               {
                  if(pending_tickets[k] == intent.executed_tickets[j])
                  {
                     order_active = true;
                     break;
                  }
               }
            }
            if(!order_active)
            {
               intent.status = "CANCELLED";
               intents_marked_cancelled++;
            }
         }
         m_intent_journal.intents[i] = intent;
      }

      int orphans_attached = 0;
      int pending_orphans_attached = 0;
      for(int i = 0; i < position_count; ++i)
      {
         ulong ticket = position_tickets[i];
         OrderIntent existing;
         if(MatchIntentByTicket(ticket, existing))
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;
         OrderIntent orphan;
         ZeroMemory(orphan);
         orphan.intent_id = StringFormat("broker_recovery_%llu", ticket);
         orphan.accept_once_key = orphan.intent_id;
         orphan.timestamp = (datetime)PositionGetInteger(POSITION_TIME);
         orphan.symbol = PositionGetString(POSITION_SYMBOL);
         orphan.signal_symbol = orphan.symbol;
         ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         orphan.order_type = (pos_type == POSITION_TYPE_SELL ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
         orphan.volume = PositionGetDouble(POSITION_VOLUME);
         orphan.price = PositionGetDouble(POSITION_PRICE_OPEN);
         orphan.sl = PositionGetDouble(POSITION_SL);
         orphan.tp = PositionGetDouble(POSITION_TP);
         orphan.status = "RECOVERED";
         orphan.execution_mode = "DIRECT";
         orphan.is_proxy = false;
         orphan.proxy_rate = 1.0;
         orphan.retry_count = 0;
         orphan.reasoning = "broker_recovery";
         ArrayResize(orphan.executed_tickets, 1);
         orphan.executed_tickets[0] = ticket;
         ArrayResize(orphan.partial_fills, 0);
         ArrayResize(orphan.error_messages, 0);
         ArrayResize(orphan.tickets_snapshot, 0);
         int idx = ArraySize(m_intent_journal.intents);
         ArrayResize(m_intent_journal.intents, idx + 1);
         m_intent_journal.intents[idx] = orphan;
         orphans_attached++;
      }
      for(int i = 0; i < pending_count; ++i)
      {
         ulong ticket = pending_tickets[i];
         OrderIntent existing;
         if(MatchIntentByTicket(ticket, existing))
            continue;
         if(!OrderSelect(ticket))
            continue;
         OrderIntent orphan;
         ZeroMemory(orphan);
         orphan.intent_id = StringFormat("broker_pending_%llu", ticket);
         orphan.accept_once_key = orphan.intent_id;
         orphan.timestamp = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         orphan.symbol = OrderGetString(ORDER_SYMBOL);
         orphan.signal_symbol = orphan.symbol;
         ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         orphan.order_type = order_type;
         orphan.volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
         orphan.price = OrderGetDouble(ORDER_PRICE_OPEN);
         orphan.sl = OrderGetDouble(ORDER_SL);
         orphan.tp = OrderGetDouble(ORDER_TP);
         orphan.status = "PENDING";
         orphan.execution_mode = "DIRECT";
         orphan.is_proxy = false;
         orphan.proxy_rate = 1.0;
         ArrayResize(orphan.executed_tickets, 1);
         orphan.executed_tickets[0] = ticket;
         ArrayResize(orphan.partial_fills, 0);
         ArrayResize(orphan.error_messages, 0);
         ArrayResize(orphan.tickets_snapshot, 0);
         int idx = ArraySize(m_intent_journal.intents);
         ArrayResize(m_intent_journal.intents, idx + 1);
         m_intent_journal.intents[idx] = orphan;
         pending_orphans_attached++;
      }

      int new_action_count = 0;
      for(int i = 0; i < ArraySize(m_intent_journal.queued_actions); ++i)
      {
         PersistedQueuedAction action = m_intent_journal.queued_actions[i];
         bool keep = true;
         if(StringLen(action.intent_id) > 0 && FindIntentIndexById(action.intent_id) < 0)
            keep = false;
         if(keep && action.expires_time > 0 && action.expires_time < now)
            keep = false;
         if(keep && action.ticket > 0)
         {
            if(!PositionSelectByTicket(action.ticket) &&
               !OrderSelect((ulong)action.ticket))
               keep = false;
         }
         if(keep)
         {
            m_intent_journal.queued_actions[new_action_count++] = action;
         }
      }
      ArrayResize(m_intent_journal.queued_actions, new_action_count);

      EnsureSLEnforcementLoaded();
      bool sl_dirty = false;
      for(int i = 0; i < m_sl_enforcement_count; )
      {
         double sl_value = 0.0;
         datetime open_time = 0;
         if(!GetPositionSLByTicket(m_sl_enforcement_queue[i].ticket, sl_value, open_time))
         {
            RemoveSLEnforcementAt(i);
            sl_dirty = true;
            continue;
         }
         i++;
      }
      if(sl_dirty)
         SaveSLEnforcementState();

      CleanupExpiredJournalEntries(now);
      PersistIntentJournal();
      Persistence_PruneOldRecoveryBackups();

      if(!was_locked)
         SetExecutionLock(false);

      m_recovery_completed = true;
      m_recovery_timestamp = TimeCurrent();

      LogOE(StringFormat("ReconcileOnStartup: intents_total=%d loaded=%d dropped=%d actions_total=%d loaded=%d dropped=%d position_orphans=%d pending_orphans=%d closed=%d cancelled=%d corrupt=%d",
                         recovered.summary.intents_total,
                         recovered.summary.intents_loaded,
                         recovered.summary.intents_dropped,
                         recovered.summary.actions_total,
                         recovered.summary.actions_loaded,
                         recovered.summary.actions_dropped,
                         orphans_attached,
                         pending_orphans_attached,
                         intents_marked_closed,
                         intents_marked_cancelled,
                         recovered.summary.corrupt_entries));

      Persistence_FreeRecoveredState(recovered);
      return true;
   }
};

bool OrderEngine::IsMarketOrderType(const ENUM_ORDER_TYPE type)
{
   return (type == ORDER_TYPE_BUY || type == ORDER_TYPE_SELL);
}

bool OrderEngine::IsPendingOrderType(const ENUM_ORDER_TYPE type)
{
   return Equity_IsPendingOrderType((int)type);
}

bool OrderEngine::IsBuyDirection(const ENUM_ORDER_TYPE type) const
{
   switch(type)
   {
      case ORDER_TYPE_BUY:
      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_BUY_STOP_LIMIT:
         return true;
   }
   return false;
}

ENUM_ORDER_TYPE OrderEngine::MarketTypeFromPending(const ENUM_ORDER_TYPE type) const
{
   switch(type)
   {
      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_BUY_STOP_LIMIT:
         return ORDER_TYPE_BUY;
      case ORDER_TYPE_SELL_LIMIT:
      case ORDER_TYPE_SELL_STOP:
      case ORDER_TYPE_SELL_STOP_LIMIT:
         return ORDER_TYPE_SELL;
      default:
         break;
   }
   return type;
}

bool OrderEngine::ShouldFallbackToMarket(const int retcode) const
{
   switch(retcode)
   {
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_INVALID_PRICE:
         return true;
   }
   return false;
}

bool OrderEngine::EvaluatePositionCaps(const OrderRequest &request,
                                       const bool is_pending_request,
                                       int &out_total_positions,
                                       int &out_symbol_positions,
                                       int &out_symbol_pending,
                                       string &out_violation_reason)
{
   out_violation_reason = "";

   const bool is_market = IsMarketOrderType(request.type);
   bool caps_ok = true;

   if(g_oe_cap_override.active)
   {
      caps_ok = g_oe_cap_override.caps_ok;
      out_total_positions = g_oe_cap_override.total_positions;
      out_symbol_positions = g_oe_cap_override.symbol_positions;
      out_symbol_pending = g_oe_cap_override.symbol_pending;
   }
   else
   {
      caps_ok = Equity_CheckPositionCaps(request.symbol,
                                         out_total_positions,
                                         out_symbol_positions,
                                         out_symbol_pending);
   }

   const int total_limit = MaxOpenPositionsTotal;
   const int symbol_limit = MaxOpenPerSymbol;
   const int pending_limit = MaxPendingsPerSymbol;

   if(!caps_ok)
   {
      if(total_limit > 0 && out_total_positions >= total_limit)
      {
         out_violation_reason = StringFormat("MaxOpenPositionsTotal reached (%d/%d)",
                                             out_total_positions,
                                             total_limit);
      }
      else if(symbol_limit > 0 && out_symbol_positions >= symbol_limit)
      {
         out_violation_reason = StringFormat("MaxOpenPerSymbol reached for %s (%d/%d)",
                                             request.symbol,
                                             out_symbol_positions,
                                             symbol_limit);
      }
      else if(pending_limit > 0 && out_symbol_pending >= pending_limit)
      {
         out_violation_reason = StringFormat("MaxPendingsPerSymbol reached for %s (%d/%d)",
                                             request.symbol,
                                             out_symbol_pending,
                                             pending_limit);
      }
      else
      {
         out_violation_reason = "Unable to evaluate position limits (calculation error)";
      }
      return false;
   }

   const int projected_total = out_total_positions + (is_market ? 1 : 0);
   const int projected_symbol_positions = out_symbol_positions + (is_market ? 1 : 0);
   const int projected_symbol_pending = out_symbol_pending + (is_pending_request ? 1 : 0);

   if(total_limit > 0 && projected_total > total_limit)
   {
      out_violation_reason = StringFormat(
         "Placing order would exceed MaxOpenPositionsTotal (%d -> %d > %d)",
         out_total_positions,
         projected_total,
         total_limit);
      return false;
   }

   if(symbol_limit > 0 && projected_symbol_positions > symbol_limit)
   {
      out_violation_reason = StringFormat(
         "Placing order would exceed MaxOpenPerSymbol for %s (%d -> %d > %d)",
         request.symbol,
         out_symbol_positions,
         projected_symbol_positions,
         symbol_limit);
      return false;
   }

   if(is_pending_request && pending_limit > 0 && projected_symbol_pending > pending_limit)
   {
      out_violation_reason = StringFormat(
         "Placing order would exceed MaxPendingsPerSymbol for %s (%d -> %d > %d)",
         request.symbol,
         out_symbol_pending,
         projected_symbol_pending,
         pending_limit);
      return false;
   }

   return true;
}

bool OrderEngine::ValidateRiskConstraints(const OrderRequest &request,
                                          const double entry_price,
                                          const bool is_pending,
                                          double &out_evaluated_risk,
                                          EquityBudgetGateResult &out_gate,
                                          string &out_rejection_reason)
{
#ifdef RPEA_ORDER_ENGINE_SKIP_EQUITY
   out_rejection_reason = "";
   ZeroMemory(out_gate);

   bool risk_calc_ok = false;
   if(g_oe_risk_override.active)
   {
      risk_calc_ok = g_oe_risk_override.ok;
      out_evaluated_risk = g_oe_risk_override.risk_value;
   }
   else
   {
      out_evaluated_risk = Equity_CalcRiskDollars(request.symbol,
                                                  request.volume,
                                                  entry_price,
                                                  request.sl,
                                                  risk_calc_ok);
   }

   if(!risk_calc_ok || out_evaluated_risk <= 0.0)
   {
      out_rejection_reason = "risk_calc_failed";
      return false;
   }

#ifdef RPEA_TEST_RUNNER
   if(g_test_gate_force_fail)
   {
      out_rejection_reason = "forced_fail";
      return false;
   }
#endif

   out_gate.approved = true;
   out_gate.gate_pass = true;
   out_gate.gating_reason = "skip_equity";
   out_gate.room_available = 1e9;
   out_gate.room_today = 1e9;
   out_gate.room_overall = 1e9;
   out_gate.open_risk = 0.0;
   out_gate.pending_risk = 0.0;
   out_gate.next_worst_case = out_evaluated_risk;
   out_gate.calculation_error = false;

   return true;
#else
   out_evaluated_risk = 0.0;
   out_rejection_reason = "";
   ZeroMemory(out_gate);

   bool risk_calc_ok = false;

   if(g_oe_risk_override.active)
   {
      risk_calc_ok = g_oe_risk_override.ok;
      out_evaluated_risk = g_oe_risk_override.risk_value;
   }
   else
   {
      out_evaluated_risk = Equity_CalcRiskDollars(request.symbol,
                                                  request.volume,
                                                  entry_price,
                                                  request.sl,
                                                  risk_calc_ok);
   }

   if(!risk_calc_ok || out_evaluated_risk <= 0.0)
   {
      out_rejection_reason = "risk_calc_failed";
      return false;
   }

   out_gate = Equity_EvaluateBudgetGate(g_ctx, out_evaluated_risk);

   double headroom = RiskGateHeadroom;
   if(headroom <= 0.0 || !MathIsValidNumber(headroom))
      headroom = DEFAULT_RiskGateHeadroom;

   double min_room = MathMin(out_gate.room_today, out_gate.room_overall);
   if(min_room < 0.0 || !MathIsValidNumber(min_room))
      min_room = 0.0;

   const double projected = out_gate.open_risk + out_gate.pending_risk + out_evaluated_risk;
   const double threshold = headroom * min_room;

   bool gate_allowed = out_gate.gate_pass;
   if(min_room > 0.0 && MathIsValidNumber(threshold))
      gate_allowed = (projected <= threshold + 1e-6);

   if(!gate_allowed)
   {
      out_rejection_reason = (StringLen(out_gate.gating_reason) > 0
                              ? out_gate.gating_reason
                              : "budget_gate");
      return false;
   }

   return true;
#endif
}

NewsGateState OrderEngine::EvaluateNewsGate(const string signal_symbol,
                                            const bool is_protective_exit,
                                            string &out_detail) const
{
   string normalized = SymbolBridge_Normalize(signal_symbol);
   out_detail = "CLEAR";

   if(normalized == "XAUEUR")
   {
      const bool xau_blocked = News_IsBlocked("XAUUSD");
      const bool eur_blocked = News_IsBlocked("EURUSD");
      if(xau_blocked || eur_blocked)
      {
         string leg = (xau_blocked ? "XAUUSD" : "EURUSD");
         out_detail = leg + (is_protective_exit ? "_PROTECTIVE" : "_BLOCKED");
         return (is_protective_exit ? NEWS_GATE_PROTECTIVE_ALLOWED : NEWS_GATE_BLOCKED);
      }
      return NEWS_GATE_CLEAR;
   }

   if(News_IsBlocked(signal_symbol))
   {
      out_detail = normalized + (is_protective_exit ? "_PROTECTIVE" : "_BLOCKED");
      return (is_protective_exit ? NEWS_GATE_PROTECTIVE_ALLOWED : NEWS_GATE_BLOCKED);
   }

   return NEWS_GATE_CLEAR;
}

bool OrderEngine::ExecuteOrderWithRetry(const OrderRequest &request,
                                        const bool is_pending_request,
                                        const double evaluated_risk,
                                        const int projected_total_positions,
                                        const int projected_symbol_positions,
                                        const int projected_symbol_pending,
                                        OrderResult &result)
{
   const bool is_market_request = (!is_pending_request && IsMarketOrderType(request.type));
   const string mode = is_pending_request
                       ? "PENDING"
                       : (IsMarketOrderType(request.type) ? "MARKET" : "UNSPECIFIED");

   LogOE(StringFormat("ExecuteOrderWithRetry: %s order for %s volume=%.4f risk=%.2f (projected totals: total=%d, symbol=%d, pending=%d)",
                      mode,
                      request.symbol,
                      request.volume,
                      evaluated_risk,
                      projected_total_positions,
                      projected_symbol_positions,
                      projected_symbol_pending));

   string init_fields = StringFormat(
      "{\"symbol\":\"%s\",\"type\":\"%s\",\"mode\":\"%s\",\"volume\":%.4f,\"risk\":%.2f,\"requested\":%.5f,\"total_after\":%d,\"symbol_after\":%d,\"pending_after\":%d}",
      request.symbol,
      EnumToString(request.type),
      mode,
      request.volume,
      evaluated_risk,
      request.price,
      projected_total_positions,
      projected_symbol_positions,
      projected_symbol_pending);

   LogDecision("OrderEngine", "EXECUTE_ORDER_INIT", init_fields);

   result.success = false;
   result.ticket = 0;
   result.error_message = "";
   result.executed_price = 0.0;
   result.executed_volume = 0.0;
   result.retry_count = 0;
   result.last_retcode = 0;

   double snapshot_point = 0.0;
   int snapshot_digits = 0;
   double snapshot_bid = 0.0;
   double snapshot_ask = 0.0;
   const bool have_snapshot = OE_GetLatestQuote("ExecuteOrderWithRetry::init",
                                                request.symbol,
                                                snapshot_point,
                                                snapshot_digits,
                                                snapshot_bid,
                                                snapshot_ask);

   double requested_price = request.price;
   double execution_price_hint = request.price;
   if(is_market_request && requested_price <= 0.0 && have_snapshot)
   {
      const bool buy_init = IsBuyDirection(request.type);
      const double snapshot_price = buy_init
                                    ? (snapshot_ask > 0.0 ? snapshot_ask : snapshot_bid)
                                    : (snapshot_bid > 0.0 ? snapshot_bid : snapshot_ask);
      if(snapshot_price > 0.0)
      {
         requested_price = snapshot_price;
         execution_price_hint = snapshot_price;
      }
   }

   const double base_point = snapshot_point;
   const double base_multiplier = (base_point > 0.0 ? MathMax(1.0, 1.0 / base_point) : 1.0);
   int base_deviation = (int)MathRound(MathMax(0.0, m_max_slippage_points * base_multiplier));
   if(base_deviation < 0)
      base_deviation = 0;

   MqlTradeRequest trade_request;
   ZeroMemory(trade_request);
   trade_request.action = is_pending_request ? TRADE_ACTION_PENDING : TRADE_ACTION_DEAL;
   trade_request.symbol = request.symbol;
   trade_request.type = request.type;
   trade_request.volume = request.volume;
   trade_request.price = execution_price_hint;
   trade_request.sl = request.sl;
   trade_request.tp = request.tp;
   trade_request.deviation = base_deviation;
   trade_request.magic = request.magic;
   trade_request.comment = request.comment;
   trade_request.type_filling = ORDER_FILLING_RETURN;
   if(is_pending_request)
   {
      trade_request.type_time = (request.expiry > 0 ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC);
      trade_request.expiration = request.expiry;
   }
   else
   {
      trade_request.type_time = ORDER_TIME_GTC;
      trade_request.expiration = 0;
      if(!MathIsValidNumber(trade_request.price) || trade_request.price <= 0.0)
         trade_request.price = 0.0;
   }

   MqlTradeResult trade_result;
   ZeroMemory(trade_result);

   const int max_attempts = m_retry_manager.MaxRetries() + 1;
   int retries_performed = 0;
   bool success = false;
   double last_quote_price = 0.0;
   double last_slippage_points = 0.0;
   bool slippage_rejected = false;
   string slippage_reject_reason = "";
   bool quote_failure = false;
   string quote_failure_reason = "";
   bool failure_logged = false;

   for(int attempt = 0; attempt < max_attempts; ++attempt)
   {
      if(attempt > 0)
         retries_performed = attempt;

      if(attempt == 0 &&
         OrderEngine_IsCircuitBreakerActive() &&
         !OrderEngine_ShouldBypassBreaker(request.is_protective))
      {
         OrderError breaker_err;
         breaker_err.context = "ExecuteOrderWithRetry";
         breaker_err.intent_id = result.intent_id;
         breaker_err.SetRetcode(TRADE_RETCODE_TRADE_DISABLED);
         breaker_err.attempt = attempt;
         breaker_err.is_protective_exit = request.is_protective;
         breaker_err.requested_volume = request.volume;
         breaker_err.requested_price = requested_price;
         OrderErrorDecision gate = OrderEngine_HandleError(breaker_err);
         result.success = false;
         result.error_message = (gate.gating_reason == "" ? "circuit_breaker_active" : gate.gating_reason);
         result.last_retcode = breaker_err.retcode;
         break;
      }

      if(is_market_request)
      {
         double attempt_point = snapshot_point;
         int attempt_digits = snapshot_digits;
         double attempt_bid = snapshot_bid;
         double attempt_ask = snapshot_ask;

         if(!OE_GetLatestQuote("ExecuteOrderWithRetry::attempt",
                               request.symbol,
                               attempt_point,
                               attempt_digits,
                               attempt_bid,
                               attempt_ask))
         {
            quote_failure = true;
            quote_failure_reason = "Unable to retrieve market quotes";
            result.last_retcode = TRADE_RETCODE_PRICE_OFF;
            break;
         }

         if(attempt_point > 0.0)
            snapshot_point = attempt_point;
         if(attempt_digits > 0)
            snapshot_digits = attempt_digits;

         const bool is_buy = IsBuyDirection(request.type);
         double quote_price = 0.0;
         if(is_buy)
            quote_price = (attempt_ask > 0.0 ? attempt_ask : attempt_bid);
         else
            quote_price = (attempt_bid > 0.0 ? attempt_bid : attempt_ask);

         if(quote_price <= 0.0)
         {
            quote_failure = true;
            quote_failure_reason = StringFormat("Invalid market quote (bid=%.5f, ask=%.5f)",
                                                attempt_bid,
                                                attempt_ask);
            result.last_retcode = TRADE_RETCODE_PRICE_OFF;
            break;
         }

         if(requested_price <= 0.0)
            requested_price = quote_price;

         execution_price_hint = quote_price;

         const double calc_point = (attempt_point > 0.0
                                    ? attempt_point
                                    : (snapshot_point > 0.0 ? snapshot_point : 0.0));

         if(calc_point > 0.0 && requested_price > 0.0)
            last_slippage_points = MathAbs(quote_price - requested_price) / calc_point;
         else
            last_slippage_points = 0.0;

         const bool within_limit = (m_max_slippage_points <= 0.0) ||
                                   (last_slippage_points <= m_max_slippage_points + 1e-6);

         LogOE(StringFormat("Market slippage check attempt %d: requested=%.5f quote=%.5f slippage=%.2f pts max=%.2f",
                            attempt,
                            requested_price,
                            quote_price,
                            last_slippage_points,
                            m_max_slippage_points));
         LogDecision("OrderEngine",
                     "MARKET_SLIPPAGE_CHECK",
                     StringFormat("{\"symbol\":\"%s\",\"attempt\":%d,\"requested\":%.5f,\"quote\":%.5f,\"slippage_pts\":%.2f,\"max_pts\":%.2f,\"within_limit\":%s}",
                                  request.symbol,
                                  attempt,
                                  requested_price,
                                  quote_price,
                                  last_slippage_points,
                                  m_max_slippage_points,
                                  within_limit ? "true" : "false"));

         if(!within_limit)
         {
            slippage_rejected = true;
            slippage_reject_reason = StringFormat("Slippage %.2f pts exceeds MaxSlippagePoints %.2f",
                                                  last_slippage_points,
                                                  m_max_slippage_points);
            result.last_retcode = TRADE_RETCODE_PRICE_OFF;
            break;
         }

         last_quote_price = quote_price;

         const double point_multiplier = (attempt_point > 0.0
                                          ? MathMax(1.0, 1.0 / attempt_point)
                                          : MathMax(1.0, (snapshot_point > 0.0 ? 1.0 / snapshot_point : 1.0)));
         trade_request.deviation = (int)MathRound(MathMax(0.0, m_max_slippage_points * point_multiplier));
         if(trade_request.deviation < 0)
            trade_request.deviation = 0;

         const int price_digits = (attempt_digits > 0 ? attempt_digits : (snapshot_digits > 0 ? snapshot_digits : 8));
         trade_request.price = NormalizeDouble(quote_price, price_digits);
      }
      else
      {
         trade_request.deviation = base_deviation;
      }

      ZeroMemory(trade_result);
      trade_request.price = execution_price_hint;
      const bool send_ok = OE_OrderSend(trade_request, trade_result);
      result.last_retcode = (int)trade_result.retcode;

      const double attempt_slippage = (is_market_request ? last_slippage_points : 0.0);

      string attempt_fields = StringFormat(
         "{\"attempt\":%d,\"symbol\":\"%s\",\"retcode\":%d,\"send_ok\":%s,\"requested\":%.5f,\"submitted\":%.5f,\"slippage_pts\":%.2f}",
         attempt,
         request.symbol,
         trade_result.retcode,
         send_ok ? "true" : "false",
         requested_price,
         trade_request.price,
         attempt_slippage);
      LogDecision("OrderEngine", "ORDER_SEND_ATTEMPT", attempt_fields);

      const bool order_done = (send_ok && trade_result.retcode == TRADE_RETCODE_DONE);
      if(order_done)
      {
         result.success = true;
         result.ticket = (trade_result.deal != 0 ? trade_result.deal : trade_result.order);
         result.executed_price = trade_result.price;
         result.executed_volume = trade_result.volume;
         result.retry_count = retries_performed;
         result.last_retcode = (int)trade_result.retcode;
         result.error_message = "";
         OrderEngine_RecordSuccess();

         double executed_slippage_pts = 0.0;
         if(snapshot_point > 0.0 && requested_price > 0.0 && trade_result.price > 0.0)
            executed_slippage_pts = MathAbs(trade_result.price - requested_price) / snapshot_point;

         LogOE(StringFormat("ExecuteOrderWithRetry success on attempt %d: ticket=%llu requested=%.5f executed=%.5f slippage=%.2f pts volume=%.4f",
                            attempt,
                            result.ticket,
                            requested_price,
                            result.executed_price,
                            executed_slippage_pts,
                            result.executed_volume));
         LogDecision("OrderEngine",
                     "EXECUTE_ORDER_SUCCESS",
                     StringFormat("{\"symbol\":\"%s\",\"attempt\":%d,\"retries\":%d,\"retcode\":%d,\"ticket\":%llu,\"requested\":%.5f,\"executed\":%.5f,\"slippage_pts\":%.2f}",
                                  request.symbol,
                                  attempt,
                                  retries_performed,
                                  trade_result.retcode,
                                  result.ticket,
                                  requested_price,
                                  result.executed_price,
                                  executed_slippage_pts));
         success = true;
         break;
      }

      OrderError err((int)trade_result.retcode);
      err.context = "ExecuteOrderWithRetry";
      err.intent_id = result.intent_id;
      err.ticket = (trade_result.order != 0 ? trade_result.order : trade_result.deal);
      err.attempt = attempt;
      err.requested_price = requested_price;
      err.executed_price = trade_result.price;
      err.requested_volume = request.volume;
      err.is_protective_exit = request.is_protective;
      OrderErrorDecision decision = OrderEngine_HandleError(err);

      LogOE(StringFormat("ExecuteOrderWithRetry failure: attempt=%d retcode=%d decision=%d slippage=%.2f pts",
                         attempt,
                         trade_result.retcode,
                         (int)decision.type,
                         attempt_slippage));

      LogDecision("OrderEngine",
                  "ORDER_RETRY_EVALUATE",
                  StringFormat("{\"attempt\":%d,\"retcode\":%d,\"decision\":%d,\"retry_delay\":%d,\"slippage_pts\":%.2f}",
                               attempt,
                               trade_result.retcode,
                               (int)decision.type,
                               decision.retry_delay_ms,
                               attempt_slippage));

      if(is_pending_request && ShouldFallbackToMarket(trade_result.retcode))
      {
         LogOE(StringFormat("ExecuteOrderWithRetry stopping pending retry: fallback to market on retcode %d",
                            trade_result.retcode));
         break;
      }

      if(decision.type != ERROR_DECISION_RETRY)
      {
         if(decision.type == ERROR_DECISION_FAIL_FAST && decision.gating_reason != "")
            result.error_message = decision.gating_reason;
         break;
      }

      if(decision.retry_delay_ms > 0)
      {
         LogOE(StringFormat("ExecuteOrderWithRetry delay before retry %d: %d ms",
                            attempt + 1,
                            decision.retry_delay_ms));
         OE_ApplyRetryDelay(decision.retry_delay_ms);
      }
   }

   if(slippage_rejected)
   {
      result.success = false;
      result.ticket = 0;
      result.executed_price = last_quote_price;
      result.executed_volume = 0.0;
      result.retry_count = retries_performed;

      result.error_message = slippage_reject_reason;
      OrderError err(TRADE_RETCODE_PRICE_OFF);
      err.context = "ExecuteOrderWithRetry";
      err.intent_id = result.intent_id;
      err.attempt = retries_performed;
      err.requested_price = requested_price;
      err.executed_price = last_quote_price;
      err.requested_volume = request.volume;
      err.is_protective_exit = request.is_protective;
      OrderEngine_HandleError(err);

      LogOE(StringFormat("ExecuteOrderWithRetry slippage rejection: requested=%.5f quote=%.5f slippage=%.2f pts limit=%.2f",
                         requested_price,
                         last_quote_price,
                         last_slippage_points,
                         m_max_slippage_points));
      LogDecision("OrderEngine",
                  "MARKET_SLIPPAGE_REJECT",
                  StringFormat("{\"symbol\":\"%s\",\"retries\":%d,\"requested\":%.5f,\"quote\":%.5f,\"slippage_pts\":%.2f,\"max_pts\":%.2f}",
                               request.symbol,
                               retries_performed,
                               requested_price,
                               last_quote_price,
                               last_slippage_points,
                               m_max_slippage_points));
      LogDecision("OrderEngine",
                  "EXECUTE_ORDER_FAIL",
                  StringFormat("{\"symbol\":\"%s\",\"retries\":%d,\"retcode\":%d,\"reason\":\"slippage_reject\",\"requested\":%.5f,\"last_quote\":%.5f,\"slippage_pts\":%.2f}",
                               request.symbol,
                               retries_performed,
                               result.last_retcode,
                               requested_price,
                               last_quote_price,
                               last_slippage_points));
      failure_logged = true;
   }

   if(quote_failure)
   {
      result.success = false;
      result.ticket = 0;
      result.executed_price = last_quote_price;
      result.executed_volume = 0.0;
      result.retry_count = retries_performed;
      result.error_message = quote_failure_reason;
      OrderError err(TRADE_RETCODE_PRICE_OFF);
      err.context = "ExecuteOrderWithRetry";
      err.intent_id = result.intent_id;
      err.attempt = retries_performed;
      err.requested_price = requested_price;
      err.executed_price = last_quote_price;
      err.requested_volume = request.volume;
      err.is_protective_exit = request.is_protective;
      OrderEngine_HandleError(err);

      LogOE(StringFormat("ExecuteOrderWithRetry quote failure: %s", quote_failure_reason));
      LogDecision("OrderEngine",
                  "EXECUTE_ORDER_FAIL",
                  StringFormat("{\"symbol\":\"%s\",\"retries\":%d,\"retcode\":%d,\"reason\":\"quote_failure\"}",
                               request.symbol,
                               retries_performed,
                               result.last_retcode));
      failure_logged = true;
   }

   if(!success && !failure_logged)
   {
      result.success = false;
      result.ticket = 0;
      result.executed_price = 0.0;
      result.executed_volume = 0.0;
      result.retry_count = retries_performed;

      string fail_message = StringFormat("OrderSend failed (retcode=%d, retries=%d)",
                                         result.last_retcode,
                                         retries_performed);
      if(trade_result.comment != "")
         fail_message = StringFormat("%s comment=%s", fail_message, trade_result.comment);
      if(is_market_request && last_quote_price > 0.0)
      {
         fail_message = StringFormat("%s requested=%.5f last_quote=%.5f slippage=%.2f pts",
                                     fail_message,
                                     requested_price,
                                     last_quote_price,
                                     last_slippage_points);
      }

      result.error_message = fail_message;
      OrderError err(result.last_retcode);
      err.context = "ExecuteOrderWithRetry";
      err.intent_id = result.intent_id;
      err.attempt = retries_performed;
      err.requested_price = requested_price;
      err.executed_price = last_quote_price;
      err.requested_volume = request.volume;
      err.is_protective_exit = request.is_protective;
      OrderEngine_HandleError(err);

      LogDecision("OrderEngine",
                  "EXECUTE_ORDER_FAIL",
                  StringFormat("{\"symbol\":\"%s\",\"retries\":%d,\"retcode\":%d,\"requested\":%.5f,\"last_quote\":%.5f,\"slippage_pts\":%.2f}",
                               request.symbol,
                               retries_performed,
                               result.last_retcode,
                               requested_price,
                               last_quote_price,
                               is_market_request ? last_slippage_points : 0.0));
   }

   double final_slippage_pts = 0.0;
   if(snapshot_point > 0.0 && requested_price > 0.0 && result.executed_price > 0.0)
      final_slippage_pts = MathAbs(result.executed_price - requested_price) / snapshot_point;

   LogOE(StringFormat("ExecuteOrderWithRetry complete: success=%s retries=%d last_retcode=%d requested=%.5f executed=%.5f slippage=%.2f pts",
                      result.success ? "true" : "false",
                      result.retry_count,
                      result.last_retcode,
                      requested_price,
                      result.executed_price,
                      final_slippage_pts));

   if(result.success && result.ticket > 0 && !is_pending_request && IsMasterAccount())
   {
      TrackSLEnforcement(result.ticket, TimeCurrent());
      SaveSLEnforcementState();
   }

   return result.success;
}

bool OrderEngine::ExecuteMarketFallback(const OrderRequest &pending_request,
                                        const double evaluated_risk,
                                        OrderResult &result)
{
   const ENUM_ORDER_TYPE market_type = MarketTypeFromPending(pending_request.type);
   if(!IsMarketOrderType(market_type))
   {
      LogOE(StringFormat("Market fallback unavailable for pending type %s",
                         EnumToString(pending_request.type)));
      return false;
   }

   OrderRequest market_request = pending_request;
   market_request.type = market_type;
   market_request.expiry = 0;

   if(StringFind(market_request.comment, "fallback") < 0)
   {
      if(StringLen(market_request.comment) > 0)
         market_request.comment = market_request.comment + "|fallback";
      else
         market_request.comment = "market-fallback";
   }

   int total_positions = 0;
   int symbol_positions = 0;
   int symbol_pending = 0;
   string violation_reason = "";

   if(!EvaluatePositionCaps(market_request,
                            false,
                            total_positions,
                            symbol_positions,
                            symbol_pending,
                            violation_reason))
   {
      LogOE(StringFormat("Market fallback blocked by caps: %s", violation_reason));
      result.success = false;
      result.ticket = 0;
      result.executed_price = 0.0;
      result.executed_volume = 0.0;
      result.retry_count = 0;
      result.last_retcode = TRADE_RETCODE_PRICE_OFF;
      result.error_message = StringFormat("Market fallback blocked: %s", violation_reason);
      return false;
   }

   const int projected_total = total_positions + 1;
   const int projected_symbol_positions = symbol_positions + 1;
   const int projected_symbol_pending = symbol_pending;

   double point = 0.0;
   int digits = 0;
   double bid = 0.0;
   double ask = 0.0;
   if(!OE_GetLatestQuote("ExecuteMarketFallback",
                         market_request.symbol,
                         point,
                         digits,
                         bid,
                         ask))
   {
      LogOE(StringFormat("Market fallback failed: unable to get quote for %s",
                         market_request.symbol));
      result.success = false;
      result.ticket = 0;
      result.executed_price = 0.0;
      result.executed_volume = 0.0;
      result.retry_count = 0;
      result.last_retcode = TRADE_RETCODE_PRICE_OFF;
      result.error_message = "Market fallback failed: unable to get current price";
      return false;
   }

   const bool is_buy = IsBuyDirection(market_request.type);
   double entry_price = is_buy ? (ask > 0.0 ? ask : bid) : (bid > 0.0 ? bid : ask);
   if(entry_price <= 0.0)
   {
      LogOE(StringFormat("Market fallback failed: invalid quote (bid=%.5f ask=%.5f)",
                         bid,
                         ask));
      result.success = false;
      result.ticket = 0;
      result.executed_price = 0.0;
      result.executed_volume = 0.0;
      result.retry_count = 0;
      result.last_retcode = TRADE_RETCODE_PRICE_OFF;
      result.error_message = "Market fallback failed: invalid quote";
      return false;
   }

   entry_price = OE_NormalizePrice(market_request.symbol, entry_price);

   double entry_slippage_pts = 0.0;
   if(point > 0.0 && pending_request.price > 0.0)
      entry_slippage_pts = MathAbs(entry_price - pending_request.price) / point;
   if(m_max_slippage_points > 0.0 && entry_slippage_pts > (m_max_slippage_points + 1e-6))
   {
      result.success = false;
      result.ticket = 0;
      result.executed_price = entry_price;
      result.executed_volume = 0.0;
      result.retry_count = 0;
      result.last_retcode = TRADE_RETCODE_PRICE_OFF;
      result.error_message = StringFormat("Slippage %.2f pts exceeds MaxSlippagePoints %.2f",
                                          entry_slippage_pts,
                                          m_max_slippage_points);
      LogOE(StringFormat("Market fallback rejected due to slippage: requested=%.5f market=%.5f slippage=%.2f pts limit=%.2f",
                         pending_request.price,
                         entry_price,
                         entry_slippage_pts,
                         m_max_slippage_points));
      LogDecision("OrderEngine",
                  "MARKET_FALLBACK_SLIPPAGE_REJECT",
                  StringFormat("{\"symbol\":\"%s\",\"requested\":%.5f,\"market\":%.5f,\"slippage_pts\":%.2f,\"max_pts\":%.2f}",
                               market_request.symbol,
                               pending_request.price,
                               entry_price,
                               entry_slippage_pts,
                               m_max_slippage_points));
      return false;
   }

   bool risk_ok = true;
   double risk_value = evaluated_risk;

   if(g_oe_risk_override.active)
   {
      risk_ok = g_oe_risk_override.ok;
      risk_value = g_oe_risk_override.risk_value;
   }
   else
   {
      risk_ok = false;
      risk_value = Equity_CalcRiskDollars(market_request.symbol,
                                          market_request.volume,
                                          entry_price,
                                          market_request.sl,
                                          risk_ok);
   }

   if(!risk_ok || risk_value <= 0.0)
   {
      LogOE("Market fallback blocked: unable to evaluate risk for market execution");
      result.success = false;
      result.ticket = 0;
      result.executed_price = 0.0;
      result.executed_volume = 0.0;
      result.retry_count = 0;
      result.last_retcode = TRADE_RETCODE_INVALID_PRICE;
      result.error_message = "Market fallback failed: risk evaluation failed";
      return false;
   }

   LogOE("Converting pending to market for fallback execution");
   LogDecision("OrderEngine",
               "MARKET_FALLBACK_INIT",
               StringFormat("{\"symbol\":\"%s\",\"pending_type\":\"%s\",\"market_type\":\"%s\",\"volume\":%.4f,\"requested\":%.5f}",
                            market_request.symbol,
                            EnumToString(pending_request.type),
                            EnumToString(market_request.type),
                            market_request.volume,
                            pending_request.price));

   const bool executed = ExecuteOrderWithRetry(market_request,
                                               false,
                                               risk_value,
                                               projected_total,
                                               projected_symbol_positions,
                                               projected_symbol_pending,
                                               result);
   return executed;
}

void OrderEngine::EnsureSLEnforcementLoaded()
{
   if(m_sl_state_loaded)
      return;
   m_sl_state_loaded = true;
   m_sl_enforcement_count = 0;
   ArrayResize(m_sl_enforcement_queue, 0);

   string contents = Persistence_ReadWholeFile(FILE_SL_ENFORCEMENT);
   if(StringLen(contents) == 0)
      return;

   string objects[];
   if(!Persistence_SplitJsonArrayObjects(contents, objects))
      return;

   const int count = ArraySize(objects);
   if(count <= 0)
      return;

   ArrayResize(m_sl_enforcement_queue, count);
   for(int i = 0; i < count; i++)
   {
      string obj = objects[i];
      if(StringLen(obj) == 0)
         continue;

      SLEnforcementEntry entry;
      ZeroMemory(entry);
      entry.active = true;
      ulong ticket = 0;
      if(!Persistence_ParseULongField(obj, "ticket", ticket) || ticket == 0)
         continue;
      entry.ticket = ticket;

      string str_value = "";
      if(Persistence_ParseStringField(obj, "open_time", str_value))
         entry.open_time = Persistence_ParseIso8601(str_value);
      if(Persistence_ParseStringField(obj, "sl_set_time", str_value))
         entry.sl_set_time = Persistence_ParseIso8601(str_value);
      if(Persistence_ParseStringField(obj, "status", str_value))
         entry.status = str_value;
      if(Persistence_ParseStringField(obj, "sl_set_within_30s", str_value))
      {
         StringToLower(str_value);
         entry.sl_set_within_30s = (str_value == "true");
      }
      else
      {
         entry.sl_set_within_30s = false;
      }

      if(entry.open_time <= 0)
         entry.open_time = TimeCurrent();
      if(StringLen(entry.status) == 0)
         entry.status = "PENDING";

      if(m_sl_enforcement_count >= ArraySize(m_sl_enforcement_queue))
         ArrayResize(m_sl_enforcement_queue, m_sl_enforcement_count + 4);
      m_sl_enforcement_queue[m_sl_enforcement_count++] = entry;
   }
}

void OrderEngine::TrackSLEnforcement(const ulong ticket, const datetime open_time)
{
   if(ticket == 0)
      return;
   EnsureSLEnforcementLoaded();

   for(int i = 0; i < m_sl_enforcement_count; i++)
   {
      if(m_sl_enforcement_queue[i].ticket == ticket)
      {
         m_sl_enforcement_queue[i].open_time = open_time;
         m_sl_enforcement_queue[i].sl_set_time = 0;
         m_sl_enforcement_queue[i].sl_set_within_30s = false;
         m_sl_enforcement_queue[i].status = "PENDING";
         m_sl_enforcement_queue[i].active = true;
         SaveSLEnforcementState();
         return;
      }
   }

   if(ArraySize(m_sl_enforcement_queue) <= m_sl_enforcement_count)
      ArrayResize(m_sl_enforcement_queue, m_sl_enforcement_count + 4);

   SLEnforcementEntry entry;
   ZeroMemory(entry);
   entry.ticket = ticket;
   entry.open_time = open_time;
   entry.sl_set_time = 0;
   entry.sl_set_within_30s = false;
   entry.status = "PENDING";
   entry.active = true;

   m_sl_enforcement_queue[m_sl_enforcement_count++] = entry;
   SaveSLEnforcementState();
}

void OrderEngine::RemoveSLEnforcementAt(const int index)
{
   if(index < 0 || index >= m_sl_enforcement_count)
      return;

   for(int i = index; i < m_sl_enforcement_count - 1; i++)
      m_sl_enforcement_queue[i] = m_sl_enforcement_queue[i + 1];

   m_sl_enforcement_count = MathMax(0, m_sl_enforcement_count - 1);
}

bool OrderEngine::GetPositionSLByTicket(const ulong ticket,
                                        double &out_sl,
                                        datetime &out_open_time) const
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong pos_ticket = PositionGetTicket(i);
      if(pos_ticket == ticket)
      {
         out_sl = PositionGetDouble(POSITION_SL);
         out_open_time = (datetime)PositionGetInteger(POSITION_TIME);
         return true;
      }
   }
   out_sl = 0.0;
   out_open_time = 0;
   return false;
}

void OrderEngine::CheckPendingSLEnforcementInternal()
{
   EnsureSLEnforcementLoaded();
   if(m_sl_enforcement_count <= 0)
      return;

   const datetime now = TimeCurrent();
   bool state_dirty = false;

   for(int i = 0; i < m_sl_enforcement_count; )
   {
      SLEnforcementEntry entry = m_sl_enforcement_queue[i];
      if(!entry.active)
      {
         RemoveSLEnforcementAt(i);
         state_dirty = true;
         continue;
      }

      double sl_value = 0.0;
      datetime pos_open_time = 0;
      const bool has_position = GetPositionSLByTicket(entry.ticket, sl_value, pos_open_time);

      if(!has_position)
      {
         entry.status = "UNKNOWN_POSITION";
         entry.active = false;
         LogDecision("OrderEngine",
                     "SL_ENFORCEMENT_DROP",
                     StringFormat("{\"ticket\":%llu,\"reason\":\"position_missing\"}", entry.ticket));
         RemoveSLEnforcementAt(i);
         state_dirty = true;
         continue;
      }

      const double elapsed = (double)(now - entry.open_time);

      if(sl_value > 0.0)
      {
         entry.sl_set_time = now;
         entry.sl_set_within_30s = (elapsed <= 30.0 + 1e-6);
         entry.status = (entry.sl_set_within_30s ? "ON_TIME" : "LATE");
         entry.active = false;
         LogDecision("OrderEngine",
                     "SL_ENFORCEMENT_SET",
                     StringFormat("{\"ticket\":%llu,\"elapsed\":%.1f,\"status\":\"%s\"}",
                                  entry.ticket,
                                  elapsed,
                                  entry.status));
         RemoveSLEnforcementAt(i);
         state_dirty = true;
         continue;
      }

      if(elapsed >= 30.0 && entry.status != "MISSING")
      {
         entry.status = "MISSING";
         LogDecision("OrderEngine",
                     "SL_ENFORCEMENT_MISSING",
                     StringFormat("{\"ticket\":%llu,\"elapsed\":%.1f}", entry.ticket, elapsed));
         m_sl_enforcement_queue[i] = entry;
         state_dirty = true;
         i++;
         continue;
      }

      m_sl_enforcement_queue[i] = entry;
      i++;
   }

   if(state_dirty)
      SaveSLEnforcementState();
}

bool OrderEngine::IsMasterAccount() const
{
   long trade_mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(trade_mode != ACCOUNT_TRADE_MODE_REAL)
      return false;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return (MathIsValidNumber(balance) && balance >= 25000.0);
}

void OrderEngine::AppendLogLine(const string line)
{
   if(m_log_buffer_size <= 0)
      return;

   if(m_log_buffer_count >= m_log_buffer_size)
   {
      for(int i = 1; i < m_log_buffer_count; i++)
         m_log_buffer[i - 1] = m_log_buffer[i];
      m_log_buffer_count = m_log_buffer_size - 1;
   }

   int current_capacity = ArraySize(m_log_buffer);
   if(current_capacity <= m_log_buffer_count)
   {
      int desired = m_log_buffer_count + 1;
      int growth = desired;
      if(growth < 16)
         growth = 16;
      if(m_log_buffer_size > 0 && growth < m_log_buffer_size)
         growth = m_log_buffer_size;
      ArrayResize(m_log_buffer, growth);
   }

   m_log_buffer[m_log_buffer_count] = line;
   m_log_buffer_count++;
   m_log_buffer_dirty = true;
}

void OrderEngine::FlushLogBuffer()
{
   if(!m_log_buffer_dirty || m_log_buffer_count <= 0)
      return;

   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   string ymd = StringFormat("%04d%02d%02d", tm.year, tm.mon, tm.day);
   string path = StringFormat("%s/order_engine_trace_%s.csv", RPEA_LOGS_DIR, ymd);

   FolderCreate(RPEA_DIR);
   FolderCreate(RPEA_LOGS_DIR);

   ResetLastError();
   int handle = FileOpen(path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      const int err = GetLastError();
      PrintFormat("[OrderEngine] FlushLogBuffer: unable to open %s (err=%d)", path, err);
      ResetLastError();
      return;
   }

   bool need_header = (FileSize(handle) == 0);
   FileSeek(handle, 0, SEEK_END);
   if(need_header)
      FileWrite(handle, "timestamp,message");

   for(int i = 0; i < m_log_buffer_count; i++)
      FileWrite(handle, m_log_buffer[i]);

   FileClose(handle);

   ArrayResize(m_log_buffer, 0);
   m_log_buffer_count = 0;
   m_log_buffer_dirty = false;
}

void OrderEngine::MarkJournalDirty()
{
   m_intent_journal_dirty = true;
}

void OrderEngine::PersistIntentJournal()
{
   if(!m_intent_journal_dirty)
      return;
   SyncEngineStateToJournal();
   if(!IntentJournal_Save(m_intent_journal))
   {
      PrintFormat("[OrderEngine] PersistIntentJournal: failed to save %s", FILE_INTENTS);
      return;
   }
   m_intent_journal_dirty = false;
}

void OrderEngine::LoadResilienceConfig()
{
   m_resilience_max_failures = Config_GetMaxConsecutiveFailures();
   m_resilience_failure_window_sec = Config_GetFailureWindowSec();
   m_resilience_breaker_cooldown_sec = Config_GetCircuitBreakerCooldownSec();
   m_resilience_self_heal_window_sec = Config_GetSelfHealRetryWindowSec();
   m_resilience_self_heal_max_attempts = Config_GetSelfHealMaxAttempts();
   m_resilience_alert_throttle_sec = Config_GetErrorAlertThrottleSec();
   m_resilience_protective_bypass = Config_GetBreakerProtectiveExitBypass();
}

void OrderEngine::RestoreEngineStateFromJournal()
{
   PersistedEngineState state = m_intent_journal.engine_state;
   m_consecutive_failures = state.consecutive_failures;
   m_failure_window_count = state.failure_window_count;
   m_failure_window_start = state.failure_window_start;
   m_last_failure_time = state.last_failure_time;
   m_circuit_breaker_until = state.circuit_breaker_until;
   m_breaker_reason = state.breaker_reason;
   m_last_alert_time = state.last_alert_time;
   m_self_heal_active = state.self_heal_active;
   m_self_heal_attempts = state.self_heal_attempts;
   m_self_heal_reason = state.self_heal_reason;
   m_next_self_heal_time = state.next_self_heal_time;
}

void OrderEngine::SyncEngineStateToJournal()
{
   PersistedEngineState state = m_intent_journal.engine_state;
   state.consecutive_failures = m_consecutive_failures;
   state.failure_window_count = m_failure_window_count;
   state.failure_window_start = m_failure_window_start;
   state.last_failure_time = m_last_failure_time;
   state.circuit_breaker_until = m_circuit_breaker_until;
   state.breaker_reason = m_breaker_reason;
   state.last_alert_time = m_last_alert_time;
   state.self_heal_active = m_self_heal_active;
   state.self_heal_attempts = m_self_heal_attempts;
   state.self_heal_reason = m_self_heal_reason;
   state.next_self_heal_time = m_next_self_heal_time;
   m_intent_journal.engine_state = state;
}

bool OrderEngine::OrderEngine_IsCircuitBreakerActive()
{
   if(m_circuit_breaker_until <= 0)
      return false;
   datetime now = TimeCurrent();
   if(now >= m_circuit_breaker_until)
   {
      OrderEngine_ResetCircuitBreaker("cooldown_elapsed");
      return false;
   }
   return true;
}

bool OrderEngine::OrderEngine_ShouldBypassBreaker(const bool protective) const
{
   if(!protective)
      return false;
   return m_resilience_protective_bypass;
}

bool OrderEngine::OrderEngine_ShouldBypassBreaker(const OrderError &err) const
{
   return OrderEngine_ShouldBypassBreaker(err.is_protective_exit);
}

void OrderEngine::OrderEngine_RecordFailure(const datetime now)
{
   if(m_failure_window_start <= 0 || (now - m_failure_window_start) > m_resilience_failure_window_sec)
   {
      m_failure_window_start = now;
      m_failure_window_count = 0;
   }
   m_failure_window_count++;
   m_consecutive_failures++;
   m_last_failure_time = now;
}

void OrderEngine::OrderEngine_RecordSuccess()
{
   m_consecutive_failures = 0;
   m_failure_window_count = 0;
   m_failure_window_start = TimeCurrent();
   m_last_failure_time = 0;
   if(m_self_heal_active)
   {
      m_self_heal_active = false;
      m_self_heal_reason = "";
      m_next_self_heal_time = 0;
      m_self_heal_attempts = 0;
   }
   if(m_circuit_breaker_until > 0 && !OrderEngine_IsCircuitBreakerActive())
      OrderEngine_ResetCircuitBreaker("success");
}

void OrderEngine::OrderEngine_TripCircuitBreaker(const string reason)
{
   datetime now = TimeCurrent();
   m_circuit_breaker_until = now + m_resilience_breaker_cooldown_sec;
   m_breaker_reason = reason;
   m_consecutive_failures = 0;
   m_failure_window_count = 0;
   m_failure_window_start = now;
   OrderEngine_ScheduleSelfHeal(reason);
   MarkJournalDirty();
   string fields = StringFormat("{\"reason\":\"%s\",\"until\":%d}", reason, (int)m_circuit_breaker_until);
   LogDecision("OrderEngine", "BREAKER_TRIP", fields);
}

void OrderEngine::OrderEngine_ResetCircuitBreaker(const string source)
{
   m_circuit_breaker_until = 0;
   m_breaker_reason = "";
   m_self_heal_active = false;
   m_self_heal_reason = "";
   m_next_self_heal_time = 0;
    m_self_heal_attempts = 0;
   MarkJournalDirty();
   string fields = StringFormat("{\"source\":\"%s\"}", source);
   LogDecision("OrderEngine", "BREAKER_RESET", fields);
}

void OrderEngine::OrderEngine_ScheduleSelfHeal(const string reason)
{
   if(m_resilience_self_heal_max_attempts <= 0)
      return;
   if(m_self_heal_attempts >= m_resilience_self_heal_max_attempts)
      return;
   datetime now = TimeCurrent();
   if(m_self_heal_active && now < m_next_self_heal_time)
      return;
   m_self_heal_active = true;
   m_self_heal_attempts++;
   m_self_heal_reason = reason;
   m_next_self_heal_time = now + m_resilience_self_heal_window_sec;
   MarkJournalDirty();
}

void OrderEngine::OrderEngine_LogErrorHandling(const OrderError &err,
                                               const OrderErrorDecision &decision)
{
   string json = StringFormat("{\"context\":\"%s\",\"retcode\":%d,\"class\":\"%s\",\"decision\":%d,\"gating\":\"%s\",\"attempt\":%d,\"breaker_until\":%d,\"failures\":%d}",
                              err.context,
                              err.retcode,
                              OE_ErrorClassName(err.cls),
                              (int)decision.type,
                              decision.gating_reason,
                              err.attempt,
                              (int)m_circuit_breaker_until,
                              m_consecutive_failures);
   LogDecision("OrderEngine", "ERROR_HANDLING", json);
   datetime now = TimeCurrent();
   if(decision.type == ERROR_DECISION_FAIL_FAST && m_resilience_alert_throttle_sec > 0)
   {
      if(m_last_alert_time <= 0 || (now - m_last_alert_time) >= m_resilience_alert_throttle_sec)
      {
         PrintFormat("[OrderEngine][ErrorHandling] %s ret=%d cls=%s decision=%d reason=%s",
                     err.context,
                     err.retcode,
                     OE_ErrorClassName(err.cls),
                     (int)decision.type,
                     decision.gating_reason);
         m_last_alert_time = now;
      }
   }
#ifdef RPEA_TEST_RUNNER
   OE_Test_CaptureDecision("ERROR_HANDLING", json);
#endif
}

OrderErrorDecision OrderEngine::OrderEngine_HandleError(const OrderError &err)
{
   OrderErrorDecision decision;
   datetime now = TimeCurrent();
   const bool bypass = OrderEngine_ShouldBypassBreaker(err);
   if(OrderEngine_IsCircuitBreakerActive() && !bypass)
   {
      decision.type = ERROR_DECISION_FAIL_FAST;
      decision.gating_reason = "circuit_breaker_active";
      OrderEngine_LogErrorHandling(err, decision);
      return decision;
   }

   if(OE_ShouldFailFast(err.cls) && !bypass)
   {
      decision.type = ERROR_DECISION_FAIL_FAST;
      decision.gating_reason = "fail_fast";
      if(!bypass)
         OrderEngine_RecordFailure(now);
      OrderEngine_TripCircuitBreaker("fail_fast:" + err.context);
      OrderEngine_LogErrorHandling(err, decision);
      return decision;
   }

   if(!bypass)
      OrderEngine_RecordFailure(now);

   RetryPolicy policy = m_retry_manager.GetPolicyForError(err.retcode);
   bool allow_retry = (OE_ShouldRetryClass(err.cls) && m_retry_manager.ShouldRetry(policy, err.attempt));
   if(allow_retry && (!OrderEngine_IsCircuitBreakerActive() || bypass))
   {
      decision.type = ERROR_DECISION_RETRY;
      decision.retry_delay_ms = m_retry_manager.CalculateDelayMs(err.attempt + 1, policy);
   }
   else
   {
      decision.type = ERROR_DECISION_DROP;
      decision.gating_reason = (allow_retry ? "" : "retry_exhausted");
   }

   OrderEngine_LogErrorHandling(err, decision);

   if(!bypass && (m_consecutive_failures >= m_resilience_max_failures ||
      m_failure_window_count >= m_resilience_max_failures))
   {
      if(!OrderEngine_IsCircuitBreakerActive())
         OrderEngine_TripCircuitBreaker("threshold:" + err.context);
   }

   return decision;
}

void OrderEngine::TouchJournalSequences()
{
   int max_intent_seq = 0;
   int max_action_seq = 0;
   IntentJournal_TouchSequences(m_intent_journal, max_intent_seq, max_action_seq);
   m_intent_sequence = max_intent_seq;
   m_action_sequence = max_action_seq;
}

void OrderEngine::LoadIntentJournal()
{
   if(!IntentJournal_Load(m_intent_journal))
   {
      PrintFormat("[OrderEngine] LoadIntentJournal: failed to load %s", FILE_INTENTS);
      IntentJournal_Clear(m_intent_journal);
   }
   TouchJournalSequences();
   m_intent_journal_dirty = false;
}

void OrderEngine::CleanupExpiredJournalEntries(const datetime now)
{
   const datetime intent_cutoff = now - OE_INTENT_TTL_MINUTES * 60;
   const datetime action_cutoff = now - OE_ACTION_TTL_MINUTES * 60;
   bool removed_any = false;

   int new_intent_count = 0;
   for(int i = 0; i < ArraySize(m_intent_journal.intents); ++i)
   {
      OrderIntent intent = m_intent_journal.intents[i];
      bool keep = true;
      if(intent.status != "PENDING")
      {
         if(intent.timestamp > 0 && intent.timestamp < intent_cutoff)
            keep = false;
         if(intent.expiry > 0 && intent.expiry < now - m_pending_expiry_grace_seconds)
            keep = false;
      }

      if(keep)
      {
         if(new_intent_count != i)
            m_intent_journal.intents[new_intent_count] = intent;
         new_intent_count++;
      }
      else
      {
         removed_any = true;
         LogOE(StringFormat("CleanupExpiredJournalEntries: removed intent %s status=%s", intent.intent_id, intent.status));
      }
   }
   if(new_intent_count != ArraySize(m_intent_journal.intents))
      ArrayResize(m_intent_journal.intents, new_intent_count);

   int new_action_count = 0;
   for(int j = 0; j < ArraySize(m_intent_journal.queued_actions); ++j)
   {
      PersistedQueuedAction action = m_intent_journal.queued_actions[j];
      bool keep = true;
      if(action.expires_time > 0 && action.expires_time < now)
         keep = false;
      if(action.queued_time > 0 && action.queued_time < action_cutoff)
         keep = false;

      if(keep)
      {
         if(new_action_count != j)
            m_intent_journal.queued_actions[new_action_count] = action;
         new_action_count++;
      }
      else
      {
         removed_any = true;
         LogOE(StringFormat("CleanupExpiredJournalEntries: removed action %s", action.action_id));
      }
   }
   if(new_action_count != ArraySize(m_intent_journal.queued_actions))
      ArrayResize(m_intent_journal.queued_actions, new_action_count);

   if(removed_any)
      MarkJournalDirty();
}

string OrderEngine::GenerateIntentId(const datetime now)
{
   if(m_intent_sequence >= 999)
      m_intent_sequence = 0;
   ++m_intent_sequence;
   MqlDateTime dt;
   TimeToStruct(now, dt);
   return StringFormat("rpea_%04d%02d%02d_%02d%02d%02d_%03d",
                       dt.year, dt.mon, dt.day,
                       dt.hour, dt.min, dt.sec,
                       m_intent_sequence);
}

ulong OrderEngine::HashString64(const string text) const
{
   const ulong FNV_OFFSET = 1469598103934665603;
   const ulong FNV_PRIME = 1099511628211;
   ulong hash = FNV_OFFSET;
   int len = StringLen(text);
   for(int i = 0; i < len; ++i)
   {
      ulong value = (ulong)StringGetCharacter(text, i) & 0xFF;
      hash ^= value;
      hash *= FNV_PRIME;
   }
   return hash;
}

string OrderEngine::HashToHex(const ulong value) const
{
   string hex = "";
   ulong temp = value;
   for(int i = 0; i < 16; ++i)
   {
      int nibble = (int)(temp & 0x0F);
      char ch = (char)(nibble < 10 ? ('0' + nibble) : ('a' + (nibble - 10)));
      hex = (string)ch + hex;
      temp >>= 4;
   }
   return hex;
}

string OrderEngine::BuildIntentAcceptKey(const OrderRequest &request) const
{
   string base = StringFormat("%s|%s|%.5f|%.5f|%.5f|%.4f|%lld|%d|%llu|%d",
                              request.symbol,
                              EnumToString(request.type),
                              request.price,
                              request.sl,
                              request.tp,
                              request.volume,
                              (long)request.expiry,
                              request.is_oco_primary ? 1 : 0,
                              request.oco_sibling_ticket,
                              request.magic);
   ulong hash = HashString64(base);
   string accept_key = "intent_" + HashToHex(hash);
   return accept_key;
}

void OrderEngine::Audit_LogIntentEvent(const OrderIntent &intent,
                                       const string action_suffix,
                                       const string decision,
                                       const double requested_price,
                                       const double executed_price,
                                       const double requested_vol,
                                       const double filled_vol,
                                       const double remaining_vol,
                                       const int retry_count,
                                       const string gating_reason_override,
                                       const string news_state_override)
{
   AuditRecord record;
   record.timestamp = TimeCurrent();
   string suffix = action_suffix;
   if(StringLen(suffix) == 0)
      suffix = ":EVENT";
   record.intent_id = intent.intent_id;
   record.action_id = intent.intent_id + suffix;
   record.symbol = intent.symbol;
   record.mode = intent.execution_mode;
   record.requested_price = requested_price;
   record.executed_price = executed_price;
   record.requested_vol = requested_vol;
   record.filled_vol = filled_vol;
   record.remaining_vol = remaining_vol;
   ArrayCopy(record.tickets, intent.executed_tickets);
   record.retry_count = retry_count;
   record.gate_open_risk = intent.gate_open_risk;
   record.gate_pending_risk = intent.gate_pending_risk;
   record.gate_next_risk = intent.gate_next_risk;
   record.room_today = intent.room_today;
   record.room_overall = intent.room_overall;
   record.gate_pass = intent.gate_pass;
   record.decision = decision;
   record.confidence = intent.confidence;
   record.efficiency = intent.efficiency;
   record.rho_est = intent.rho_est;
   record.est_value = intent.est_value;
   record.hold_time = intent.hold_time_seconds;
   string gating_reason = intent.gating_reason;
   if(intent.is_proxy)
     {
      string proxy_info = intent.proxy_context;
      if(StringLen(proxy_info) == 0 && intent.signal_symbol != "" && intent.symbol != intent.signal_symbol)
         proxy_info = StringFormat("%s->%s rate=%.5f",
                                   intent.signal_symbol,
                                   intent.symbol,
                                   intent.proxy_rate);
      if(StringLen(proxy_info) > 0 && StringFind(gating_reason, proxy_info) < 0)
      {
         if(StringLen(gating_reason) > 0)
            gating_reason = gating_reason + "|" + proxy_info;
         else
            gating_reason = proxy_info;
      }
     }
   record.gating_reason = (StringLen(gating_reason_override) > 0 ? gating_reason_override : gating_reason);
   record.news_window_state = (StringLen(news_state_override) > 0 ? news_state_override : intent.news_window_state);
   AuditLogger_Log(record);
}

// Partial fill state management helpers (Task 8)
int OrderEngine::FindPartialFillState(const ulong ticket) const
{
   for(int i = 0; i < m_partial_fill_count; i++)
   {
      if(m_partial_fill_states[i].ticket == ticket)
         return i;
   }
   return -1;
}

int OrderEngine::FindOrCreatePartialFillState(const ulong ticket, const double requested_volume)
{
   int idx = FindPartialFillState(ticket);
   if(idx >= 0)
      return idx;
   
   // Grow array if needed
   if(m_partial_fill_count >= ArraySize(m_partial_fill_states))
   {
      if(ArrayResize(m_partial_fill_states, m_partial_fill_count + 10) < 0)
      {
         LogOE("FindOrCreatePartialFillState: Failed to resize array");
         return -1;
      }
   }
   
   m_partial_fill_states[m_partial_fill_count].ticket = ticket;
   m_partial_fill_states[m_partial_fill_count].requested_volume = requested_volume;
   m_partial_fill_states[m_partial_fill_count].filled_volume = 0.0;
   m_partial_fill_states[m_partial_fill_count].remaining_volume = requested_volume;
   m_partial_fill_states[m_partial_fill_count].first_fill_time = TimeCurrent();
   m_partial_fill_states[m_partial_fill_count].last_fill_time = TimeCurrent();
   m_partial_fill_states[m_partial_fill_count].fill_count = 0;
   return m_partial_fill_count++;
}

void OrderEngine::ClearPartialFillState(const int index)
{
   if(index < 0 || index >= m_partial_fill_count)
      return;
   
   // Shift array down
   for(int i = index; i < m_partial_fill_count - 1; i++)
      m_partial_fill_states[i] = m_partial_fill_states[i + 1];
   m_partial_fill_count--;
}

void OrderEngine::ClearPartialFillStateByTicket(const ulong ticket)
{
   int idx = FindPartialFillState(ticket);
   if(idx >= 0)
      ClearPartialFillState(idx);
}

bool OrderEngine::IntentExists(const string accept_key, int &out_index) const
{
   out_index = IntentJournal_FindIntentByAcceptKey(m_intent_journal, accept_key);
   return (out_index >= 0);
}

bool OrderEngine::FindIntentByTicket(const ulong ticket,
                                     string &out_intent_id,
                                     string &out_accept_key) const
{
   out_intent_id = "";
   out_accept_key = "";
   for(int i = 0; i < ArraySize(m_intent_journal.intents); ++i)
   {
      OrderIntent intent = m_intent_journal.intents[i];
      for(int j = 0; j < ArraySize(intent.executed_tickets); ++j)
      {
         if(intent.executed_tickets[j] == ticket)
         {
            out_intent_id = intent.intent_id;
            out_accept_key = intent.accept_once_key;
            return true;
         }
      }
   }
   return false;
}

int OrderEngine::FindIntentIndexById(const string intent_id) const
{
   for(int i = 0; i < ArraySize(m_intent_journal.intents); ++i)
   {
      if(m_intent_journal.intents[i].intent_id == intent_id)
         return i;
   }
   return -1;
}

bool OrderEngine::FindIntentById(const string intent_id, OrderIntent &out_intent) const
{
   int idx = FindIntentIndexById(intent_id);
   if(idx < 0)
      return false;
   out_intent = m_intent_journal.intents[idx];
   return true;
}

bool OrderEngine::MatchIntentByTicket(const ulong ticket, OrderIntent &out_intent) const
{
   for(int i = 0; i < ArraySize(m_intent_journal.intents); ++i)
   {
      OrderIntent intent = m_intent_journal.intents[i];
      for(int j = 0; j < ArraySize(intent.executed_tickets); ++j)
      {
         if(intent.executed_tickets[j] == ticket)
         {
            out_intent = intent;
            return true;
         }
      }
   }
   return false;
}

void OrderEngine::ResetState()
{
   m_oco_count = 0;
   m_execution_locked = false;
   m_consecutive_failures = 0;
   m_failure_window_count = 0;
   m_failure_window_start = (datetime)0;
   m_last_failure_time = (datetime)0;
   m_circuit_breaker_until = (datetime)0;
   m_breaker_reason = "";
   m_last_alert_time = (datetime)0;
   m_self_heal_active = false;
   m_self_heal_attempts = 0;
   m_self_heal_reason = "";
   m_next_self_heal_time = (datetime)0;
   m_sl_enforcement_count = 0;
   m_sl_state_loaded = false;
   ArrayResize(m_sl_enforcement_queue, 0);
   ArrayResize(m_recovered_intents, 0);
   ArrayResize(m_recovered_actions, 0);
   m_recovered_intent_count = 0;
   m_recovered_action_count = 0;
   m_recovery_completed = false;
   m_recovery_timestamp = 0;
}

string OrderEngine::FormatLogLine(const string message)
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   string timestamp = StringFormat("%04d-%02d-%02d %02d:%02d:%02d",
                                   tm.year, tm.mon, tm.day, tm.hour, tm.min, tm.sec);
   string sanitized = message;
   StringReplace(sanitized, "\"", "\"\"");
   StringReplace(sanitized, "\r", "");
   StringReplace(sanitized, "\n", "\\n");
   return StringFormat("%s,\"%s\"", timestamp, sanitized);
}

//==============================================================================
// Global OrderEngine Instance
//==============================================================================
extern OrderEngine g_order_engine;

bool OrderEngine_GetIntentMetadata(const ulong ticket,
                                   string &out_intent_id,
                                   string &out_accept_key)
{
   return g_order_engine.GetIntentMetadata(ticket, out_intent_id, out_accept_key);
}

bool OrderEngine_FindIntentById(const string intent_id, OrderIntent &out_intent)
{
   return g_order_engine.FindIntentById(intent_id, out_intent);
}

int OrderEngine_FindIntentIndexById(const string intent_id)
{
   return g_order_engine.FindIntentIndexById(intent_id);
}

bool OrderEngine_FindIntentByTicket(const ulong ticket, OrderIntent &out_intent)
{
   return g_order_engine.MatchIntentByTicket(ticket, out_intent);
}

//------------------------------------------------------------------------------
// Normalization overrides - used for deterministic unit testing (Task 3)
//------------------------------------------------------------------------------

struct OENormalizationOverrides
{
   bool     volume_active;
   string   volume_symbol;
   double   volume_step;
   double   volume_min;
   double   volume_max;

   bool     price_active;
   string   price_symbol;
   double   price_point;
   int      price_digits;
   double   price_bid;
   double   price_ask;
   int      price_stops_level;
};

static OENormalizationOverrides g_oe_norm_overrides =
{
   false, "", 0.0, 0.0, 0.0,
   false, "", 0.0, 0, 0.0, 0.0, 0
};

//------------------------------------------------------------------------------
// Position cap overrides for deterministic unit testing (Task 4)
//------------------------------------------------------------------------------

struct OECapOverrideState
{
   bool active;
   bool caps_ok;
   int  total_positions;
   int  symbol_positions;
   int  symbol_pending;
};

static OECapOverrideState g_oe_cap_override = {false, true, 0, 0, 0};

void OE_Test_SetCapOverride(const bool caps_ok,
                            const int total_positions,
                            const int symbol_positions,
                            const int symbol_pending)
{
   g_oe_cap_override.active = true;
   g_oe_cap_override.caps_ok = caps_ok;
   g_oe_cap_override.total_positions = total_positions;
   g_oe_cap_override.symbol_positions = symbol_positions;
   g_oe_cap_override.symbol_pending = symbol_pending;
}

void OE_Test_ClearCapOverride()
{
   g_oe_cap_override.active = false;
   g_oe_cap_override.caps_ok = true;
   g_oe_cap_override.total_positions = 0;
   g_oe_cap_override.symbol_positions = 0;
   g_oe_cap_override.symbol_pending = 0;
}

//------------------------------------------------------------------------------
// Risk override for deterministic unit testing (Task 4)
//------------------------------------------------------------------------------

struct OERiskOverrideState
{
   bool active;
   bool ok;
   double risk_value;
};

static OERiskOverrideState g_oe_risk_override = {false, true, 0.0};

void OE_Test_SetRiskOverride(const bool ok, const double risk_value)
{
   g_oe_risk_override.active = true;
   g_oe_risk_override.ok = ok;
   g_oe_risk_override.risk_value = risk_value;
}

void OE_Test_ClearRiskOverride()
{
   g_oe_risk_override.active = false;
   g_oe_risk_override.ok = true;
   g_oe_risk_override.risk_value = 0.0;
}

//------------------------------------------------------------------------------
// OrderSend override queue for deterministic retry testing (Task 5)
//------------------------------------------------------------------------------

struct OEOrderSendResponse
{
   bool   result_ok;
   int    retcode;
   ulong  order_ticket;
   ulong  deal_ticket;
   double price;
   double volume;
   string comment;
};

struct OEOrderSendOverrideState
{
   bool   active;
   int    call_count;
   int    current_index;
   OEOrderSendResponse responses[];
};

static OEOrderSendOverrideState g_oe_order_send_override;

void OE_Test_ClearOrderSendOverride()
{
   g_oe_order_send_override.active = false;
   g_oe_order_send_override.call_count = 0;
   g_oe_order_send_override.current_index = 0;
   ArrayResize(g_oe_order_send_override.responses, 0);
}

void OE_Test_EnableOrderSendOverride()
{
   g_oe_order_send_override.active = true;
   g_oe_order_send_override.call_count = 0;
   g_oe_order_send_override.current_index = 0;
   ArrayResize(g_oe_order_send_override.responses, 0);
}

void OE_Test_DisableOrderSendOverride()
{
   OE_Test_ClearOrderSendOverride();
}

void OE_Test_EnqueueOrderSendResponse(const bool result_ok,
                                      const int retcode,
                                      const ulong order_ticket,
                                      const ulong deal_ticket,
                                      const double price,
                                      const double volume,
                                      const string comment)
{
   if(!g_oe_order_send_override.active)
      OE_Test_EnableOrderSendOverride();

   const int size = ArraySize(g_oe_order_send_override.responses);
   ArrayResize(g_oe_order_send_override.responses, size + 1);
   g_oe_order_send_override.responses[size].result_ok = result_ok;
   g_oe_order_send_override.responses[size].retcode = retcode;
   g_oe_order_send_override.responses[size].order_ticket = order_ticket;
   g_oe_order_send_override.responses[size].deal_ticket = deal_ticket;
   g_oe_order_send_override.responses[size].price = price;
   g_oe_order_send_override.responses[size].volume = volume;
   g_oe_order_send_override.responses[size].comment = comment;
}

int OE_Test_GetOrderSendCallCount()
{
   return g_oe_order_send_override.call_count;
}

//------------------------------------------------------------------------------
// Retry delay capture for deterministic validation (Task 5)
//------------------------------------------------------------------------------

struct OERetryDelayCaptureState
{
   bool active;
   bool skip_sleep;
   int  delays[];
};

static OERetryDelayCaptureState g_oe_retry_delay_capture;

void OE_Test_ResetRetryDelayCapture()
{
   g_oe_retry_delay_capture.active = false;
   g_oe_retry_delay_capture.skip_sleep = false;
   ArrayResize(g_oe_retry_delay_capture.delays, 0);
}

void OE_Test_BeginRetryDelayCapture(const bool skip_sleep)
{
   g_oe_retry_delay_capture.active = true;
   g_oe_retry_delay_capture.skip_sleep = skip_sleep;
   ArrayResize(g_oe_retry_delay_capture.delays, 0);
}

void OE_Test_EndRetryDelayCapture()
{
   OE_Test_ResetRetryDelayCapture();
}

int OE_Test_GetCapturedDelayCount()
{
   return ArraySize(g_oe_retry_delay_capture.delays);
}

int OE_Test_GetCapturedDelay(const int index)
{
   const int count = ArraySize(g_oe_retry_delay_capture.delays);
   if(index < 0 || index >= count)
      return 0;
   return g_oe_retry_delay_capture.delays[index];
}

//------------------------------------------------------------------------------
// Internal OrderSend wrapper honoring overrides
//------------------------------------------------------------------------------

bool OE_OrderSend(const MqlTradeRequest &request, MqlTradeResult &result)
{
   if(g_oe_order_send_override.active)
   {
      g_oe_order_send_override.call_count++;

      const int idx = g_oe_order_send_override.current_index;
      const int total = ArraySize(g_oe_order_send_override.responses);
      if(idx >= total)
      {
         ZeroMemory(result);
         result.retcode = 0;
         return false;
      }

      const OEOrderSendResponse queued = g_oe_order_send_override.responses[idx];
      g_oe_order_send_override.current_index++;

      ZeroMemory(result);
      result.retcode = queued.retcode;
      result.order = queued.order_ticket;
      result.deal = queued.deal_ticket;
      result.price = queued.price;
      result.volume = queued.volume;
      result.comment = queued.comment;
      return queued.result_ok;
   }

#ifdef RPEA_ORDER_ENGINE_SKIP_RISK
#define RPEA_ORDER_ENGINE_SKIP_ORDERSEND_TMP
#endif
#ifdef RPEA_ORDER_ENGINE_SKIP_EQUITY
#define RPEA_ORDER_ENGINE_SKIP_ORDERSEND_TMP
#endif

#ifdef RPEA_ORDER_ENGINE_SKIP_ORDERSEND_TMP
   // Skip live OrderSend in test builds when no override is active
   ZeroMemory(result);
   result.retcode = TRADE_RETCODE_PRICE_OFF;
   return false;
#else
   ResetLastError();
   bool ok = OrderSend(request, result);
   if(!ok)
   {
      const int err = GetLastError();
      PrintFormat("[OrderEngine] OrderSend failed (err=%d, retcode=%d, comment=%s)",
                  err,
                  result.retcode,
                  result.comment);
      ResetLastError();
   }
   return ok;
#endif

#ifdef RPEA_ORDER_ENGINE_SKIP_ORDERSEND_TMP
#undef RPEA_ORDER_ENGINE_SKIP_ORDERSEND_TMP
#endif
}

//------------------------------------------------------------------------------
// Retry delay helper honoring capture overrides
//------------------------------------------------------------------------------

void OE_ApplyRetryDelay(const int delay_ms)
{
   if(delay_ms <= 0)
      return;

   if(g_oe_retry_delay_capture.active)
   {
      const int size = ArraySize(g_oe_retry_delay_capture.delays);
      ArrayResize(g_oe_retry_delay_capture.delays, size + 1);
      g_oe_retry_delay_capture.delays[size] = delay_ms;
      if(g_oe_retry_delay_capture.skip_sleep)
         return;
   }

   Sleep(delay_ms);
}

void OE_Test_SetVolumeOverride(const string symbol,
                               const double step,
                               const double min_volume,
                               const double max_volume)
{
   g_oe_norm_overrides.volume_active = true;
   g_oe_norm_overrides.volume_symbol = symbol;
   g_oe_norm_overrides.volume_step = step;
   g_oe_norm_overrides.volume_min = min_volume;
   g_oe_norm_overrides.volume_max = max_volume;
}

void OE_Test_SetPriceOverride(const string symbol,
                              const double point,
                              const int digits,
                              const double bid,
                              const double ask,
                              const int stops_level)
{
   g_oe_norm_overrides.price_active = true;
   g_oe_norm_overrides.price_symbol = symbol;
   g_oe_norm_overrides.price_point = point;
   g_oe_norm_overrides.price_digits = digits;
   g_oe_norm_overrides.price_bid = bid;
   g_oe_norm_overrides.price_ask = ask;
   g_oe_norm_overrides.price_stops_level = stops_level;
}

void OE_Test_ClearVolumeOverride()
{
   g_oe_norm_overrides.volume_active = false;
   g_oe_norm_overrides.volume_symbol = "";
   g_oe_norm_overrides.volume_step = 0.0;
   g_oe_norm_overrides.volume_min = 0.0;
   g_oe_norm_overrides.volume_max = 0.0;
}

void OE_Test_ClearPriceOverride()
{
   g_oe_norm_overrides.price_active = false;
   g_oe_norm_overrides.price_symbol = "";
   g_oe_norm_overrides.price_point = 0.0;
   g_oe_norm_overrides.price_digits = 0;
   g_oe_norm_overrides.price_bid = 0.0;
   g_oe_norm_overrides.price_ask = 0.0;
   g_oe_norm_overrides.price_stops_level = 0;
}

void OE_Test_ClearOverrides()
{
   OE_Test_ClearVolumeOverride();
   OE_Test_ClearPriceOverride();
   OE_Test_ClearCapOverride();
   OE_Test_ClearRiskOverride();
   OE_Test_ClearOrderSendOverride();
   OE_Test_ResetRetryDelayCapture();
}

void OE_Test_ResetIntentJournal()
{
   g_order_engine.TestResetIntentJournal();
}

bool OE_Test_IsRecoveryComplete()
{
   return g_order_engine.TestIsRecoveryComplete();
}

int OE_Test_GetRecoveredIntentCount()
{
   return g_order_engine.TestRecoveredIntentCount();
}

bool OE_Test_GetVolumeOverride(const string symbol,
                               double &step,
                               double &min_vol,
                               double &max_vol)
{
   if(!g_oe_norm_overrides.volume_active || g_oe_norm_overrides.volume_symbol != symbol)
      return false;

   step = g_oe_norm_overrides.volume_step;
   min_vol = g_oe_norm_overrides.volume_min;
   max_vol = g_oe_norm_overrides.volume_max;
   return true;
}

bool OE_Test_GetPriceOverride(const string symbol,
                              double &point,
                              int &digits,
                              double &bid,
                              double &ask,
                              int &stops_level)
{
   if(!g_oe_norm_overrides.price_active || g_oe_norm_overrides.price_symbol != symbol)
      return false;

   point = g_oe_norm_overrides.price_point;
   digits = g_oe_norm_overrides.price_digits;
   bid = g_oe_norm_overrides.price_bid;
   ask = g_oe_norm_overrides.price_ask;
   stops_level = g_oe_norm_overrides.price_stops_level;
   return true;
}

bool OE_GetLatestQuote(const string context,
                       const string symbol,
                       double &out_point,
                       int &out_digits,
                       double &out_bid,
                       double &out_ask)
{
   double override_point = 0.0;
   int override_digits = 0;
   double override_bid = 0.0;
   double override_ask = 0.0;
   int override_stops = 0;

   if(OE_Test_GetPriceOverride(symbol,
                               override_point,
                               override_digits,
                               override_bid,
                               override_ask,
                               override_stops))
   {
      out_point = override_point;
      out_digits = override_digits;
      out_bid = override_bid;
      out_ask = override_ask;
      return true;
   }

   out_point = 0.0;
   out_digits = 0;
   out_bid = 0.0;
   out_ask = 0.0;

   string ctx_point = StringFormat("%s::POINT", context);
   if(!OE_SymbolInfoDoubleSafe(ctx_point, symbol, SYMBOL_POINT, out_point))
      return false;

   long digits_long = 0;
   string ctx_digits = StringFormat("%s::DIGITS", context);
   if(OE_SymbolInfoIntegerSafe(ctx_digits, symbol, SYMBOL_DIGITS, digits_long))
      out_digits = (int)digits_long;
   else
      out_digits = 0;

   string ctx_bid = StringFormat("%s::BID", context);
   if(!OE_SymbolInfoDoubleSafe(ctx_bid, symbol, SYMBOL_BID, out_bid))
      return false;

   string ctx_ask = StringFormat("%s::ASK", context);
   if(!OE_SymbolInfoDoubleSafe(ctx_ask, symbol, SYMBOL_ASK, out_ask))
      return false;

   return true;
}

//------------------------------------------------------------------------------
// Internal normalization helpers (Task 3)
//------------------------------------------------------------------------------

bool OE_SymbolInfoDoubleSafe(const string context,
                             const string symbol,
                             const ENUM_SYMBOL_INFO_DOUBLE property,
                             double &out_value)
{
   ResetLastError();
   if(!SymbolInfoDouble(symbol, property, out_value))
   {
      const int err = GetLastError();
      PrintFormat("[OrderEngine] %s: SymbolInfoDouble(%s,%d) failed (err=%d)",
                  context, symbol, property, err);
      ResetLastError();
      return false;
   }
   return true;
}

bool OE_SymbolInfoIntegerSafe(const string context,
                              const string symbol,
                              const ENUM_SYMBOL_INFO_INTEGER property,
                              long &out_value)
{
   ResetLastError();
   if(!SymbolInfoInteger(symbol, property, out_value))
   {
      const int err = GetLastError();
      PrintFormat("[OrderEngine] %s: SymbolInfoInteger(%s,%d) failed (err=%d)",
                  context, symbol, property, err);
      ResetLastError();
      return false;
   }
   return true;
}

double OE_RoundToStep(const double value, const double step)
{
   if(step <= 0.0)
      return value;
   return MathRound(value / step) * step;
}

bool OE_ValidateVolumeRange(const string context,
                            const string symbol,
                            const double value,
                            const double min_value,
                            const double max_value)
{
   const double tolerance = MathMax(1e-8, min_value * 1e-6);
   if(value < min_value - tolerance)
   {
      PrintFormat("[OrderEngine] %s: volume %.8f for %s below minimum %.8f",
                  context, value, symbol, min_value);
      return false;
   }
   if(value > max_value + tolerance)
   {
      PrintFormat("[OrderEngine] %s: volume %.8f for %s above maximum %.8f",
                  context, value, symbol, max_value);
      return false;
   }
   return true;
}

bool OE_ValidatePointAlignment(const string context,
                               const string symbol,
                               const double value,
                               const double point)
{
   if(point <= 0.0)
      return true;

   const double steps = value / point;
   const double nearest_steps = MathRound(steps);
   const double aligned = nearest_steps * point;
   const double tolerance = MathMax(point * 1e-4, DBL_EPSILON);
   if(MathAbs(value - aligned) > tolerance)
   {
      PrintFormat("[OrderEngine] %s: price %.10f for %s misaligned to point %.10f (delta=%.10f)",
                  context, value, symbol, point, value - aligned);
      return false;
   }
   return true;
}

bool OE_IsVolumeWithinRange(const string symbol, const double volume)
{
   const string context = "OE_IsVolumeWithinRange";

   double step = 0.0;
   double min_vol = 0.0;
   double max_vol = 0.0;

   if(!OE_Test_GetVolumeOverride(symbol, step, min_vol, max_vol))
   {
      if(!OE_SymbolInfoDoubleSafe(context, symbol, SYMBOL_VOLUME_MIN, min_vol) ||
         !OE_SymbolInfoDoubleSafe(context, symbol, SYMBOL_VOLUME_MAX, max_vol))
      {
         return false;
      }
   }

   return OE_ValidateVolumeRange(context, symbol, volume, min_vol, max_vol);
}

//==============================================================================
// Legacy Function Wrappers (for backward compatibility)
//==============================================================================

double OE_NormalizeVolume(const string symbol, const double volume)
{
   const string context = "OE_NormalizeVolume";

   if(StringLen(symbol) == 0)
   {
      PrintFormat("[OrderEngine] %s: empty symbol provided, returning raw volume %.8f",
                  context, volume);
      return volume;
   }

   double step = 0.0;
   double min_vol = 0.0;
   double max_vol = 0.0;
   const bool has_override = OE_Test_GetVolumeOverride(symbol, step, min_vol, max_vol);

   if(!has_override)
   {
      if(!OE_SymbolInfoDoubleSafe(context, symbol, SYMBOL_VOLUME_STEP, step) ||
         !OE_SymbolInfoDoubleSafe(context, symbol, SYMBOL_VOLUME_MIN, min_vol) ||
         !OE_SymbolInfoDoubleSafe(context, symbol, SYMBOL_VOLUME_MAX, max_vol))
      {
         return volume;
      }
   }

   if(step <= 0.0)
   {
      PrintFormat("[OrderEngine] %s: invalid volume step %.10f for %s, using raw volume clamp",
                  context, step, symbol);
      step = 0.0;
   }

   if(volume <= 0.0)
   {
      PrintFormat("[OrderEngine] %s: non-positive volume %.8f for %s",
                  context, volume, symbol);
   }

   OE_ValidateVolumeRange(context, symbol, volume, min_vol, max_vol);

   double normalized = volume;
   if(step > 0.0)
      normalized = OE_RoundToStep(volume, step);

   if(normalized < min_vol)
      normalized = min_vol;
   else if(normalized > max_vol)
      normalized = max_vol;

   if(step > 0.0)
      normalized = OE_RoundToStep(normalized, step);

   if(normalized < min_vol)
      normalized = min_vol;
   else if(normalized > max_vol)
      normalized = max_vol;

   if(step > 0.0)
   {
      const double tolerance = MathMax(step * 1e-4, 1e-8);
      const double re_aligned = OE_RoundToStep(normalized, step);
      if(MathAbs(normalized - re_aligned) > tolerance)
      {
         PrintFormat("[OrderEngine] %s: correcting volume alignment for %s (norm=%.8f -> %.8f)",
                     context, symbol, normalized, re_aligned);
         normalized = re_aligned;
      }
   }

   if(MathAbs(normalized - volume) > (step > 0.0 ? step * 0.5 : 1e-8))
   {
      PrintFormat("[OrderEngine] %s: adjusted volume for %s (raw=%.8f, normalized=%.8f, step=%.8f)",
                  context, symbol, volume, normalized, step);
   }

   return NormalizeDouble(normalized, 8);
}

double OE_NormalizePrice(const string symbol, const double price)
{
   const string context = "OE_NormalizePrice";

   if(StringLen(symbol) == 0)
   {
      PrintFormat("[OrderEngine] %s: empty symbol provided, returning raw price %.10f",
                  context, price);
      return price;
   }

   double point = 0.0;
   int digits = 0;
   double override_bid = 0.0;
   double override_ask = 0.0;
   int override_stops = 0;
   const bool has_override = OE_Test_GetPriceOverride(symbol, point, digits, override_bid, override_ask, override_stops);

   if(!has_override)
   {
      if(!OE_SymbolInfoDoubleSafe(context, symbol, SYMBOL_POINT, point))
         return price;
   }

   if(point <= 0.0)
   {
      PrintFormat("[OrderEngine] %s: invalid point size %.10f for %s, returning raw price %.10f",
                  context, point, symbol, price);
      return price;
   }

   if(price <= 0.0)
   {
      PrintFormat("[OrderEngine] %s: non-positive price %.10f for %s",
                  context, price, symbol);
   }

   if(!has_override)
   {
      long digits_long = 0;
      if(!OE_SymbolInfoIntegerSafe(context, symbol, SYMBOL_DIGITS, digits_long))
         digits_long = 0;
      digits = (int)MathMax(0.0, (double)digits_long);

      long stops_level_long = 0;
      if(!OE_SymbolInfoIntegerSafe(context, symbol, SYMBOL_TRADE_STOPS_LEVEL, stops_level_long))
         stops_level_long = 0;
      if(stops_level_long < 0)
         stops_level_long = 0;
      override_stops = (int)stops_level_long;
   }
   else
   {
      if(digits < 0)
         digits = 0;
      if(override_stops < 0)
         override_stops = 0;
   }

   const double stops_distance = point * (double)override_stops;

   double normalized = OE_RoundToStep(price, point);
   normalized = NormalizeDouble(normalized, digits > 0 ? digits : 8);

   OE_ValidatePointAlignment(context, symbol, normalized, point);

   if(stops_distance > 0.0)
   {
      double used_bid = override_bid;
      double used_ask = override_ask;
      bool quotes_ok = false;

      if(has_override)
      {
         quotes_ok = (used_bid > 0.0 || used_ask > 0.0);
      }
      else
      {
         double actual_bid = 0.0;
         double actual_ask = 0.0;
         const bool have_bid = OE_SymbolInfoDoubleSafe(context, symbol, SYMBOL_BID, actual_bid);
         const bool have_ask = OE_SymbolInfoDoubleSafe(context, symbol, SYMBOL_ASK, actual_ask);
         used_bid = actual_bid;
         used_ask = actual_ask;
         quotes_ok = (have_bid && have_ask && actual_bid > 0.0 && actual_ask > 0.0);
      }

      if(quotes_ok)
      {
         double adjusted_price = normalized;
         bool adjusted = false;

         if(adjusted_price < used_bid)
         {
            const double diff = used_bid - adjusted_price;
            if(diff < stops_distance)
            {
               adjusted_price = used_bid - stops_distance;
               adjusted = true;
            }
         }
         else if(adjusted_price > used_ask)
         {
            const double diff = adjusted_price - used_ask;
            if(diff < stops_distance)
            {
               adjusted_price = used_ask + stops_distance;
               adjusted = true;
            }
         }
         else
         {
            const double diff_bid = adjusted_price - used_bid;
            const double diff_ask = used_ask - adjusted_price;
            if(diff_bid < stops_distance || diff_ask < stops_distance)
            {
               PrintFormat("[OrderEngine] %s: price %.10f for %s inside spread violates stops level %.10f (bid=%.10f ask=%.10f)",
                           context, adjusted_price, symbol, stops_distance, used_bid, used_ask);
            }
         }

         if(adjusted)
         {
            if(adjusted_price < 0.0)
               adjusted_price = 0.0;

            adjusted_price = OE_RoundToStep(adjusted_price, point);
            adjusted_price = NormalizeDouble(adjusted_price, digits > 0 ? digits : 8);

            if(MathAbs(adjusted_price - normalized) > 0.0)
            {
               PrintFormat("[OrderEngine] %s: adjusted price for %s to honor stops level (raw=%.10f, normalized=%.10f, bid=%.10f, ask=%.10f, stops=%.10f)",
                           context, symbol, price, adjusted_price, used_bid, used_ask, stops_distance);
            }

            normalized = adjusted_price;
         }
      }
      else
      {
         PrintFormat("[OrderEngine] %s: unable to enforce stops level for %s (bid=%.10f, ask=%.10f)",
                     context, symbol, used_bid, used_ask);
      }
   }

   if(!OE_ValidatePointAlignment(context, symbol, normalized, point))
   {
      const double forced = OE_RoundToStep(normalized, point);
      normalized = NormalizeDouble(forced, digits > 0 ? digits : 8);
   }

   return NormalizeDouble(normalized, digits > 0 ? digits : 8);
}

bool OrderEngine_EnterCritical(const string reason)
{
   if(g_order_engine_global_lock)
   {
      string fields = StringFormat("{\"reason\":\"%s\",\"current\":\"%s\"}", reason, g_order_engine_lock_reason);
      LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "LOCK_SKIP_BUSY", fields);
      return false;
   }
   g_order_engine_global_lock = true;
   g_order_engine_lock_reason = reason;
   return true;
}

void OrderEngine_ExitCritical(const string reason)
{
   if(reason == "")
   {
      // no-op
   }
   g_order_engine_global_lock = false;
   g_order_engine_lock_reason = "";
}

double Queue_OrderEngine_GetMinStopDistancePoints(const string symbol)
{
   long stops_level = 0;
   if(SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL, stops_level))
   {
      if(stops_level < 0)
         stops_level = 0;
      return (double)stops_level;
   }
   return 0.0;
}

bool Queue_OrderEngine_IsRiskReducing(const QueuedAction &qa,
                                      const double current_sl,
                                      const double current_tp,
                                      bool &out_is_risk_reducing)
{
   out_is_risk_reducing = false;

   if(qa.action_type == QA_CLOSE)
   {
      out_is_risk_reducing = true;
      return true;
   }

   if(qa.action_type == QA_SL_MODIFY)
   {
      if(!PositionSelectByTicket((ulong)qa.ticket))
         return false;
      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(pos_type == POSITION_TYPE_BUY)
         out_is_risk_reducing = (qa.new_sl >= current_sl - 1e-6);
      else
         out_is_risk_reducing = (qa.new_sl <= current_sl + 1e-6);
      return true;
   }

   if(qa.action_type == QA_TP_MODIFY)
   {
      out_is_risk_reducing = false;
      return true;
   }

   return true;
}

int OrderEngine_MaxDeviationPoints()
{
   int deviation = MaxSlippagePoints;
   if(deviation <= 0)
      deviation = (int)MathRound(DEFAULT_MaxSlippagePoints);
   if(deviation < 0)
      deviation = 0;
   return deviation;
}

bool Queue_OrderEngine_ApplyAction(const QueuedAction &qa,
                                   string &out_reason_code,
                                   bool &out_permanent_failure)
{
   out_permanent_failure = false;
   out_reason_code = "APPLY_OK";

#ifdef RPEA_TEST_RUNNER
   if(OE_Test_Modify(qa))
   {
      out_reason_code = "APPLY_OK";
      return true;
   }
#endif

   if(qa.ticket <= 0 || StringLen(qa.symbol) == 0)
   {
      out_permanent_failure = true;
      out_reason_code = "APPLY_FAIL_PERMANENT";
      return false;
   }

   if(qa.action_type != QA_CLOSE && !PositionSelectByTicket((ulong)qa.ticket))
   {
      out_permanent_failure = true;
      out_reason_code = "APPLY_FAIL_PERMANENT";
      return false;
   }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   const bool is_protective_action = (qa.action_type == QA_SL_MODIFY ||
                                      qa.action_type == QA_TP_MODIFY ||
                                      qa.action_type == QA_CLOSE);

   if(g_order_engine.BreakerBlocksAction(is_protective_action))
   {
      out_reason_code = "BREAKER_ACTIVE";
      return false;
   }

   if(qa.action_type == QA_SL_MODIFY || qa.action_type == QA_TP_MODIFY)
   {
      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);
      req.action = TRADE_ACTION_SLTP;
      req.symbol = qa.symbol;
      req.position = (ulong)qa.ticket;
      req.sl = (qa.new_sl > 0.0 ? qa.new_sl : current_sl);
      req.tp = (qa.new_tp > 0.0 ? qa.new_tp : current_tp);
      req.deviation = OrderEngine_MaxDeviationPoints();
      req.type_time = ORDER_TIME_GTC;
   }
   else if(qa.action_type == QA_CLOSE)
   {
      if(!PositionSelectByTicket((ulong)qa.ticket))
      {
         out_permanent_failure = true;
         out_reason_code = "APPLY_FAIL_PERMANENT";
         return false;
      }
      double volume = PositionGetDouble(POSITION_VOLUME);
      if(volume <= 0.0)
      {
         out_permanent_failure = true;
         out_reason_code = "APPLY_FAIL_PERMANENT";
         return false;
      }
      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      req.action = TRADE_ACTION_DEAL;
      req.symbol = qa.symbol;
      req.position = (ulong)qa.ticket;
      req.volume = volume;
      req.type = (pos_type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      req.deviation = OrderEngine_MaxDeviationPoints();
      req.type_time = ORDER_TIME_GTC;
      double price = 0.0;
      if(req.type == ORDER_TYPE_SELL)
         SymbolInfoDouble(req.symbol, SYMBOL_BID, price);
      else
         SymbolInfoDouble(req.symbol, SYMBOL_ASK, price);
      req.price = price;
   }
   else
   {
      out_permanent_failure = true;
      out_reason_code = "APPLY_FAIL_PERMANENT";
      return false;
   }

   const int max_attempts = 3;
   for(int attempt = 0; attempt < max_attempts; attempt++)
   {
      if(OE_OrderSend(req, res))
      {
         out_reason_code = "APPLY_OK";
         g_order_engine.ResilienceRecordSuccess();
         return true;
      }

      OrderError err((int)res.retcode);
      err.context = "QueueAction";
      err.intent_id = qa.intent_id;
      err.action_id = qa.context_hex;
      err.ticket = (ulong)qa.ticket;
      err.attempt = attempt;
      err.requested_volume = req.volume;
      err.requested_price = req.price;
      err.executed_price = res.price;
      err.is_protective_exit = is_protective_action;
      OrderErrorDecision decision = g_order_engine.ResilienceHandleError(err);
      if(decision.type == ERROR_DECISION_RETRY && attempt + 1 < max_attempts)
      {
         if(decision.retry_delay_ms > 0)
            OE_ApplyRetryDelay(decision.retry_delay_ms);
         out_reason_code = "APPLY_RETRY";
         continue;
      }
      if(decision.type == ERROR_DECISION_FAIL_FAST)
      {
         out_reason_code = (decision.gating_reason == "" ? "APPLY_FAIL" : decision.gating_reason);
         return false;
      }
      out_reason_code = "APPLY_FAIL";
      return false;
   }

   out_permanent_failure = true;
   out_reason_code = "APPLY_FAIL_PERMANENT";
   return false;
}

bool OrderEngine_RequestModifySLTP(const string symbol,
                                   const long ticket,
                                   const double new_sl,
                                   const double new_tp,
                                   const string context)
{
   if(ticket <= 0 || StringLen(symbol) == 0)
      return false;

   if(!PositionSelectByTicket((ulong)ticket))
      return false;

   double current_sl = PositionGetDouble(POSITION_SL);
   double current_tp = PositionGetDouble(POSITION_TP);

   QueueActionType action_type = QA_SL_MODIFY;
   if(new_sl <= 0.0 && new_tp > 0.0)
      action_type = QA_TP_MODIFY;

   QueuedAction qa;
   qa.id = 0;
   qa.ticket = ticket;
   qa.symbol = symbol;
   qa.action_type = action_type;
   qa.new_sl = new_sl > 0.0 ? new_sl : 0.0;
   qa.new_tp = new_tp > 0.0 ? new_tp : 0.0;
   qa.priority = QP_OTHER;
   qa.retry_count = 0;
   qa.context_hex = "";

   bool risk_reducing = false;
   Queue_OrderEngine_IsRiskReducing(qa, current_sl, current_tp, risk_reducing);

   string linked_intent_id = "";
   string linked_accept_key = "";
   OrderEngine_GetIntentMetadata((ulong)ticket, linked_intent_id, linked_accept_key);

   if(News_IsBlocked(symbol) && action_type != QA_CLOSE)
   {
      long queued_id = 0;
      bool queued = Queue_Add(symbol,
                              ticket,
                              action_type,
                              qa.new_sl,
                              qa.new_tp,
                              context,
                              queued_id,
                              linked_intent_id,
                              linked_accept_key);
      if(queued)
      {
         string fields = StringFormat("{\"queue_id\":%I64d,\"ticket\":%I64d,\"reason\":\"QUEUED_NEWS\"}",
                                      queued_id, ticket);
         LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "QUEUED_NEWS", fields);
      }
      return queued;
   }

   string apply_reason = "";
   bool permanent_failure = false;
   bool applied = Queue_OrderEngine_ApplyAction(qa, apply_reason, permanent_failure);
   if(!applied && permanent_failure)
   {
      string fields = StringFormat("{\"ticket\":%I64d,\"reason\":\"%s\"}", ticket, apply_reason);
      LogAuditRow("QUEUE", "OrderEngine", LOG_WARN, apply_reason, fields);
   }
   return applied;
}

bool OrderEngine_RequestProtectiveClose(const string symbol,
                                        const long ticket,
                                        const string context)
{
   if(ticket <= 0 || StringLen(symbol) == 0)
      return false;

   QueuedAction qa;
   qa.id = 0;
   qa.ticket = ticket;
   qa.symbol = symbol;
   qa.action_type = QA_CLOSE;
   qa.new_sl = 0.0;
   qa.new_tp = 0.0;
   qa.priority = QP_PROTECTIVE_EXIT;
   qa.retry_count = 0;
   qa.context_hex = "";

   string apply_reason = "";
   bool permanent_failure = false;
   bool applied = Queue_OrderEngine_ApplyAction(qa, apply_reason, permanent_failure);
   if(!applied && permanent_failure)
   {
      string fields = StringFormat("{\"ticket\":%I64d,\"reason\":\"%s\"}", ticket, apply_reason);
      LogAuditRow("QUEUE", "OrderEngine", LOG_WARN, apply_reason, fields);
   }
   return applied;
}

void OrderEngine_ProcessQueueAndTrailing()
{
   if(!OrderEngine_EnterCritical("queue_process"))
      return;

   Queue_CancelExpired();
   Queue_RevalidateAndApply();
   Breakeven_HandleOnTickOrTimer();
   Trail_HandleOnTickOrTimer();

   OrderEngine_ExitCritical("queue_process");
}

void OrderEngine_OnTradeTransaction(const MqlTradeTransaction &trans,
                                    const MqlTradeRequest &request,
                                    const MqlTradeResult &result)
{
   g_order_engine.OnTradeTxn(trans, request, result);

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
   {
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      long position_id = (long)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      if(entry == DEAL_ENTRY_OUT && position_id > 0)
      {
         Queue_ClearForTicket(position_id);
         Breakeven_OnPositionClosed(position_id);
         Trail_OnPositionClosed(position_id);
      }
   }

   if(trans.position > 0)
   {
      ulong pos_ticket = trans.position;
      if(PositionSelectByTicket(pos_ticket))
      {
         double pos_sl = PositionGetDouble(POSITION_SL);
         double pos_tp = PositionGetDouble(POSITION_TP);
         Queue_CoalesceIfRedundant((long)pos_ticket, pos_sl, pos_tp);
      }
   }
}

void OrderEngine_RestoreStateOnInit(const int queue_ttl_minutes,
                                    const int max_queue_size,
                                    const bool enable_prioritization)
{
   int ttl_minutes = (queue_ttl_minutes > 0 ? queue_ttl_minutes : DEFAULT_QueueTTLMinutes);
   int max_queue = (max_queue_size > 0 ? max_queue_size : DEFAULT_MaxQueueSize);
   bool prioritization = enable_prioritization;

   Queue_Init(ttl_minutes, max_queue, prioritization);
   int restored = Queue_LoadFromDiskAndReconcile();
   Breakeven_Init();
   Trail_Init();

   string fields = StringFormat("{\"restored\":%d}", restored);
   LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "LOAD_OK", fields);
}

void OrderEngine_PlacePending(const string symbol, const double price, const double sl, const double tp)
{
   PrintFormat("[OrderEngine] PlacePending stub %s price=%.5f sl=%.5f tp=%.5f", symbol, price, sl, tp);
}

void OrderEngine_PlaceMarket(const string symbol, const double sl, const double tp)
{
   PrintFormat("[OrderEngine] PlaceMarket stub %s sl=%.5f tp=%.5f", symbol, sl, tp);
}

void OrderEngine_OnTradeTxn(const MqlTradeTransaction& trans,
                            const MqlTradeRequest& request,
                            const MqlTradeResult& result)
{
   OrderEngine_OnTradeTransaction(trans, request, result);
}

// End include guard
#undef OE_CORRELATION_FALLBACK
#endif // RPEA_ORDER_ENGINE_MQH
