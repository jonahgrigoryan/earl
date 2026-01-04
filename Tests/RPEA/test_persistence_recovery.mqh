//+------------------------------------------------------------------+
//|                                    test_persistence_recovery.mqh |
//|                M4-Task04: Persistence Recovery & Logging Tests   |
//+------------------------------------------------------------------+
#ifndef TEST_PERSISTENCE_RECOVERY_MQH
#define TEST_PERSISTENCE_RECOVERY_MQH

#include <RPEA/persistence.mqh>
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
// Test: State_MarkDirty updates last_state_write_time
//+------------------------------------------------------------------+
bool Test_PersistenceRecovery_MarkDirtyUpdatesTime()
{
   g_current_test = "Test_PersistenceRecovery_MarkDirtyUpdatesTime";
   Print("Running: ", g_current_test);
   
   // Save original state
   ChallengeState orig_st = State_Get();
   
   ChallengeState st;
   ZeroMemory(st);
   st.initial_baseline = 10000.0;
   st.baseline_today = 10000.0;
   st.last_state_write_time = (datetime)0;
   State_Set(st);
   
   datetime before = TimeCurrent();
   State_MarkDirty();
   datetime after = TimeCurrent();
   
   st = State_Get();
   bool time_updated = (st.last_state_write_time >= before && st.last_state_write_time <= after);
   bool is_dirty = Persistence_IsDirty();
   
   // Restore state
   State_Set(orig_st);
   Persistence_ClearDirty();
   
   ASSERT_TRUE(time_updated, "State_MarkDirty should update last_state_write_time");
   ASSERT_TRUE(is_dirty, "Persistence should be marked dirty");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Idempotent trade-day counting with deal_time
//+------------------------------------------------------------------+
bool Test_PersistenceRecovery_IdempotentTradeDayCounting()
{
   g_current_test = "Test_PersistenceRecovery_IdempotentTradeDayCounting";
   Print("Running: ", g_current_test);
   
   // Save original state
   ChallengeState orig_st = State_Get();
   
   // Setup: fresh state for a specific date
   ChallengeState st;
   ZeroMemory(st);
   st.initial_baseline = 10000.0;
   st.baseline_today = 10000.0;
   st.gDaysTraded = 0;
   st.last_counted_server_date = 0;
   st.last_counted_deal_time = (datetime)0;
   State_Set(st);
   
   datetime test_time = D'2025.01.15 12:00:00';
   datetime deal_time_1 = test_time;
   datetime deal_time_2 = test_time + 60;  // 1 minute later (same day)
   
   // First call should count the day
   State_MarkTradeDayServer(test_time, deal_time_1);
   st = State_Get();
   int days_after_first = st.gDaysTraded;
   
   // Second call same day with later deal_time should NOT count again
   State_MarkTradeDayServer(test_time, deal_time_2);
   st = State_Get();
   int days_after_second = st.gDaysTraded;
   
   // Third call with EARLIER deal_time (simulating replay) should NOT count
   State_MarkTradeDayServer(test_time, deal_time_1 - 10);
   st = State_Get();
   int days_after_replay = st.gDaysTraded;
   
   // Restore state
   State_Set(orig_st);
   Persistence_ClearDirty();
   
   ASSERT_TRUE(days_after_first == 1, "First entry should count trade day");
   ASSERT_TRUE(days_after_second == 1, "Second entry same day should NOT count again");
   ASSERT_TRUE(days_after_replay == 1, "Replay with earlier deal_time should NOT count");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: DisablePermanent triggers MarkDirty
//+------------------------------------------------------------------+
bool Test_PersistenceRecovery_DisablePermanentMarksDirty()
{
   g_current_test = "Test_PersistenceRecovery_DisablePermanentMarksDirty";
   Print("Running: ", g_current_test);
   
   // Save original state
   ChallengeState orig_st = State_Get();
   Persistence_ClearDirty();
   
   ChallengeState st;
   ZeroMemory(st);
   st.initial_baseline = 10000.0;
   st.baseline_today = 10000.0;
   st.disabled_permanent = false;
   st.trading_enabled = true;
   State_Set(st);
   Persistence_ClearDirty();
   
   // Call State_DisablePermanent
   State_DisablePermanent();
   
   st = State_Get();
   bool is_disabled = st.disabled_permanent;
   bool trading_off = !st.trading_enabled;
   bool is_dirty = Persistence_IsDirty();
   
   // Restore state
   State_Set(orig_st);
   Persistence_ClearDirty();
   
   ASSERT_TRUE(is_disabled, "disabled_permanent should be true");
   ASSERT_TRUE(trading_off, "trading_enabled should be false");
   ASSERT_TRUE(is_dirty, "Persistence should be marked dirty after disable");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Persistence recovery summary struct initialized
//+------------------------------------------------------------------+
bool Test_PersistenceRecovery_SummaryStructInitialized()
{
   g_current_test = "Test_PersistenceRecovery_SummaryStructInitialized";
   Print("Running: ", g_current_test);
   
   PersistenceRecoverySummary summary;
   ZeroMemory(summary);
   
   // After ZeroMemory, all fields should be 0/false
   bool intents_zero = (summary.intents_total == 0);
   bool loaded_zero = (summary.intents_loaded == 0);
   bool dropped_zero = (summary.intents_dropped == 0);
   bool renamed_false = !summary.renamed_corrupt_file;
   
   ASSERT_TRUE(intents_zero, "intents_total should be 0 after ZeroMemory");
   ASSERT_TRUE(loaded_zero, "intents_loaded should be 0 after ZeroMemory");
   ASSERT_TRUE(dropped_zero, "intents_dropped should be 0 after ZeroMemory");
   ASSERT_TRUE(renamed_false, "renamed_corrupt_file should be false after ZeroMemory");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: STATE_VERSION_CURRENT is defined
//+------------------------------------------------------------------+
bool Test_PersistenceRecovery_StateVersionDefined()
{
   g_current_test = "Test_PersistenceRecovery_StateVersionDefined";
   Print("Running: ", g_current_test);
   
   int version = STATE_VERSION_CURRENT;
   
   ASSERT_TRUE(version >= 2, 
               StringFormat("STATE_VERSION_CURRENT should be >= 2 (got %d)", version));
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Validation handles NaN baseline
//+------------------------------------------------------------------+
bool Test_PersistenceRecovery_ValidationHandlesNaN()
{
   g_current_test = "Test_PersistenceRecovery_ValidationHandlesNaN";
   Print("Running: ", g_current_test);
   
   ChallengeState s;
   ZeroMemory(s);
   // Create NaN by 0.0/0.0
   double nan_val = 0.0;
   if(nan_val == 0.0) nan_val = nan_val / nan_val;  // Produces NaN
   
   s.initial_baseline = nan_val;
   s.baseline_today = 10000.0;
   
   string reason;
   Persistence_ValidateChallengeState(s, reason);
   
   // After validation, initial_baseline should be repaired
   bool is_valid = MathIsValidNumber(s.initial_baseline);
   bool is_positive = (s.initial_baseline > 0.0);
   
   ASSERT_TRUE(is_valid, "NaN initial_baseline should be replaced with valid number");
   ASSERT_TRUE(is_positive, "Repaired initial_baseline should be positive");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Run all persistence recovery tests
//+------------------------------------------------------------------+
bool TestPersistenceRecovery_RunAll()
{
   Print("==============================================================");
   Print("M4 Task04 Persistence Recovery Tests");
   Print("==============================================================");

   int local_passed = 0;
   int local_failed = 0;

   bool ok = true;
   
   // Reset counters for this suite
   int start_passed = g_test_passed;
   int start_failed = g_test_failed;
   
   ok &= Test_PersistenceRecovery_MarkDirtyUpdatesTime();
   ok &= Test_PersistenceRecovery_IdempotentTradeDayCounting();
   ok &= Test_PersistenceRecovery_DisablePermanentMarksDirty();
   ok &= Test_PersistenceRecovery_SummaryStructInitialized();
   ok &= Test_PersistenceRecovery_StateVersionDefined();
   ok &= Test_PersistenceRecovery_ValidationHandlesNaN();

   local_passed = g_test_passed - start_passed;
   local_failed = g_test_failed - start_failed;
   
   PrintFormat("Persistence Recovery Test Summary: %d passed, %d failed", local_passed, local_failed);
   return (local_failed == 0);
}

#endif // TEST_PERSISTENCE_RECOVERY_MQH
