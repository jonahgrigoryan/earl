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

#endif // RPEA_ORDER_ENGINE_MQH
