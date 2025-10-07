//+------------------------------------------------------------------+
//|                                      run_order_engine_tests.mq5 |
//|                                          RPEA Order Engine Tests |
//|                      Test runner for M3 Task 1 - Order Engine   |
//+------------------------------------------------------------------+
#property copyright "RPEA"
#property version   "1.00"
#property script_show_inputs

// Include the test file
#include <Tests/RPEA/test_order_engine.mqh>

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("Starting RPEA Order Engine Tests...");

   // Run all tests
   bool success = TestOrderEngine_RunAll();
   if(!success)
   {
      Print("Order Engine Tests reported failures.");
   }
   else
   {
      Print("Order Engine Tests passed successfully.");
   }

   Print("Order Engine Tests completed.");
}
