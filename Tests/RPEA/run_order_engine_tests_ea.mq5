//+------------------------------------------------------------------+
//|                                  run_order_engine_tests_ea.mq5   |
//|                        Expert wrapper for RPEA Order Engine Tests|
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

// Provide lightweight stubs for risk/equity to keep tests hermetic
#define RPEA_ORDER_ENGINE_SKIP_RISK
#define RPEA_ORDER_ENGINE_SKIP_EQUITY

// Inputs/macros normally provided by the main EA; define here for tests
#define MaxOpenPositionsTotal  2
#define MaxOpenPerSymbol       1
#define MaxPendingsPerSymbol   2
#define DailyLossCapPct        4.0
#define OverallLossCapPct      6.0
#define MinRiskDollar          10.0
#define OneAndDoneR            1.5
#define NYGatePctOfDailyCap    0.50
#define RiskPct                1.5
#define MicroRiskPct           0.10
#define GivebackCapDayPct      0.50
#define MinStopPoints          1

#include "test_order_engine.mqh"
#include "test_order_engine_normalization.mqh"
#include "test_order_engine_limits.mqh"
#include "test_order_engine_retry.mqh"

// Stubs matching prototypes declared when SKIP_* defines are set
double Equity_CalcRiskDollars(const string symbol,
                              const double volume,
                              const double price_entry,
                              const double stop_price,
                              bool &ok)
{
   ok = false;
   return 0.0;
}

bool Equity_CheckPositionCaps(const string symbol,
                              int &out_total_positions,
                              int &out_symbol_positions,
                              int &out_symbol_pending)
{
   out_total_positions = 0;
   out_symbol_positions = 0;
   out_symbol_pending = 0;
   return true;
}

bool Equity_IsPendingOrderType(const int type)
{
   switch(type)
   {
      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_SELL_LIMIT:
      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_SELL_STOP:
      case ORDER_TYPE_BUY_STOP_LIMIT:
      case ORDER_TYPE_SELL_STOP_LIMIT:
         return true;
   }
   return false;
}

// Flag to ensure tests execute once
bool g_tests_run = false;

int OnInit()
{
   Print("Starting RPEA Order Engine Tests (EA)...");
   g_tests_run = true;

   bool success = TestOrderEngine_RunAll();
   bool normalization_success = TestOrderEngineNormalization_RunAll();
   bool limits_success = TestOrderEngineLimits_RunAll();
   bool retry_success = TestOrderEngineRetry_RunAll();
   if(!success || !normalization_success || !limits_success || !retry_success)
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
