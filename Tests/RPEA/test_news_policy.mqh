//+------------------------------------------------------------------+
//|                                            test_news_policy.mqh |
//| Unit tests for News Logic (M4-Task01)                           |
//+------------------------------------------------------------------+
#include <RPEA/news.mqh>

bool Test_News_CalendarLoading()
{
   // Setup mock events
   NewsEvent events[];
   ArrayResize(events, 1);
   events[0].symbol = "USD";
   events[0].impact = "HIGH";
   events[0].timestamp_utc = 10000;
   events[0].prebuffer_min = 5;
   events[0].postbuffer_min = 5;
   events[0].is_valid = true;
   events[0].is_currency = true;

   News_Test_SetCalendarEvents(events, 1);
   
   // Verify load
   if(!News_LoadEvents()) return false;
   if(g_news_source != 1) return false; // Should be Calendar (mocked)
   
   News_Test_Clear();
   return true;
}

bool Test_News_BlockingGates()
{
   // Setup USD event at T=10000, +/- 5 min -> block [9700, 10300]
   NewsEvent events[];
   ArrayResize(events, 1);
   events[0].symbol = "USD";
   events[0].impact = "HIGH";
   events[0].timestamp_utc = 10000; // 02:46:40
   events[0].prebuffer_min = 5;
   events[0].postbuffer_min = 5;
   events[0].is_valid = true;
   events[0].is_currency = true;
   events[0].block_start_utc = 10000 - 300;
   events[0].block_end_utc = 10000 + 300;

   News_Test_SetCalendarEvents(events, 1);
   SymbolSelect("EURUSD", true);
   SymbolSelect("XAUUSD", true);
   string syms[] = {"EURUSD", "XAUUSD"};
   News_InitStabilization(syms, 2); // Init
   
   // Test CLEAR (before)
   News_Test_SetCurrentTimes(9000, 9000); // 02:30:00
   if(News_IsBlocked("EURUSD")) return false; 
   if(News_IsModifyBlocked("EURUSD")) return false;
   if(News_IsEntryBlocked("EURUSD")) return false;

   // Test BLOCKED (during window)
   News_Test_SetCurrentTimes(10000, 10000); 
   if(!News_IsBlocked("EURUSD")) return false;
   if(!News_IsModifyBlocked("EURUSD")) return false;
   if(!News_IsEntryBlocked("EURUSD")) return false;
   
   // Protective check - uses window block logic, so should report PROTECTIVE_ONLY
   string state = News_GetWindowStateDetailed("EURUSD", true);
   if(state != "PROTECTIVE_ONLY") return false;

   // Non-protective check - should report BLOCKED
   string state2 = News_GetWindowStateDetailed("EURUSD", false);
   if(state2 != "BLOCKED") return false;

   News_Test_Clear();
   return true;
}

bool Test_News_Stabilization()
{
   // Setup event leaving blocking window at T=10300. Stabilization starts then.
   NewsEvent events[];
   ArrayResize(events, 1);
   events[0].symbol = "USD";
   events[0].impact = "HIGH";
   events[0].timestamp_utc = 10000;
   events[0].prebuffer_min = 5;
   events[0].postbuffer_min = 5;
   events[0].block_start_utc = 9700;
   events[0].block_end_utc = 10300;
   events[0].is_currency = true;
   events[0].is_valid = true;

   News_Test_SetCalendarEvents(events, 1);
   SymbolSelect("EURUSD", true);
   string syms[] = {"EURUSD"};
   News_InitStabilization(syms, 1);
   
   // T=10299: Blocked
   News_Test_SetCurrentTimes(10299, 10299);
   News_UpdateBlockState("EURUSD");
   if(!News_IsBlocked("EURUSD")) return false;

   // T=10301: Window Clear -> transitions to Stabilization
   News_Test_SetCurrentTimes(10301, 10301);
   News_UpdateBlockState("EURUSD");
   
   if(News_IsBlocked("EURUSD")) return false; // Window clear
   if(News_IsModifyBlocked("EURUSD")) return false; // Mods allowed
   if(!News_IsStabilizing("EURUSD")) return false; // In stabilization
   if(!News_IsEntryBlocked("EURUSD")) return false; // Entries blocked

   // Verify state details
   string state = News_GetWindowStateDetailed("EURUSD", false);
   if(state != "STABILIZING") return false;

   // Simulate timeout (default 60 min = 3600s)
   // Advance to 10300 + 3600 + 60 = 13960
   News_Test_SetCurrentTimes(13960, 13960);
   News_UpdateBlockState("EURUSD");
   
   if(News_IsStabilizing("EURUSD")) return false; // Should be clear
   if(News_IsEntryBlocked("EURUSD")) return false;

   News_Test_Clear();
   return true;
}

bool TestNewsPolicy_RunAll()
{
   bool res = true;
   Print("Running News Policy Tests...");
   if(!Test_News_CalendarLoading()) { Print("Test_News_CalendarLoading FAILED"); res = false; }
   if(!Test_News_BlockingGates()) { Print("Test_News_BlockingGates FAILED"); res = false; }
   if(!Test_News_Stabilization()) { Print("Test_News_Stabilization FAILED"); res = false; }
   
   return res;
}
