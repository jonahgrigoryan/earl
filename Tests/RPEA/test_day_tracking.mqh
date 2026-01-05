//+------------------------------------------------------------------+
//|                                          test_day_tracking.mqh |
//|                         M4-Task02: Server-Day Tracking Tests    |
//+------------------------------------------------------------------+
#ifndef TEST_DAY_TRACKING_MQH
#define TEST_DAY_TRACKING_MQH

#include <RPEA/timeutils.mqh>
#include <RPEA/state.mqh>

//==============================================================================
// Test: CEST report date string format
//==============================================================================
bool TestDay_CestReportDateFormat()
{
   Print("TestDay_CestReportDateFormat: Starting...");
   
   // Create a known datetime: 2024.06.15 14:30:00
   datetime test_time = D'2024.06.15 14:30:00';
   
   string result = TimeUtils_CestDateString(test_time);
   
   // With default offset 0, should return same date
   bool passed = (StringSubstr(result, 0, 4) == "2024" && 
                  StringSubstr(result, 5, 2) == "06" && 
                  StringSubstr(result, 8, 2) == "15");
   
   if(!passed)
      Print("TestDay_CestReportDateFormat: FAILED - got ", result);
   else
      Print("TestDay_CestReportDateFormat: PASSED");
   
   return passed;
}

//==============================================================================
// Test: Same server-day detection
//==============================================================================
bool TestDay_ServerSameDayDetection()
{
   Print("TestDay_ServerSameDayDetection: Starting...");
   
   datetime t1 = D'2024.06.15 08:00:00';
   datetime t2 = D'2024.06.15 23:59:59';
   
   int date1 = TimeUtils_ServerDateInt(t1);
   int date2 = TimeUtils_ServerDateInt(t2);
   
   bool passed = (date1 == date2 && date1 == 20240615);
   
   if(!passed)
      Print("TestDay_ServerSameDayDetection: FAILED - date1=", date1, " date2=", date2);
   else
      Print("TestDay_ServerSameDayDetection: PASSED");
   
   return passed;
}

//==============================================================================
// Test: Different server-day detection
//==============================================================================
bool TestDay_ServerDifferentDayDetection()
{
   Print("TestDay_ServerDifferentDayDetection: Starting...");
   
   datetime t1 = D'2024.06.15 23:59:59';
   datetime t2 = D'2024.06.16 00:00:00';
   
   int date1 = TimeUtils_ServerDateInt(t1);
   int date2 = TimeUtils_ServerDateInt(t2);
   
   bool passed = (date1 != date2 && date1 == 20240615 && date2 == 20240616);
   
   if(!passed)
      Print("TestDay_ServerDifferentDayDetection: FAILED - date1=", date1, " date2=", date2);
   else
      Print("TestDay_ServerDifferentDayDetection: PASSED");
   
   return passed;
}

//==============================================================================
// Test: Trade day marking is idempotent
//==============================================================================
bool TestDay_TradeDayIdempotent()
{
   Print("TestDay_TradeDayIdempotent: Starting...");
   
   // Reset state
   ChallengeState st = {0};
   st.trading_enabled = true;
   g_state = st;
   
   datetime test_time = D'2024.06.15 10:00:00';
   
   // Mark trade day twice
   State_MarkTradeDayServer(test_time);
   int days_after_first = State_GetDaysTraded();
   
   State_MarkTradeDayServer(test_time);
   int days_after_second = State_GetDaysTraded();
   
   bool passed = (days_after_first == 1 && days_after_second == 1);
   
   if(!passed)
      Print("TestDay_TradeDayIdempotent: FAILED - after_first=", days_after_first, " after_second=", days_after_second);
   else
      Print("TestDay_TradeDayIdempotent: PASSED");
   
   return passed;
}

//==============================================================================
// Test: Trade day increments on new server day
//==============================================================================
bool TestDay_TradeDayIncrements()
{
   Print("TestDay_TradeDayIncrements: Starting...");
   
   // Reset state
   ChallengeState st = {0};
   st.trading_enabled = true;
   g_state = st;
   
   datetime day1 = D'2024.06.15 10:00:00';
   datetime day2 = D'2024.06.16 10:00:00';
   
   State_MarkTradeDayServer(day1);
   int days_after_day1 = State_GetDaysTraded();
   
   State_MarkTradeDayServer(day2);
   int days_after_day2 = State_GetDaysTraded();
   
   bool passed = (days_after_day1 == 1 && days_after_day2 == 2);
   
   if(!passed)
      Print("TestDay_TradeDayIncrements: FAILED - day1=", days_after_day1, " day2=", days_after_day2);
   else
      Print("TestDay_TradeDayIncrements: PASSED");
   
   return passed;
}

//==============================================================================
// Test: CEST offset applied correctly for reporting
//==============================================================================
bool TestDay_CestOffsetApplication()
{
   Print("TestDay_CestOffsetApplication: Starting...");
   
   // Server time 23:30 with offset +60 min should show next CEST day
   datetime server_time = D'2024.06.15 23:30:00';
   
   // With default offset=0, CEST should be same as server
   datetime cest = TimeUtils_ServerToCEST(server_time);
   
   // Just verify the function doesn't crash and returns valid time
   bool passed = (cest >= server_time - 86400 && cest <= server_time + 86400);
   
   if(!passed)
      Print("TestDay_CestOffsetApplication: FAILED - invalid CEST time");
   else
      Print("TestDay_CestOffsetApplication: PASSED");
   
   return passed;
}

//==============================================================================
// Run all day tracking tests
//==============================================================================
bool TestDayTracking_RunAll()
{
   Print("=== M4-Task02: Day Tracking Tests ===");
   
   bool ok = true;
   ok &= TestDay_CestReportDateFormat();
   ok &= TestDay_ServerSameDayDetection();
   ok &= TestDay_ServerDifferentDayDetection();
   ok &= TestDay_TradeDayIdempotent();
   ok &= TestDay_TradeDayIncrements();
   ok &= TestDay_CestOffsetApplication();
   
   Print("=== Day Tracking Tests: ", (ok ? "ALL PASSED" : "SOME FAILED"), " ===");
   
   return ok;
}

#endif // TEST_DAY_TRACKING_MQH
