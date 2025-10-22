// Include guard
#ifndef RPEA_ORDER_ENGINE_MQH
#define RPEA_ORDER_ENGINE_MQH
// order_engine.mqh - Order Engine scaffolding (M3 Task 1)
// References: .kiro/specs/rpea-m3/tasks.md, design.md

#include <RPEA/config.mqh>
#include <RPEA/logging.mqh>
#include <RPEA/persistence.mqh>

#define OE_INTENT_TTL_MINUTES   1440
#define OE_ACTION_TTL_MINUTES   1440

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
bool Equity_IsPendingOrderType(const int type);
bool Equity_CheckPositionCaps(const string symbol,
                              int &out_total_positions,
                              int &out_symbol_positions,
                              int &out_symbol_pending);
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

// Queued action structure
struct QueuedAction
{
   string   action_id;
   string   accept_once_key;
   string   type;               // "TRAIL", "MODIFY_SL", "MODIFY_TP", "CANCEL"
   ulong    ticket;
   double   new_value;
   double   validation_threshold;
   datetime queued_time;
   datetime expires_time;
   string   trigger_condition;
};

// OCO relationship tracking
struct OCORelationship
{
   ulong    primary_ticket;
   ulong    sibling_ticket;
   string   symbol;
   double   primary_volume;
   double   sibling_volume;
   datetime expiry;
   bool     is_active;
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

bool OE_OrderSend(const MqlTradeRequest &request, MqlTradeResult &result);
void OE_ApplyRetryDelay(const int delay_ms);
bool OE_GetLatestQuote(const string context,
                       const string symbol,
                       double &out_point,
                       int &out_digits,
                       double &out_bid,
                       double &out_ask);

//==============================================================================
// OrderEngine Class
//==============================================================================
class OrderEngine
{
private:
   // State management
   OCORelationship m_oco_relationships[];
   int             m_oco_count;
   QueuedAction    m_queued_actions[];
   int             m_queue_count;
   bool            m_execution_locked;
   
   // Configuration (from inputs)
   int             m_max_retry_attempts;
   int             m_initial_retry_delay_ms;
   double          m_retry_backoff_multiplier;
   int             m_queued_action_ttl_min;
   double          m_max_slippage_points;
   int             m_min_hold_seconds;
   bool            m_enable_execution_lock;
   int             m_pending_expiry_grace_seconds;
   bool            m_auto_cancel_oco_sibling;
   int             m_oco_cancellation_timeout_ms;
   bool            m_enable_risk_reduction_sibling_cancel;
   bool            m_enable_detailed_logging;
   int             m_log_buffer_size;
   string          m_log_buffer[];
   int             m_log_buffer_count;
   bool            m_log_buffer_dirty;
   RetryManager    m_retry_manager;
   IntentJournal   m_intent_journal;
   bool            m_intent_journal_dirty;
   int             m_intent_sequence;
   int             m_action_sequence;

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
   
   void RemoveExpiredQueuedActions(const datetime now)
   {
      int new_count = 0;
      bool removed_any = false;
      for(int i = 0; i < m_queue_count; i++)
      {
         if(m_queued_actions[i].expires_time > now)
         {
            if(new_count != i)
            {
               m_queued_actions[new_count] = m_queued_actions[i];
            }
            new_count++;
         }
         else
         {
            LogOE(StringFormat("Removed expired queued action: %s ticket=%llu", 
                  m_queued_actions[i].type, m_queued_actions[i].ticket));
            if(m_queued_actions[i].action_id != "")
            {
               if(IntentJournal_RemoveActionById(m_intent_journal, m_queued_actions[i].action_id))
                  removed_any = true;
            }
         }
      }
      m_queue_count = new_count;
      if(removed_any)
      {
         MarkJournalDirty();
         PersistIntentJournal();
      }
   }

