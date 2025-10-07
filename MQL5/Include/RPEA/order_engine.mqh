#ifndef RPEA_ORDER_ENGINE_MQH
#define RPEA_ORDER_ENGINE_MQH
// order_engine.mqh - Order Engine scaffolding (M3 Task 1)
// References: .kiro/specs/rpea-m3/tasks.md, design.md

#include <RPEA/config.mqh>
#include <RPEA/logging.mqh>

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

   // Helper methods
   void LogOE(const string message)
   {
      if(m_enable_detailed_logging)
      {
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
      
      ArrayResize(m_oco_relationships, 100);
      ArrayResize(m_queued_actions, 1000);
   }
   
   // Destructor
   ~OrderEngine()
   {
      ArrayFree(m_oco_relationships);
      ArrayFree(m_queued_actions);
   }
   
   //===========================================================================
   // Initialization and Lifecycle Methods
   //===========================================================================
   
   bool Init()
   {
      LogOE("OrderEngine::Init() - Initializing Order Engine");
      m_oco_count = 0;
      m_queue_count = 0;
      m_execution_locked = false;
      LogOE("OrderEngine::Init() - Initialization complete");
      return true;
   }
   
   void OnShutdown()
   {
      LogOE("OrderEngine::OnShutdown() - Flushing state and logs");
      
      // Log final state
      LogOE(StringFormat("OrderEngine::OnShutdown() - Active OCO relationships: %d", m_oco_count));
      LogOE(StringFormat("OrderEngine::OnShutdown() - Queued actions: %d", m_queue_count));
      
      // TODO[M3-Task2]: Persist intent journal
      // TODO[M3-Task14]: Flush audit logs
      
      LogOE("OrderEngine::OnShutdown() - Shutdown complete");
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
      
      LogOE(StringFormat("PlaceOrder: %s %s vol=%.2f price=%.5f sl=%.5f tp=%.5f",
            request.symbol, EnumToString(request.type), request.volume, 
            request.price, request.sl, request.tp));
      
      // TODO[M3-Task3]: Normalize volume and price
      // TODO[M3-Task4]: Check position limits
      // TODO[M3-Task5]: Implement retry logic
      // TODO[M3-Task6]: Market fallback with slippage protection
      
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

//==============================================================================
// Global OrderEngine Instance
//==============================================================================
extern OrderEngine g_order_engine;

//==============================================================================
// Legacy Function Wrappers (for backward compatibility)
//==============================================================================

double OE_NormalizeVolume(const string symbol, const double volume)
{
   // TODO[M3-Task3]: implement rounding to SYMBOL_VOLUME_STEP with min/max validation
   return volume;
}

double OE_NormalizePrice(const string symbol, const double price)
{
   // TODO[M3-Task3]: implement rounding to symbol point and stops-level validation
   return price;
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

#endif // RPEA_ORDER_ENGINE_MQH
