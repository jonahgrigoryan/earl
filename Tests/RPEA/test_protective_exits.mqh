//+------------------------------------------------------------------+
//|                                      test_protective_exits.mqh   |
//|                      M4-Task03: Protective Exit Behavior Tests   |
//+------------------------------------------------------------------+
#ifndef TEST_PROTECTIVE_EXITS_MQH
#define TEST_PROTECTIVE_EXITS_MQH

#include <RPEA/order_engine.mqh>
#include <RPEA/news.mqh>
#include <RPEA/equity_guardian.mqh>
#include <RPEA/state.mqh>
#include <RPEA/config.mqh>

// Test counters (use global from test_reporter)
#ifndef TEST_COUNTERS_DECLARED
#define TEST_COUNTERS_DECLARED
extern int g_test_passed;
extern int g_test_failed;
extern string g_current_test;
#endif

// Test assertion macro
#ifndef ASSERT_TRUE
#define ASSERT_TRUE(cond, msg) \
   if(!(cond)) { \
      PrintFormat("[FAIL] %s: %s", g_current_test, msg); \
      g_test_failed++; \
   } else { \
      g_test_passed++; \
   }
#endif

//+------------------------------------------------------------------+
// Helper: Create test fixture file
//+------------------------------------------------------------------+
bool ProtectiveExits_WriteFixture(const string filename, const string &lines[], const int line_count, string &out_path)
{
   FolderCreate(RPEA_DIR);
   const string fixture_dir = RPEA_DIR + "/test_fixtures";
   FolderCreate(fixture_dir);
   string path = fixture_dir + "/" + filename;
   int handle = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;
   for(int i = 0; i < line_count; i++)
      FileWrite(handle, lines[i]);
   FileClose(handle);
   out_path = path;
   return true;
}