   bool IsMarketOrderType(const ENUM_ORDER_TYPE type);
   bool IsPendingOrderType(const ENUM_ORDER_TYPE type);
   bool EvaluatePositionCaps(const OrderRequest &request,
                             const bool is_pending_request,
                             int &out_total_positions,
                             int &out_symbol_positions,
                             int &out_symbol_pending,
                             string &out_violation_reason);
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
   void RestoreQueuedActionsFromJournal();
   void ResetState();
   string FormatLogLine(const string message);
   string GenerateIntentId(const datetime now);
   string GenerateActionId(const datetime now);
   string BuildIntentAcceptKey(const OrderRequest &request) const;
   string BuildActionAcceptKey(const QueuedAction &action) const;
   ulong  HashString64(const string text) const;
   string HashToHex(const ulong value) const;
   bool   IntentExists(const string accept_key, int &out_index) const;
   bool   ActionExists(const string accept_key, int &out_index) const;
   void   CleanupExpiredJournalEntries(const datetime now);
   PersistedQueuedAction ToPersistedAction(const QueuedAction &action) const;
   void   FromPersistedAction(const PersistedQueuedAction &persisted, QueuedAction &action) const;
   void   MarkJournalDirty();
   void   TouchJournalSequences();

public:
   // Constructor
   OrderEngine()
   {
      m_oco_count = 0;
      m_queue_count = 0;
      m_execution_locked = false;
      
      // Initialize with defaults from config.mqh
      m_max_retry_attempts = DEFAULT_MaxRetryAttempts;
      m_initial_retry_delay_ms = DEFAULT_InitialRetryDelayMs;
      m_retry_backoff_multiplier = DEFAULT_RetryBackoffMultiplier;
      m_queued_action_ttl_min = DEFAULT_QueuedActionTTLMin;
      m_max_slippage_points = DEFAULT_MaxSlippagePoints;
      m_min_hold_seconds = DEFAULT_MinHoldSeconds;
      m_enable_execution_lock = DEFAULT_EnableExecutionLock;
      m_pending_expiry_grace_seconds = DEFAULT_PendingExpiryGraceSeconds;
      m_auto_cancel_oco_sibling = DEFAULT_AutoCancelOCOSibling;
      m_oco_cancellation_timeout_ms = DEFAULT_OCOCancellationTimeoutMs;
      m_enable_risk_reduction_sibling_cancel = DEFAULT_EnableRiskReductionSiblingCancel;
      m_enable_detailed_logging = DEFAULT_EnableDetailedLogging;
      m_log_buffer_size = DEFAULT_LogBufferSize;
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
      ArrayResize(m_queued_actions, 1000);
   }
   
   // Destructor
   ~OrderEngine()
   {
      ArrayFree(m_oco_relationships);
      ArrayFree(m_queued_actions);
      ArrayFree(m_log_buffer);
      m_log_buffer_count = 0;
      m_log_buffer_dirty = false;
   }
   
   //===========================================================================
   // Initialization and Lifecycle Methods
   //===========================================================================
   
   bool Init()
   {
      LogOE("OrderEngine::Init() - Initializing Order Engine");
      ResetState();
      m_log_buffer_count = 0;
      m_log_buffer_dirty = false;
      ArrayResize(m_log_buffer, 0);
      m_retry_manager.Configure(m_max_retry_attempts,
                                m_initial_retry_delay_ms,
                                m_retry_backoff_multiplier);
      LoadIntentJournal();
      CleanupExpiredJournalEntries(TimeCurrent());
      PersistIntentJournal();
      RestoreQueuedActionsFromJournal();
      LogOE("OrderEngine::Init() - Initialization complete");
      return true;
   }
   
