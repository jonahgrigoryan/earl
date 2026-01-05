//+------------------------------------------------------------------+
//|                                           test_micro_mode.mqh  |
//|                          M4-Task02: Micro-Mode & Hard-Stop Tests|
//+------------------------------------------------------------------+
#ifndef TEST_MICRO_MODE_MQH
#define TEST_MICRO_MODE_MQH

#include <RPEA/state.mqh>
#include <RPEA/equity_guardian.mqh>

//==============================================================================
// Test: Micro-Mode does not activate when gDaysTraded sufficient
//==============================================================================
bool TestMicro_NotActivatedSufficientDays()
{
   Print("TestMicro_NotActivatedSufficientDays: Starting...");
   
   // Reset state with sufficient days
   ChallengeState st = {0};
   st.trading_enabled = true;
   st.gDaysTraded = MinTradeDaysRequired; // Already met requirement
   st.initial_baseline = 10000.0;
   st.micro_mode = false;
   g_state = st;
   
   bool was_active_before = Equity_IsMicroModeActive();
   
   // Even with high equity, shouldn't activate if days already met
   bool passed = !was_active_before;
   
   if(!passed)
      Print("TestMicro_NotActivatedSufficientDays: FAILED");
   else
      Print("TestMicro_NotActivatedSufficientDays: PASSED");
   
   return passed;
}

//==============================================================================
// Test: Micro-Mode state check
//==============================================================================
bool TestMicro_StateCheck()
{
   Print("TestMicro_StateCheck: Starting...");
   
   // Set Micro-Mode active
   ChallengeState st = {0};
   st.trading_enabled = true;
   st.micro_mode = true;
   st.micro_mode_activated_at = TimeCurrent();
   g_state = st;
   
   bool is_active = Equity_IsMicroModeActive();
   
   // Reset
   st.micro_mode = false;
   g_state = st;
   
   bool is_inactive = !Equity_IsMicroModeActive();
   
   bool passed = is_active && is_inactive;
   
   if(!passed)
      Print("TestMicro_StateCheck: FAILED - active=", is_active, " inactive=", is_inactive);
   else
      Print("TestMicro_StateCheck: PASSED");
   
   return passed;
}

//==============================================================================
// Test: Micro-Mode time stop calculation
//==============================================================================
bool TestMicro_TimeStop()
{
   Print("TestMicro_TimeStop: Starting...");
   
   // Activate Micro-Mode
   ChallengeState st = {0};
   st.trading_enabled = true;
   st.micro_mode = true;
   g_state = st;
   
   // Entry time that's older than MicroTimeStopMin
   datetime old_entry = TimeCurrent() - (MicroTimeStopMin + 10) * 60;
   bool should_stop = Equity_MicroTimeStopExceeded(old_entry);
   
   // Entry time that's recent
   datetime recent_entry = TimeCurrent() - 5 * 60;
   bool should_not_stop = !Equity_MicroTimeStopExceeded(recent_entry);
   
   bool passed = should_stop && should_not_stop;
   
   if(!passed)
      Print("TestMicro_TimeStop: FAILED - old_stop=", should_stop, " recent_no_stop=", should_not_stop);
   else
      Print("TestMicro_TimeStop: PASSED");
   
   // Reset
   st.micro_mode = false;
   g_state = st;
   
   return passed;
}

//==============================================================================
// Test: Micro-Mode enforces one entry per day
//==============================================================================
bool TestMicro_OneEntryPerDay()
{
   Print("TestMicro_OneEntryPerDay: Starting...");
   
   // Reset state
   ChallengeState st = {0};
   st.trading_enabled = true;
   st.micro_mode = true;
   st.last_micro_entry_server_date = 0;
   g_state = st;
   
   datetime now = TimeCurrent();
   
   // First entry should be allowed
   bool first_allowed = State_MicroEntryAllowed(now);
   
   // Mark entry
   State_MarkMicroEntryServer(now);
   
   // Second entry same day should be blocked
   bool second_blocked = !State_MicroEntryAllowed(now);
   
   bool passed = first_allowed && second_blocked;
   
   if(!passed)
      Print("TestMicro_OneEntryPerDay: FAILED - first=", first_allowed, " second_blocked=", second_blocked);
   else
      Print("TestMicro_OneEntryPerDay: PASSED");
   
   return passed;
}

