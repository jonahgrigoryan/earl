#ifndef RPEA_MR_CONTEXT_MQH
#define RPEA_MR_CONTEXT_MQH
// mr_context.mqh - Lightweight MR context for allocator (M7 Task 7)
// Separate header to avoid circular includes (signals_mr -> m7_helpers -> order_engine)

struct MR_Context
{
   double expected_R;         // Expected R-multiple (e.g., 1.5)
   double expected_hold;      // Expected hold time in minutes (from EMRT_GetP50)
   double worst_case_risk;    // 0.0 here; computed in allocator where equity/SL known
   double entry_price;        // Current bid/ask from EXECUTION symbol (not signal)
   int    direction;          // 1 for long, -1 for short
};

MR_Context g_last_mr_context;

#endif // RPEA_MR_CONTEXT_MQH