   void OnShutdown()
   {
      LogOE("OrderEngine::OnShutdown() - Flushing state and logs");
      
      // Log final state
      LogOE(StringFormat("OrderEngine::OnShutdown() - Active OCO relationships: %d", m_oco_count));
      LogOE(StringFormat("OrderEngine::OnShutdown() - Queued actions: %d", m_queue_count));
      LogOE("OrderEngine::OnShutdown() - Shutdown complete");

      PersistIntentJournal();
      FlushLogBuffer();
      ResetState();
      m_log_buffer_count = 0;
      m_log_buffer_dirty = false;
      ArrayResize(m_log_buffer, 0);
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
         // TODO[M3-Task7]: Process OCO fill and cancel sibling
         // TODO[M3-Task8]: Handle partial fills
      }
      else if(trans.type == TRADE_TRANSACTION_ORDER_ADD)
      {
         LogOE(StringFormat("OnTradeTxn: ORDER_ADD order=%llu", trans.order));
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
      
      // Remove expired queued actions
      RemoveExpiredQueuedActions(now);
      
      // TODO[M3-Task12]: Process queued actions (trailing stops during news windows)
      // TODO[M3-Task13]: Check trailing stop activation conditions
      // TODO[M3-Task7]: Check OCO expiry and pending order cleanup
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
      intent_record.order_type = normalized.type;
      intent_record.volume = normalized.volume;
      intent_record.price = normalized.price;
      intent_record.sl = normalized.sl;
      intent_record.tp = normalized.tp;
      intent_record.expiry = normalized.expiry;
      intent_record.status = "PENDING";
      intent_record.execution_mode = (mode == "" ? "DIRECT" : mode);
      intent_record.oco_sibling_id = "";
      intent_record.retry_count = 0;
      intent_record.reasoning = request.comment;
      StringReplace(intent_record.reasoning, "\r", " ");
      StringReplace(intent_record.reasoning, "\n", " ");
      ArrayResize(intent_record.error_messages, 0);
      ArrayResize(intent_record.executed_tickets, 0);
      ArrayResize(intent_record.partial_fills, 0);

      intent_index = ArraySize(m_intent_journal.intents);
      ArrayResize(m_intent_journal.intents, intent_index + 1);
      m_intent_journal.intents[intent_index] = intent_record;
      MarkJournalDirty();
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
         double quote = 0.0;
         if(normalized.type == ORDER_TYPE_BUY)
         {
            if(OE_SymbolInfoDoubleSafe("PlaceOrder::BUY", normalized.symbol, SYMBOL_ASK, quote))
               entry_price = quote;
         }
         else if(normalized.type == ORDER_TYPE_SELL)
         {
            if(OE_SymbolInfoDoubleSafe("PlaceOrder::SELL", normalized.symbol, SYMBOL_BID, quote))
               entry_price = quote;
         }
      }

      if(entry_price > 0.0)
      {
         const double normalized_entry = OE_NormalizePrice(normalized.symbol, entry_price);
         if(MathIsValidNumber(normalized_entry) && normalized_entry > 0.0)
            entry_price = normalized_entry;
      }

      bool risk_calc_ok = false;
      double risk_dollars = 0.0;

      if(g_oe_risk_override.active)
      {
         risk_calc_ok = g_oe_risk_override.ok;
         risk_dollars = g_oe_risk_override.risk_value;
      }
      else
      {
         risk_dollars = Equity_CalcRiskDollars(normalized.symbol,
                                               normalized.volume,
                                               entry_price,
                                               normalized.sl,
                                               risk_calc_ok);
      }

      if(!risk_calc_ok || risk_dollars <= 0.0)
      {
         string fields = StringFormat(
            "{\"symbol\":\"%s\",\"type\":\"%s\",\"mode\":\"%s\",\"entry\":%.5f,\"sl\":%.5f,\"volume\":%.4f}",
            normalized.symbol,
            EnumToString(normalized.type),
            mode,
            entry_price,
            normalized.sl,
            normalized.volume);

         LogDecision("OrderEngine", "RISK_BLOCK", fields);
         LogOE("PlaceOrder blocked: unable to evaluate risk (entry/sl invalid)");
         result.error_message = "Risk evaluation failed for order request";
         return result;
      }