//+------------------------------------------------------------------+
// Test: Protective exits are allowed during news windows
//+------------------------------------------------------------------+
bool Test_ProtectiveExits_BypassNews()
{
   g_current_test = "Test_ProtectiveExits_BypassNews";
   Print("Running: ", g_current_test);
   
   // Create test news fixture with event in progress
   string fixture_path = "";
   string lines[2];
   lines[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min";
   lines[1] = "2025-01-15T13:30:00Z,XAUUSD,HIGH,BLS,Test Event,5,10";
   
   bool fixture_created = ProtectiveExits_WriteFixture("news_protective.csv", lines, 2, fixture_path);
   ASSERT_TRUE(fixture_created, "Test fixture should be created");
   
   if(!fixture_created)
      return false;
   
   // Set news override to our fixture
   News_Test_SetOverridePath(fixture_path);
   News_Test_SetOverrideMaxAgeHours(24);
   
   // Set time to during the news event (13:29 is within T-5min buffer)
   News_Test_SetCurrentTimes(StringToTime("2025.01.15 13:29"), StringToTime("2025.01.15 13:29"));

   // Check that protective exits are allowed during news
   string news_state = News_GetWindowState("XAUUSD", true);  // is_protective = true
   bool protective_allowed = (news_state == "PROTECTIVE_ONLY" || news_state == "CLEAR");
   
   News_Test_ClearCurrentTimeOverride();
   
   ASSERT_TRUE(protective_allowed, 
               StringFormat("Protective exits should be allowed during news (got state: %s)", news_state));
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Margin protection threshold is reasonable
//+------------------------------------------------------------------+
bool Test_ProtectiveExits_MarginProtectionThreshold()
{
   g_current_test = "Test_ProtectiveExits_MarginProtectionThreshold";
   Print("Running: ", g_current_test);
   
   // Verify margin level threshold is within reasonable range
   bool threshold_valid = (MarginLevelCritical >= 20.0 && MarginLevelCritical <= 100.0);
   
   ASSERT_TRUE(threshold_valid,
               StringFormat("Margin level threshold should be between 20%% and 100%% (got %.2f)", MarginLevelCritical));
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: OE_ERR_DAILY_DISABLED is properly defined
//+------------------------------------------------------------------+
bool Test_ProtectiveExits_DailyDisabledErrorCode()
{
   g_current_test = "Test_ProtectiveExits_DailyDisabledErrorCode";
   Print("Running: ", g_current_test);
   
   // Verify error code is defined and has expected value
   bool error_defined = (OE_ERR_DAILY_DISABLED == 10004);
   
   ASSERT_TRUE(error_defined, 
               StringFormat("OE_ERR_DAILY_DISABLED should be 10004 (got %d)", OE_ERR_DAILY_DISABLED));
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Entry gates block when daily disabled
//+------------------------------------------------------------------+
bool Test_ProtectiveExits_EntryGatesBlock()
{
   g_current_test = "Test_ProtectiveExits_EntryGatesBlock";
   Print("Running: ", g_current_test);
   
   // Save original state
   ChallengeState orig_st = State_Get();
   
   // Setup: daily floor breached, not permanent
   ChallengeState st = State_Get();
   st.daily_floor_breached = true;
   st.disabled_permanent = false;
   st.trading_enabled = false;
   State_Set(st);
   
   // Check entry gates
   M4GateResult result = OE_CheckM4EntryGates(true);  // is_entry = true
   
   bool blocked = !result.allowed;
   bool correct_error = (result.error_code == OE_ERR_DAILY_DISABLED);
   
   // Restore state
   State_Set(orig_st);
   
   ASSERT_TRUE(blocked, "Entry gates should block when daily kill-switch active");
   ASSERT_TRUE(correct_error, 
               StringFormat("Error code should be OE_ERR_DAILY_DISABLED (got %d)", result.error_code));
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Non-entry operations allowed when daily disabled
//+------------------------------------------------------------------+
bool Test_ProtectiveExits_NonEntryAllowed()
{
   g_current_test = "Test_ProtectiveExits_NonEntryAllowed";
   Print("Running: ", g_current_test);
   
   // Save original state
   ChallengeState orig_st = State_Get();
   
   // Setup: daily floor breached, not permanent
   ChallengeState st = State_Get();
   st.daily_floor_breached = true;
   st.disabled_permanent = false;
   st.trading_enabled = false;
   State_Set(st);
   
   // Check non-entry gates (e.g., for protective exits)
   M4GateResult result = OE_CheckM4EntryGates(false);  // is_entry = false
   
   bool allowed = result.allowed;
   
   // Restore state
   State_Set(orig_st);
   
   ASSERT_TRUE(allowed, "Non-entry operations should be allowed when daily disabled (for protective exits)");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Magic number check
//+------------------------------------------------------------------+
bool Test_ProtectiveExits_MagicNumberCheck()
{
   g_current_test = "Test_ProtectiveExits_MagicNumberCheck";
   Print("Running: ", g_current_test);
   
   // Test our magic range (MagicBase to MagicBase + 999)
   bool magic_base_valid = OrderEngine_IsOurMagic(MagicBase);
   bool magic_offset_valid = OrderEngine_IsOurMagic(MagicBase + 500);
   bool magic_upper_valid = OrderEngine_IsOurMagic(MagicBase + 999);
   bool magic_out_of_range = !OrderEngine_IsOurMagic(MagicBase + 1000);
   bool magic_below_range = !OrderEngine_IsOurMagic(MagicBase - 1);
   
   ASSERT_TRUE(magic_base_valid, "MagicBase should be recognized as our magic");
   ASSERT_TRUE(magic_offset_valid, "MagicBase+500 should be recognized as our magic");
   ASSERT_TRUE(magic_upper_valid, "MagicBase+999 should be recognized as our magic");
   ASSERT_TRUE(magic_out_of_range, "MagicBase+1000 should NOT be recognized as our magic");
   ASSERT_TRUE(magic_below_range, "MagicBase-1 should NOT be recognized as our magic");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Run all protective exits tests
//+------------------------------------------------------------------+
bool TestProtectiveExits_RunAll()
{
   Print("==============================================================");
   Print("M4 Task03 Protective Exit Tests");
   Print("==============================================================");

   int local_passed = 0;
   int local_failed = 0;

   bool ok = true;
   
   // Reset counters for this suite
   int start_passed = g_test_passed;
   int start_failed = g_test_failed;
   
   ok &= Test_ProtectiveExits_BypassNews();
   ok &= Test_ProtectiveExits_MarginProtectionThreshold();
   ok &= Test_ProtectiveExits_DailyDisabledErrorCode();
   ok &= Test_ProtectiveExits_EntryGatesBlock();
   ok &= Test_ProtectiveExits_NonEntryAllowed();
   ok &= Test_ProtectiveExits_MagicNumberCheck();

   local_passed = g_test_passed - start_passed;
   local_failed = g_test_failed - start_failed;
   
   PrintFormat("Protective Exits Test Summary: %d passed, %d failed", local_passed, local_failed);
   return (local_failed == 0);
}

#endif // TEST_PROTECTIVE_EXITS_MQH
