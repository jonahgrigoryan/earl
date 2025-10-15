// Include guard
#ifndef RPEA_ORDER_ENGINE_MQH
#define RPEA_ORDER_ENGINE_MQH
// order_engine.mqh - Order Engine scaffolding (M3 Task 1)
// References: .kiro/specs/rpea-m3/tasks.md, design.md

#include <RPEA/config.mqh>
#include <RPEA/logging.mqh>

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
};

// Queued action structure
struct QueuedAction
{
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
         }
      }
      m_queue_count = new_count;
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
   void AppendLogLine(const string line);
   void FlushLogBuffer();
   void FlushIntentJournalStub();
   void ResetState();
   string FormatLogLine(const string message);

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

      FlushIntentJournalStub();
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
      
      // TODO[M3-Task12]: Implement queue with TTL and bounds checking
      // For now, just add to queue
      if(m_queue_count < ArraySize(m_queued_actions))
      {
         m_queued_actions[m_queue_count] = action;
         m_queue_count++;
         return true;
      }
      
      LogOE("QueueAction: Queue full, cannot add action");
      return false;
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
      
      // TODO[M3-Task16]: Load intent journal
      // TODO[M3-Task16]: Reconcile with broker positions/orders
      // TODO[M3-Task16]: Rebuild OCO relationships
      
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
      "{\"symbol\":\"%s\",\"type\":\"%s\",\"mode\":\"%s\",\"volume\":%.4f,\"risk\":%.2f,\"total_after\":%d,\"symbol_after\":%d,\"pending_after\":%d}",
      request.symbol,
      EnumToString(request.type),
      mode,
      request.volume,
      evaluated_risk,
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

   MqlTradeRequest trade_request;
   ZeroMemory(trade_request);
   trade_request.action = is_pending_request ? TRADE_ACTION_PENDING : TRADE_ACTION_DEAL;
   trade_request.symbol = request.symbol;
   trade_request.type = request.type;
   trade_request.volume = request.volume;
   trade_request.price = request.price;
   trade_request.sl = request.sl;
   trade_request.tp = request.tp;
   trade_request.deviation = (int)MathRound(MathMax(0.0, m_max_slippage_points));
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

   for(int attempt = 0; attempt < max_attempts; ++attempt)
   {
      if(attempt > 0)
         retries_performed = attempt;

      ZeroMemory(trade_result);
      const bool send_ok = OE_OrderSend(trade_request, trade_result);
      result.last_retcode = trade_result.retcode;

      string attempt_fields = StringFormat(
         "{\"attempt\":%d,\"symbol\":\"%s\",\"retcode\":%d,\"send_ok\":%s}",
         attempt,
         request.symbol,
         trade_result.retcode,
         send_ok ? "true" : "false");
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

         LogOE(StringFormat("ExecuteOrderWithRetry success on attempt %d: ticket=%llu price=%.5f volume=%.4f",
                            attempt,
                            result.ticket,
                            result.executed_price,
                            result.executed_volume));
         LogDecision("OrderEngine",
                     "EXECUTE_ORDER_SUCCESS",
                     StringFormat("{\"symbol\":\"%s\",\"attempt\":%d,\"retries\":%d,\"retcode\":%d,\"ticket\":%llu}",
                                  request.symbol,
                                  attempt,
                                  retries_performed,
                                  trade_result.retcode,
                                  result.ticket));
         success = true;
         break;
      }

      const RetryPolicy policy = m_retry_manager.GetPolicyForError(trade_result.retcode);
      const string policy_name = m_retry_manager.PolicyName(policy);
      const bool retry_allowed = m_retry_manager.ShouldRetry(policy, attempt);

      LogOE(StringFormat("ExecuteOrderWithRetry failure: attempt=%d retcode=%d policy=%s retry_allowed=%s",
                         attempt,
                         trade_result.retcode,
                         policy_name,
                         retry_allowed ? "true" : "false"));

      LogDecision("OrderEngine",
                  "ORDER_RETRY_EVALUATE",
                  StringFormat("{\"attempt\":%d,\"retcode\":%d,\"policy\":\"%s\",\"retry_allowed\":%s}",
                               attempt,
                               trade_result.retcode,
                               policy_name,
                               retry_allowed ? "true" : "false"));

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

   if(!success)
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

      result.error_message = fail_message;

      LogDecision("OrderEngine",
                  "EXECUTE_ORDER_FAIL",
                  StringFormat("{\"symbol\":\"%s\",\"retries\":%d,\"retcode\":%d}",
                               request.symbol,
                               retries_performed,
                               result.last_retcode));
   }

   LogOE(StringFormat("ExecuteOrderWithRetry complete: success=%s retries=%d last_retcode=%d",
                      result.success ? "true" : "false",
                      result.retry_count,
                      result.last_retcode));
   return result.success;
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

void OrderEngine::FlushIntentJournalStub()
{
   FolderCreate(RPEA_DIR);
   FolderCreate(RPEA_STATE_DIR);

   ResetLastError();
   int handle = FileOpen(FILE_INTENTS, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      const int err = GetLastError();
      PrintFormat("[OrderEngine] FlushIntentJournalStub: unable to open %s (err=%d)", FILE_INTENTS, err);
      ResetLastError();
      return;
   }

   if(FileSize(handle) == 0)
      FileWrite(handle, "{}");

   FileClose(handle);
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
   sanitized = StringReplace(sanitized, "\"", "\"\"");
   sanitized = StringReplace(sanitized, "\r", "");
   sanitized = StringReplace(sanitized, "\n", "\\n");
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

static OEOrderSendOverrideState g_oe_order_send_override = {false, 0, 0, NULL};

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

static OERetryDelayCaptureState g_oe_retry_delay_capture = {false, false, NULL};

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

      const OEOrderSendResponse &queued = g_oe_order_send_override.responses[idx];
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