      LogDecision("OrderEngine",
                  "RISK_EVAL",
                  StringFormat("{\"symbol\":\"%s\",\"type\":\"%s\",\"mode\":\"%s\",\"entry\":%.5f,\"sl\":%.5f,\"volume\":%.4f,\"risk\":%.2f}",
                               normalized.symbol,
                               EnumToString(normalized.type),
                               mode,
                               entry_price,
                               normalized.sl,
                               normalized.volume,
                               risk_dollars));

      ExecuteOrderWithRetry(normalized,
                            is_pending,
                            risk_dollars,
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
         ExecuteMarketFallback(normalized, risk_dollars, result);
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
            ArrayResize(record.partial_fills, 1);
            record.partial_fills[0] = result.executed_volume;
            string success_fields = StringFormat("{\"intent_id\":\"%s\",\"ticket\":%llu,\"executed_price\":%.5f,\"executed_volume\":%.4f}",
                                                 record.intent_id,
                                                 result.ticket,
                                                 result.executed_price,
                                                 result.executed_volume);
            LogAuditRow("ORDER_INTENT_EXECUTED", "OrderEngine", LOG_INFO, "Intent executed", success_fields);
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
         }
         m_intent_journal.intents[intent_index] = record;
         MarkJournalDirty();
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
      
      // TODO[M3-Task7]: Implement OCO tracking
      return false;
   }
   
