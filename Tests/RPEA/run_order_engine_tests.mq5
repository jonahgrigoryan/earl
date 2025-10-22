//+------------------------------------------------------------------+
//|                                      run_order_engine_tests.mq5 |
//|                                          RPEA Order Engine Tests |
//|                      Test runner for M3 Task 1 - Order Engine   |
//+------------------------------------------------------------------+
#property copyright "RPEA"
#property version   "1.00"
#property script_show_inputs

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
#define RPEA_ORDER_ENGINE_SKIP_RISK
#define RPEA_ORDER_ENGINE_SKIP_EQUITY

// Include the test file
#include "test_order_engine.mqh"
#include "test_order_engine_normalization.mqh"
#include "test_order_engine_limits.mqh"
#include "test_order_engine_retry.mqh"
#include "test_order_engine_market.mqh"
#include "test_order_engine_intent.mqh"

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

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("Starting RPEA Order Engine Tests...");

   // Run all tests
   bool success = TestOrderEngine_RunAll();
   bool normalization_success = TestOrderEngineNormalization_RunAll();
   bool limits_success = TestOrderEngineLimits_RunAll();
   bool retry_success = TestOrderEngineRetry_RunAll();
   bool market_success = TestOrderEngineMarket_RunAll();
   bool intent_success = TestOrderEngineIntent_RunAll();
   if(!success || !normalization_success || !limits_success || !retry_success || !market_success || !intent_success)
   {
      Print("Order Engine Tests reported failures.");
   }
   else
   {
      Print("Order Engine Tests passed successfully.");
   }

   Print("Order Engine Tests completed.");
}