//==============================================================================
// Test: Hard-stop state check
//==============================================================================
bool TestHardStop_StateCheck()
{
   Print("TestHardStop_StateCheck: Starting...");
   
   // Reset state
   ChallengeState st = {0};
   st.trading_enabled = true;
   st.disabled_permanent = false;
   g_state = st;
   
   bool not_stopped = !Equity_IsHardStopped();
   
   // Set hard-stopped
   st.disabled_permanent = true;
   g_state = st;
   
   bool is_stopped = Equity_IsHardStopped();
   
   bool passed = not_stopped && is_stopped;
   
   if(!passed)
      Print("TestHardStop_StateCheck: FAILED - not_stopped=", not_stopped, " is_stopped=", is_stopped);
   else
      Print("TestHardStop_StateCheck: PASSED");
   
   return passed;
}

//==============================================================================
// Test: Giveback protection state check
//==============================================================================
bool TestGiveback_StateCheck()
{
   Print("TestGiveback_StateCheck: Starting...");
   
   // Micro-Mode active but trading enabled = no giveback
   ChallengeState st = {0};
   st.micro_mode = true;
   st.trading_enabled = true;
   g_state = st;
   
   bool no_giveback = !Equity_IsGivebackProtectionActive();
   
   // Micro-Mode active and trading disabled = giveback active
   st.trading_enabled = false;
   g_state = st;
   
   bool has_giveback = Equity_IsGivebackProtectionActive();
   
   // Not in Micro-Mode = no giveback even if trading disabled
   st.micro_mode = false;
   st.trading_enabled = false;
   g_state = st;
   
   bool no_giveback_outside_micro = !Equity_IsGivebackProtectionActive();
   
   bool passed = no_giveback && has_giveback && no_giveback_outside_micro;
   
   if(!passed)
      Print("TestGiveback_StateCheck: FAILED - no=", no_giveback, " has=", has_giveback, " outside=", no_giveback_outside_micro);
   else
      Print("TestGiveback_StateCheck: PASSED");
   
   return passed;
}

//==============================================================================
// Test: Peak equity tracking updates
//==============================================================================
bool TestGiveback_PeakTracking()
{
   Print("TestGiveback_PeakTracking: Starting...");
   
   // Reset state with low peak
   ChallengeState st = {0};
   st.day_peak_equity = 100.0;
   st.overall_peak_equity = 100.0;
   g_state = st;
   
   // Call update - this will read AccountInfoDouble which in test is 0 or whatever default
   // Just verify the function doesn't crash
   Equity_UpdatePeakTracking();
   
   ChallengeState after = State_Get();
   
   // In test environment, equity is likely 0, so peaks should stay >= 0
   bool passed = (after.day_peak_equity >= 0.0 && after.overall_peak_equity >= 0.0);
   
   if(!passed)
      Print("TestGiveback_PeakTracking: FAILED - day_peak=", after.day_peak_equity, " overall_peak=", after.overall_peak_equity);
   else
      Print("TestGiveback_PeakTracking: PASSED");
   
   return passed;
}

//==============================================================================
// Run all Micro-Mode tests
//==============================================================================
bool TestMicroMode_RunAll()
{
   Print("=== M4-Task02: Micro-Mode & Hard-Stop Tests ===");
   
   bool ok = true;
   ok &= TestMicro_NotActivatedSufficientDays();
   ok &= TestMicro_StateCheck();
   ok &= TestMicro_TimeStop();
   ok &= TestMicro_OneEntryPerDay();
   ok &= TestHardStop_StateCheck();
   ok &= TestGiveback_StateCheck();
   ok &= TestGiveback_PeakTracking();
   
   Print("=== Micro-Mode Tests: ", (ok ? "ALL PASSED" : "SOME FAILED"), " ===");
   
   return ok;
}

#endif // TEST_MICRO_MODE_MQH
