//+------------------------------------------------------------------+
//|                                       test_persistence_state.mqh |
//|                    M4-Task04: Challenge State Persistence Tests  |
//+------------------------------------------------------------------+
#ifndef TEST_PERSISTENCE_STATE_MQH
#define TEST_PERSISTENCE_STATE_MQH

#include <RPEA/persistence.mqh>
#include <RPEA/state.mqh>

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
// Test: Validation clamps negative gDaysTraded
//+------------------------------------------------------------------+
bool Test_PersistenceState_ClampNegativeDaysTraded()
{
   g_current_test = "Test_PersistenceState_ClampNegativeDaysTraded";
   Print("Running: ", g_current_test);
   
   ChallengeState s;
   ZeroMemory(s);
   s.initial_baseline = 10000.0;
   s.baseline_today = 10000.0;
   s.gDaysTraded = -5;  // Invalid negative
   
   string reason;
   Persistence_ValidateChallengeState(s, reason);
   
   ASSERT_TRUE(s.gDaysTraded == 0, "Negative gDaysTraded should be clamped to 0");
   ASSERT_TRUE(reason == "negative_days_traded", 
               StringFormat("Reason should be 'negative_days_traded' (got '%s')", reason));
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Validation clamps invalid initial_baseline
//+------------------------------------------------------------------+
bool Test_PersistenceState_ClampInvalidBaseline()
{
   g_current_test = "Test_PersistenceState_ClampInvalidBaseline";
   Print("Running: ", g_current_test);
   
   ChallengeState s;
   ZeroMemory(s);
   s.initial_baseline = -100.0;  // Invalid negative
   s.baseline_today = 10000.0;
   s.gDaysTraded = 0;
   
   string reason;
   Persistence_ValidateChallengeState(s, reason);
   
   ASSERT_TRUE(s.initial_baseline > 0, "Negative initial_baseline should be clamped to current equity");
   ASSERT_TRUE(reason == "invalid_initial_baseline",
               StringFormat("Reason should be 'invalid_initial_baseline' (got '%s')", reason));
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Validation enforces disabled_permanent -> trading_enabled=false
//+------------------------------------------------------------------+
bool Test_PersistenceState_DisabledPermanentEnforced()
{
   g_current_test = "Test_PersistenceState_DisabledPermanentEnforced";
   Print("Running: ", g_current_test);
   
   ChallengeState s;
   ZeroMemory(s);
   s.initial_baseline = 10000.0;
   s.baseline_today = 10000.0;
   s.disabled_permanent = true;
   s.trading_enabled = true;  // Should be overridden
   
   string reason;
   Persistence_ValidateChallengeState(s, reason);
   
   ASSERT_TRUE(!s.trading_enabled, 
               "trading_enabled should be false when disabled_permanent is true");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: State version is set if missing
//+------------------------------------------------------------------+
bool Test_PersistenceState_VersionSet()
{
   g_current_test = "Test_PersistenceState_VersionSet";
   Print("Running: ", g_current_test);
   
   ChallengeState s;
   ZeroMemory(s);
   s.initial_baseline = 10000.0;
   s.baseline_today = 10000.0;
   s.state_version = 0;  // Missing/unset
   
   string reason;
   Persistence_ValidateChallengeState(s, reason);
   
   ASSERT_TRUE(s.state_version == STATE_VERSION_CURRENT,
               StringFormat("state_version should be set to %d (got %d)", 
                           STATE_VERSION_CURRENT, s.state_version));
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Validation clamps future deal time
//+------------------------------------------------------------------+
bool Test_PersistenceState_ClampFutureDealTime()
{
   g_current_test = "Test_PersistenceState_ClampFutureDealTime";
   Print("Running: ", g_current_test);
   
   ChallengeState s;
   ZeroMemory(s);
   s.initial_baseline = 10000.0;
   s.baseline_today = 10000.0;
   s.last_counted_deal_time = TimeCurrent() + 86400;  // Tomorrow (invalid)
   
   string reason;
   Persistence_ValidateChallengeState(s, reason);
   
   ASSERT_TRUE(s.last_counted_deal_time == (datetime)0,
               "Future last_counted_deal_time should be reset to 0");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Dirty flag tracking
//+------------------------------------------------------------------+
bool Test_PersistenceState_DirtyFlagTracking()
{
   g_current_test = "Test_PersistenceState_DirtyFlagTracking";
   Print("Running: ", g_current_test);
   
   // Start clean
   Persistence_ClearDirty();
   bool initially_clean = !Persistence_IsDirty();
   
   // Mark dirty
   Persistence_MarkDirty();
   bool marked_dirty = Persistence_IsDirty();
   
   // Clear again
   Persistence_ClearDirty();
   bool cleared = !Persistence_IsDirty();
   
   ASSERT_TRUE(initially_clean, "State should initially not be dirty");
   ASSERT_TRUE(marked_dirty, "State should be dirty after MarkDirty()");
   ASSERT_TRUE(cleared, "State should not be dirty after ClearDirty()");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: State payload includes all M4-Task04 fields
//+------------------------------------------------------------------+
bool Test_PersistenceState_PayloadContainsNewFields()
{
   g_current_test = "Test_PersistenceState_PayloadContainsNewFields";
   Print("Running: ", g_current_test);
   
   ChallengeState s;
   ZeroMemory(s);
   s.initial_baseline = 10000.0;
   s.baseline_today = 9500.0;
   s.gDaysTraded = 5;
   s.last_counted_server_date = 20250115;
   s.last_counted_deal_time = (datetime)1736899200;
   s.disabled_permanent = false;
   s.micro_mode = true;
   s.state_version = 2;
   
   string payload = Persistence_BuildChallengeStatePayload(s);
   
   bool has_version = (StringFind(payload, "state_version=") >= 0);
   bool has_deal_time = (StringFind(payload, "last_counted_deal_time=") >= 0);
   bool has_write_time = (StringFind(payload, "last_state_write_time=") >= 0);
   bool has_micro_date = (StringFind(payload, "last_micro_entry_server_date=") >= 0);
   
   ASSERT_TRUE(has_version, "Payload should contain state_version field");
   ASSERT_TRUE(has_deal_time, "Payload should contain last_counted_deal_time field");
   ASSERT_TRUE(has_write_time, "Payload should contain last_state_write_time field");
   ASSERT_TRUE(has_micro_date, "Payload should contain last_micro_entry_server_date field");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Run all persistence state tests
//+------------------------------------------------------------------+
bool TestPersistenceState_RunAll()
{
   Print("==============================================================");
   Print("M4 Task04 Persistence State Tests");
   Print("==============================================================");

   int local_passed = 0;
   int local_failed = 0;

   bool ok = true;
   
   // Reset counters for this suite
   int start_passed = g_test_passed;
   int start_failed = g_test_failed;
   
   ok &= Test_PersistenceState_ClampNegativeDaysTraded();
   ok &= Test_PersistenceState_ClampInvalidBaseline();
   ok &= Test_PersistenceState_DisabledPermanentEnforced();
   ok &= Test_PersistenceState_VersionSet();
   ok &= Test_PersistenceState_ClampFutureDealTime();
   ok &= Test_PersistenceState_DirtyFlagTracking();
   ok &= Test_PersistenceState_PayloadContainsNewFields();

   local_passed = g_test_passed - start_passed;
   local_failed = g_test_failed - start_failed;
   
   PrintFormat("Persistence State Test Summary: %d passed, %d failed", local_passed, local_failed);
   return (local_failed == 0);
}

#endif // TEST_PERSISTENCE_STATE_MQH