   bool ProcessOCOFill(const ulong filled_ticket)
   {
      LogOE(StringFormat("ProcessOCOFill: ticket=%llu", filled_ticket));
      // TODO[M3-Task7]: Cancel sibling order
      // TODO[M3-Task8]: Handle partial fills
      return false;
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
   // Queue Management Methods (Stubs for M3 Task 12)
   //===========================================================================
   
   bool QueueAction(const QueuedAction& action)
   {
      LogOE(StringFormat("QueueAction: type=%s ticket=%llu expires=%s",
            action.type, action.ticket, TimeToString(action.expires_time)));

      QueuedAction queued = action;
      datetime now = TimeCurrent();
      if(queued.queued_time <= 0)
         queued.queued_time = now;
      if(queued.expires_time <= 0)
         queued.expires_time = queued.queued_time + m_queued_action_ttl_min * 60;
      if(queued.action_id == "")
         queued.action_id = GenerateActionId(now);
      queued.accept_once_key = BuildActionAcceptKey(queued);

      int duplicate_index = -1;
      if(ActionExists(queued.accept_once_key, duplicate_index))
      {
         LogOE(StringFormat("QueueAction duplicate ignored: type=%s ticket=%llu accept_key=%s",
                            queued.type, queued.ticket, queued.accept_once_key));
         string dup_fields = StringFormat("{\"action_id\":\"%s\",\"type\":\"%s\",\"ticket\":%llu,\"accept_once_key\":\"%s\"}",
                                          queued.action_id,
                                          queued.type,
                                          queued.ticket,
                                          queued.accept_once_key);
         LogDecision("OrderEngine", "QUEUE_ACTION_DUP", dup_fields);
         LogAuditRow("QUEUED_ACTION_DUP", "OrderEngine", LOG_WARN, "Duplicate queued action", dup_fields);
         return false;
      }

      if(m_queue_count >= ArraySize(m_queued_actions))
      {
         LogOE("QueueAction: Queue full, cannot add action");
         return false;
      }

      m_queued_actions[m_queue_count] = queued;
      m_queue_count++;

      PersistedQueuedAction persisted = ToPersistedAction(queued);
      int persisted_index = IntentJournal_FindActionById(m_intent_journal, persisted.action_id);
      if(persisted_index < 0)
      {
         persisted_index = ArraySize(m_intent_journal.queued_actions);
         ArrayResize(m_intent_journal.queued_actions, persisted_index + 1);
      }
      m_intent_journal.queued_actions[persisted_index] = persisted;
      MarkJournalDirty();
      PersistIntentJournal();

      string queue_fields = StringFormat("{\"action_id\":\"%s\",\"type\":\"%s\",\"ticket\":%llu,\"accept_once_key\":\"%s\",\"expires\":\"%s\"}",
                                         queued.action_id,
                                         queued.type,
                                         queued.ticket,
                                         queued.accept_once_key,
                                         TimeToString(queued.expires_time));
      LogDecision("OrderEngine", "QUEUE_ACTION_ACCEPT", queue_fields);
      LogAuditRow("QUEUED_ACTION", "OrderEngine", LOG_INFO, "Action queued", queue_fields);
      return true;
   }
   
   void ProcessQueuedActions(const datetime now)
   {
      LogOE(StringFormat("ProcessQueuedActions: Processing %d queued actions", m_queue_count));
      // TODO[M3-Task12]: Implement precondition validation and execution
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
      CleanupExpiredJournalEntries(TimeCurrent());
      PersistIntentJournal();
      LogOE("ReconcileOnStartup: Reconciliation complete");
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
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_REQUOTE:
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
    if(is_market_request && requested_price <= 0.0 && have_snapshot)
    {
       const bool buy_init = IsBuyDirection(request.type);
       const double snapshot_price = buy_init
                                     ? (snapshot_ask > 0.0 ? snapshot_ask : snapshot_bid)
                                     : (snapshot_bid > 0.0 ? snapshot_bid : snapshot_ask);
       if(snapshot_price > 0.0)
          requested_price = snapshot_price;
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
   trade_request.price = request.price;
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
      const bool send_ok = OE_OrderSend(trade_request, trade_result);
      result.last_retcode = trade_result.retcode;

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
         result.last_retcode = trade_result.retcode;
         result.error_message = "";

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

      const RetryPolicy policy = m_retry_manager.GetPolicyForError(trade_result.retcode);
      const string policy_name = m_retry_manager.PolicyName(policy);
      const bool retry_allowed = m_retry_manager.ShouldRetry(policy, attempt);

      LogOE(StringFormat("ExecuteOrderWithRetry failure: attempt=%d retcode=%d policy=%s retry_allowed=%s slippage=%.2f pts",
                         attempt,
                         trade_result.retcode,
                         policy_name,
                         retry_allowed ? "true" : "false",
                         attempt_slippage));

      LogDecision("OrderEngine",
                  "ORDER_RETRY_EVALUATE",
                  StringFormat("{\"attempt\":%d,\"retcode\":%d,\"policy\":\"%s\",\"retry_allowed\":%s,\"slippage_pts\":%.2f}",
                               attempt,
                               trade_result.retcode,
                               policy_name,
                               retry_allowed ? "true" : "false",
                               attempt_slippage));

      if(!retry_allowed)
         break;

      const int delay_ms = m_retry_manager.CalculateDelayMs(attempt + 1, policy);
      if(delay_ms > 0)
      {
         LogOE(StringFormat("ExecuteOrderWithRetry delay before retry %d: %d ms (policy=%s)",
                            attempt + 1,
                            delay_ms,
                            policy_name));
         OE_ApplyRetryDelay(delay_ms);
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

   LogOE("Converting pending to market due to high slippage");
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
   if(!IntentJournal_Save(m_intent_journal))
   {
      PrintFormat("[OrderEngine] PersistIntentJournal: failed to save %s", FILE_INTENTS);
      return;
   }
   m_intent_journal_dirty = false;
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

void OrderEngine::RestoreQueuedActionsFromJournal()
{
   m_queue_count = 0;
   datetime now = TimeCurrent();
   const int capacity = ArraySize(m_queued_actions);

   for(int i = 0; i < ArraySize(m_intent_journal.queued_actions); ++i)
   {
      PersistedQueuedAction persisted = m_intent_journal.queued_actions[i];
      if(persisted.expires_time > 0 && persisted.expires_time < now)
         continue;
      if(m_queue_count >= capacity)
      {
         Print("[OrderEngine] RestoreQueuedActionsFromJournal: queue capacity reached during restore");
         break;
      }
      QueuedAction runtime;
      FromPersistedAction(persisted, runtime);
      m_queued_actions[m_queue_count++] = runtime;
   }
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
   m_intent_sequence++;
   MqlDateTime dt;
   TimeToStruct(now, dt);
   return StringFormat("rpea_%04d%02d%02d_%02d%02d%02d_%03d",
                       dt.year, dt.mon, dt.day,
                       dt.hour, dt.min, dt.sec,
                       m_intent_sequence);
}

string OrderEngine::GenerateActionId(const datetime now)
{
   if(m_action_sequence >= 999)
      m_action_sequence = 0;
   m_action_sequence++;
   MqlDateTime dt;
   TimeToStruct(now, dt);
   return StringFormat("rpea_action_%04d%02d%02d_%02d%02d%02d_%03d",
                       dt.year, dt.mon, dt.day,
                       dt.hour, dt.min, dt.sec,
                       m_action_sequence);
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

string OrderEngine::BuildActionAcceptKey(const QueuedAction &action) const
{
   string base = StringFormat("%llu|%s|%.8f|%.4f|%lld|%s",
                              action.ticket,
                              action.type,
                              action.new_value,
                              action.validation_threshold,
                              (long)action.queued_time,
                              action.trigger_condition);
   ulong hash = HashString64(base);
   string accept_key = "action_" + HashToHex(hash);
   return accept_key;
}

bool OrderEngine::IntentExists(const string accept_key, int &out_index) const
{
   out_index = IntentJournal_FindIntentByAcceptKey(m_intent_journal, accept_key);
   return (out_index >= 0);
}

bool OrderEngine::ActionExists(const string accept_key, int &out_index) const
{
   out_index = IntentJournal_FindActionByAcceptKey(m_intent_journal, accept_key);
   return (out_index >= 0);
}

PersistedQueuedAction OrderEngine::ToPersistedAction(const QueuedAction &action) const
{
   PersistedQueuedAction persisted;
   persisted.action_id = action.action_id;
   persisted.accept_once_key = action.accept_once_key;
   persisted.ticket = action.ticket;
   persisted.action_type = action.type;
   persisted.new_value = action.new_value;
   persisted.validation_threshold = action.validation_threshold;
   persisted.queued_time = action.queued_time;
   persisted.expires_time = action.expires_time;
   persisted.trigger_condition = action.trigger_condition;
   return persisted;
}

void OrderEngine::FromPersistedAction(const PersistedQueuedAction &persisted, QueuedAction &action) const
{
   action.action_id = persisted.action_id;
   action.accept_once_key = persisted.accept_once_key;
   action.type = persisted.action_type;
   action.ticket = persisted.ticket;
   action.new_value = persisted.new_value;
   action.validation_threshold = persisted.validation_threshold;
   action.queued_time = persisted.queued_time;
   action.expires_time = persisted.expires_time;
   action.trigger_condition = persisted.trigger_condition;
}

void OrderEngine::ResetState()
{
   m_oco_count = 0;
   m_queue_count = 0;
   m_execution_locked = false;
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

void OE_QueueTrailIfBlocked(const ulong position_ticket,
                            const double new_sl,
                            const datetime now)
{
   // TODO[M3-Task13]: enqueue SL move during news window; enforce TTL and preconditions
}

void OE_TrailingMaybeActivate(const ulong position_ticket,
                              const double entry_price,
                              const double sl_price,
                              const double r_multiple,
                              const double atr_points)
{
   // TODO[M3-Task13]: activate trailing at >= +1R and move SL by ATR*TrailMult
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
   g_order_engine.OnTradeTxn(trans, request, result);
}

// End include guard
#endif // RPEA_ORDER_ENGINE_MQH
