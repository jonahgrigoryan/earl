//+------------------------------------------------------------------+
//|                                  run_order_engine_tests_ea.mq5   |
//|                        Expert wrapper for RPEA Order Engine Tests|
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include <Tests/RPEA/test_order_engine.mqh>
#include <Tests/RPEA/test_order_engine_normalization.mqh>

// Flag to ensure tests execute once
bool g_tests_run = false;

int OnInit()
{
   Print("Starting RPEA Order Engine Tests (EA)...");
   g_tests_run = true;

   bool success = TestOrderEngine_RunAll();
   bool normalization_success = TestOrderEngineNormalization_RunAll();
   if(!success || !normalization_success)
   {
      Print("Order Engine Tests reported failures.");
      // Returning INIT_FAILED will stop the expert immediately
      return(INIT_FAILED);
   }

   Print("Order Engine Tests passed successfully.");
   // Remove expert to avoid processing ticks
   ExpertRemove();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(g_tests_run)
      PrintFormat("Order Engine Tests completed. Deinit reason=%d", reason);
}

void OnTick()
{
   // The expert is removed in OnInit, so OnTick should never be reached.
   ExpertRemove();
}
