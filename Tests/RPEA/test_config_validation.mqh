//+------------------------------------------------------------------+
//|                                      test_config_validation.mqh  |
//|                    M6-Task01: Parameter Validation Tests         |
//|                                                                  |
//| Tests validation helpers and getter functions for config inputs  |
//+------------------------------------------------------------------+
#ifndef TEST_CONFIG_VALIDATION_MQH
#define TEST_CONFIG_VALIDATION_MQH

#include <RPEA/config.mqh>

//+------------------------------------------------------------------+
//| Test: ORMinutes nearest value calculation                        |
//+------------------------------------------------------------------+
bool Test_ORMinutes_NearestValue()
{
   Print("  [Test] ORMinutes_NearestValue");
   bool passed = true;
   
   // Test exact matches
   if(Config_NearestORMinutes(30) != 30)
   {
      Print("    FAIL: Config_NearestORMinutes(30) should return 30");
      passed = false;
   }
   if(Config_NearestORMinutes(45) != 45)
   {
      Print("    FAIL: Config_NearestORMinutes(45) should return 45");
      passed = false;
   }
   if(Config_NearestORMinutes(60) != 60)
   {
      Print("    FAIL: Config_NearestORMinutes(60) should return 60");
      passed = false;
   }
   if(Config_NearestORMinutes(75) != 75)
   {
      Print("    FAIL: Config_NearestORMinutes(75) should return 75");
      passed = false;
   }
   
   // Test values that should round to nearest
   // 25 -> 30 (closer to 30 than 45)
   if(Config_NearestORMinutes(25) != 30)
   {
      Print("    FAIL: Config_NearestORMinutes(25) should return 30");
      passed = false;
   }
   
   // 37 -> 30 or 45 (equidistant, could be either; 37 is closer to 30)
   // Actually 37-30=7, 45-37=8, so 30 is closer
   if(Config_NearestORMinutes(37) != 30)
   {
      Print("    FAIL: Config_NearestORMinutes(37) should return 30");
      passed = false;
   }
   
   // 50 -> 45 (50-45=5, 60-50=10)
   if(Config_NearestORMinutes(50) != 45)
   {
      Print("    FAIL: Config_NearestORMinutes(50) should return 45");
      passed = false;
   }
   
   // 55 -> 60 (55-45=10, 60-55=5)
   if(Config_NearestORMinutes(55) != 60)
   {
      Print("    FAIL: Config_NearestORMinutes(55) should return 60");
      passed = false;
   }
   
   // 70 -> 75 (70-60=10, 75-70=5)
   if(Config_NearestORMinutes(70) != 75)
   {
      Print("    FAIL: Config_NearestORMinutes(70) should return 75");
      passed = false;
   }
   
   // 100 -> 75 (far out of range, 75 is closest)
   if(Config_NearestORMinutes(100) != 75)
   {
      Print("    FAIL: Config_NearestORMinutes(100) should return 75");
      passed = false;
   }
   
   // 0 -> 30 (far out of range, 30 is closest)
   if(Config_NearestORMinutes(0) != 30)
   {
      Print("    FAIL: Config_NearestORMinutes(0) should return 30");
      passed = false;
   }
   
   // -10 -> 30
   if(Config_NearestORMinutes(-10) != 30)
   {
      Print("    FAIL: Config_NearestORMinutes(-10) should return 30");
      passed = false;
   }
   
   if(passed)
      Print("    PASS");
   return passed;
}

//+------------------------------------------------------------------+
//| Test: Hour clamping [0, 23]                                      |
//+------------------------------------------------------------------+
bool Test_HourClamping()
{
   Print("  [Test] HourClamping");
   bool passed = true;
   
   // Valid hours pass through unchanged
   if(Config_ClampHour(0) != 0)
   {
      Print("    FAIL: Config_ClampHour(0) should return 0");
      passed = false;
   }
   if(Config_ClampHour(12) != 12)
   {
      Print("    FAIL: Config_ClampHour(12) should return 12");
      passed = false;
   }
   if(Config_ClampHour(23) != 23)
   {
      Print("    FAIL: Config_ClampHour(23) should return 23");
      passed = false;
   }
   
   // Out of range clamped
   if(Config_ClampHour(-1) != 0)
   {
      Print("    FAIL: Config_ClampHour(-1) should return 0");
      passed = false;
   }
   if(Config_ClampHour(-100) != 0)
   {
      Print("    FAIL: Config_ClampHour(-100) should return 0");
      passed = false;
   }
   if(Config_ClampHour(24) != 23)
   {
      Print("    FAIL: Config_ClampHour(24) should return 23");
      passed = false;
   }
   if(Config_ClampHour(100) != 23)
   {
      Print("    FAIL: Config_ClampHour(100) should return 23");
      passed = false;
   }
   
   if(passed)
      Print("    PASS");
   return passed;
}

//+------------------------------------------------------------------+
//| Test: Non-negative integer clamping                              |
//+------------------------------------------------------------------+
bool Test_NonNegativeIntClamping()
{
   Print("  [Test] NonNegativeIntClamping");
   bool passed = true;
   
   // Non-negative values pass through
   if(Config_ClampNonNegativeInt(0) != 0)
   {
      Print("    FAIL: Config_ClampNonNegativeInt(0) should return 0");
      passed = false;
   }
   if(Config_ClampNonNegativeInt(100) != 100)
   {
      Print("    FAIL: Config_ClampNonNegativeInt(100) should return 100");
      passed = false;
   }
   
   // Negative values clamped to 0
   if(Config_ClampNonNegativeInt(-1) != 0)
   {
      Print("    FAIL: Config_ClampNonNegativeInt(-1) should return 0");
      passed = false;
   }
   if(Config_ClampNonNegativeInt(-999) != 0)
   {
      Print("    FAIL: Config_ClampNonNegativeInt(-999) should return 0");
      passed = false;
   }
   
   if(passed)
      Print("    PASS");
   return passed;
}

//+------------------------------------------------------------------+
//| Test: Getter functions return expected values in test context    |
//| (In test runner, getters return the macro values directly)       |
//+------------------------------------------------------------------+
bool Test_GetterFunctions_TestContext()
{
   Print("  [Test] GetterFunctions_TestContext");
   bool passed = true;
   
   // In test runner context, most getters return the macro values
   // Verify the getter functions are callable and return reasonable values
   
   // ORMinutes - should be the macro value (60 in test runner)
   int or_minutes = Config_GetORMinutes();
   if(or_minutes != 30 && or_minutes != 45 && or_minutes != 60 && or_minutes != 75)
   {
      PrintFormat("    FAIL: Config_GetORMinutes() returned invalid value %d", or_minutes);
      passed = false;
   }
   
   // Effective daily loss cap
   double effective_daily = Config_GetEffectiveDailyLossCapPct();
   if(effective_daily <= 0)
   {
      PrintFormat("    FAIL: Config_GetEffectiveDailyLossCapPct() returned invalid value %.4f", effective_daily);
      passed = false;
   }
   
   // Session hours should be in valid range
   int start_lo = Config_GetStartHourLO();
   if(start_lo < 0 || start_lo > 23)
   {
      PrintFormat("    FAIL: Config_GetStartHourLO() returned invalid value %d", start_lo);
      passed = false;
   }
   
   int start_ny = Config_GetStartHourNY();
   if(start_ny < 0 || start_ny > 23)
   {
      PrintFormat("    FAIL: Config_GetStartHourNY() returned invalid value %d", start_ny);
      passed = false;
   }
   
   int cutoff = Config_GetCutoffHour();
   if(cutoff < 0 || cutoff > 23)
   {
      PrintFormat("    FAIL: Config_GetCutoffHour() returned invalid value %d", cutoff);
      passed = false;
   }
   
   // Min trade days should be >= 1
   int min_days = Config_GetMinTradeDaysRequired();
   if(min_days < 1)
   {
      PrintFormat("    FAIL: Config_GetMinTradeDaysRequired() returned invalid value %d", min_days);
      passed = false;
   }
   
   // Risk percentages should be within finalspec ranges
   double risk_pct = Config_GetRiskPct();
   if(risk_pct < 0.8 || risk_pct > 2.0)
   {
      PrintFormat("    FAIL: Config_GetRiskPct() returned invalid value %.4f", risk_pct);
      passed = false;
   }
   
   double micro_risk = Config_GetMicroRiskPct();
   if(micro_risk < 0.05 || micro_risk > 0.20)
   {
      PrintFormat("    FAIL: Config_GetMicroRiskPct() returned invalid value %.4f", micro_risk);
      passed = false;
   }
   
   // R-targets should be within finalspec ranges
   double rtarget_bc = Config_GetRtargetBC();
   if(rtarget_bc < 1.8 || rtarget_bc > 2.6)
   {
      PrintFormat("    FAIL: Config_GetRtargetBC() returned invalid value %.4f", rtarget_bc);
      passed = false;
   }
   
   double rtarget_msc = Config_GetRtargetMSC();
   if(rtarget_msc < 1.6 || rtarget_msc > 2.4)
   {
      PrintFormat("    FAIL: Config_GetRtargetMSC() returned invalid value %.4f", rtarget_msc);
      passed = false;
   }
   
   // Multipliers should be within finalspec ranges
   double sl_mult = Config_GetSLmult();
   if(sl_mult < 0.7 || sl_mult > 1.3)
   {
      PrintFormat("    FAIL: Config_GetSLmult() returned invalid value %.4f", sl_mult);
      passed = false;
   }
   
   double trail_mult = Config_GetTrailMult();
   if(trail_mult < 0.6 || trail_mult > 1.2)
   {
      PrintFormat("    FAIL: Config_GetTrailMult() returned invalid value %.4f", trail_mult);
      passed = false;
   }
   
   // Time values should be within finalspec ranges
   int micro_time_stop = Config_GetMicroTimeStopMin();
   if(micro_time_stop < 30 || micro_time_stop > 60)
   {
      PrintFormat("    FAIL: Config_GetMicroTimeStopMin() returned invalid value %d", micro_time_stop);
      passed = false;
   }
   
   int min_hold = Config_GetMinHoldSeconds();
   if(min_hold < 0)
   {
      PrintFormat("    FAIL: Config_GetMinHoldSeconds() returned invalid value %d", min_hold);
      passed = false;
   }
   
   int news_buffer = Config_GetNewsBufferS();
   if(news_buffer < 0)
   {
      PrintFormat("    FAIL: Config_GetNewsBufferS() returned invalid value %d", news_buffer);
      passed = false;
   }
   
   // Queue/logging sizes should be >= 1
   int max_queue = Config_GetMaxQueueSize();
   if(max_queue < 1)
   {
      PrintFormat("    FAIL: Config_GetMaxQueueSize() returned invalid value %d", max_queue);
      passed = false;
   }
   
   int log_buffer = Config_GetLogBufferSize();
   if(log_buffer < 1)
   {
      PrintFormat("    FAIL: Config_GetLogBufferSize() returned invalid value %d", log_buffer);
      passed = false;
   }
   
   // Position caps should be >= 0
   int max_positions = Config_GetMaxOpenPositionsTotal();
   if(max_positions < 0)
   {
      PrintFormat("    FAIL: Config_GetMaxOpenPositionsTotal() returned invalid value %d", max_positions);
      passed = false;
   }
   
   int max_per_symbol = Config_GetMaxOpenPerSymbol();
   if(max_per_symbol < 0)
   {
      PrintFormat("    FAIL: Config_GetMaxOpenPerSymbol() returned invalid value %d", max_per_symbol);
      passed = false;
   }
   
   int max_pendings = Config_GetMaxPendingsPerSymbol();
   if(max_pendings < 0)
   {
      PrintFormat("    FAIL: Config_GetMaxPendingsPerSymbol() returned invalid value %d", max_pendings);
      passed = false;
   }
   
   if(passed)
      Print("    PASS");
   return passed;
}

//+------------------------------------------------------------------+
//| Test: SpreadMultATR getter                                       |
//+------------------------------------------------------------------+
bool Test_SpreadMultATR_Getter()
{
   Print("  [Test] SpreadMultATR_Getter");
   bool passed = true;
   
   double spread_mult = Config_GetSpreadMultATR();
   if(spread_mult <= 0)
   {
      PrintFormat("    FAIL: Config_GetSpreadMultATR() returned non-positive value %.6f", spread_mult);
      passed = false;
   }
   
   if(passed)
      Print("    PASS");
   return passed;
}

//+------------------------------------------------------------------+
//| Test: SpreadMultATR clamp helper                                 |
//+------------------------------------------------------------------+
bool Test_SpreadMultATR_Clamp()
{
   Print("  [Test] SpreadMultATR_Clamp");
   bool passed = true;
   
   double clamped = Config_ClampSpreadMultATRValue(-0.01);
   if(clamped != DEFAULT_SpreadMultATR)
   {
      PrintFormat("    FAIL: Config_ClampSpreadMultATRValue(-0.01) should return %.6f", DEFAULT_SpreadMultATR);
      passed = false;
   }
   
   clamped = Config_ClampSpreadMultATRValue(0.0);
   if(clamped != DEFAULT_SpreadMultATR)
   {
      PrintFormat("    FAIL: Config_ClampSpreadMultATRValue(0.0) should return %.6f", DEFAULT_SpreadMultATR);
      passed = false;
   }
   
   clamped = Config_ClampSpreadMultATRValue(0.01);
   if(MathAbs(clamped - 0.01) > 1e-9)
   {
      PrintFormat("    FAIL: Config_ClampSpreadMultATRValue(0.01) should return 0.01, got %.6f", clamped);
      passed = false;
   }
   
   if(passed)
      Print("    PASS");
   return passed;
}

//+------------------------------------------------------------------+
//| Test: Leverage override getters                                  |
//+------------------------------------------------------------------+
bool Test_LeverageOverride_Getters()
{
   Print("  [Test] LeverageOverride_Getters");
   bool passed = true;
   
   int lev_fx = Config_GetLeverageOverrideFX();
   // 0 = use account, otherwise [1, 1000]
   if(lev_fx != 0 && (lev_fx < 1 || lev_fx > 1000))
   {
      PrintFormat("    FAIL: Config_GetLeverageOverrideFX() returned invalid value %d", lev_fx);
      passed = false;
   }
   
   int lev_metals = Config_GetLeverageOverrideMetals();
   if(lev_metals != 0 && (lev_metals < 1 || lev_metals > 1000))
   {
      PrintFormat("    FAIL: Config_GetLeverageOverrideMetals() returned invalid value %d", lev_metals);
      passed = false;
   }
   
   if(passed)
      Print("    PASS");
   return passed;
}

//+------------------------------------------------------------------+
//| Test: OneAndDoneR and GivebackCapDayPct getters                  |
//+------------------------------------------------------------------+
bool Test_RiskParameter_Getters()
{
   Print("  [Test] RiskParameter_Getters");
   bool passed = true;
   
   double one_and_done = Config_GetOneAndDoneR();
   if(one_and_done < 0.5 || one_and_done > 5.0)
   {
      PrintFormat("    FAIL: Config_GetOneAndDoneR() returned out-of-range value %.4f", one_and_done);
      passed = false;
   }
   
   double giveback = Config_GetGivebackCapDayPct();
   if(giveback < 0.25 || giveback > 0.50)
   {
      PrintFormat("    FAIL: Config_GetGivebackCapDayPct() returned out-of-range value %.4f", giveback);
      passed = false;
   }
   
   if(passed)
      Print("    PASS");
   return passed;
}

//+------------------------------------------------------------------+
//| Test: Stabilization parameter getters                            |
//+------------------------------------------------------------------+
bool Test_Stabilization_Getters()
{
   Print("  [Test] Stabilization_Getters");
   bool passed = true;
   
   int timeout = Config_GetStabilizationTimeoutMin();
   if(timeout < 0)
   {
      PrintFormat("    FAIL: Config_GetStabilizationTimeoutMin() returned negative value %d", timeout);
      passed = false;
   }
   
   int bars = Config_GetStabilizationBars();
   if(bars < 1)
   {
      PrintFormat("    FAIL: Config_GetStabilizationBars() returned invalid value %d", bars);
      passed = false;
   }
   
   int lookback = Config_GetStabilizationLookbackBars();
   if(lookback < 1)
   {
      PrintFormat("    FAIL: Config_GetStabilizationLookbackBars() returned invalid value %d", lookback);
      passed = false;
   }
   
   int cal_lookback = Config_GetNewsCalendarLookbackHours();
   if(cal_lookback < 0)
   {
      PrintFormat("    FAIL: Config_GetNewsCalendarLookbackHours() returned negative value %d", cal_lookback);
      passed = false;
   }
   
   int cal_lookahead = Config_GetNewsCalendarLookaheadHours();
   if(cal_lookahead < 1)
   {
      PrintFormat("    FAIL: Config_GetNewsCalendarLookaheadHours() returned invalid value %d", cal_lookahead);
      passed = false;
   }
   
   int queue_ttl = Config_GetQueueTTLMinutes();
   if(queue_ttl < 0)
   {
      PrintFormat("    FAIL: Config_GetQueueTTLMinutes() returned negative value %d", queue_ttl);
      passed = false;
   }
   
   if(passed)
      Print("    PASS");
   return passed;
}

//+------------------------------------------------------------------+
//| Test: Slippage/spread getters                                    |
//+------------------------------------------------------------------+
bool Test_SlippageSpread_Getters()
{
   Print("  [Test] SlippageSpread_Getters");
   bool passed = true;
   
   int slippage = Config_GetMaxSlippagePoints();
   if(slippage < 0)
   {
      PrintFormat("    FAIL: Config_GetMaxSlippagePoints() returned negative value %d", slippage);
      passed = false;
   }
   
   int spread = Config_GetMaxSpreadPoints();
   if(spread < 0)
   {
      PrintFormat("    FAIL: Config_GetMaxSpreadPoints() returned negative value %d", spread);
      passed = false;
   }
   
   if(passed)
      Print("    PASS");
   return passed;
}

//+------------------------------------------------------------------+
//| Test: Task17 resilience config getters                           |
//+------------------------------------------------------------------+
bool Test_Task17Resilience_Getters()
{
   Print("  [Test] Task17Resilience_Getters");
   bool passed = true;
   
   int max_failures = Config_GetMaxConsecutiveFailures();
   if(max_failures < 1)
   {
      PrintFormat("    FAIL: Config_GetMaxConsecutiveFailures() returned invalid value %d", max_failures);
      passed = false;
   }
   
   int failure_window = Config_GetFailureWindowSec();
   if(failure_window < 1)
   {
      PrintFormat("    FAIL: Config_GetFailureWindowSec() returned invalid value %d", failure_window);
      passed = false;
   }
   
   int cooldown = Config_GetCircuitBreakerCooldownSec();
   if(cooldown < 1)
   {
      PrintFormat("    FAIL: Config_GetCircuitBreakerCooldownSec() returned invalid value %d", cooldown);
      passed = false;
   }
   
   int heal_window = Config_GetSelfHealRetryWindowSec();
   if(heal_window < 1)
   {
      PrintFormat("    FAIL: Config_GetSelfHealRetryWindowSec() returned invalid value %d", heal_window);
      passed = false;
   }
   
   int heal_attempts = Config_GetSelfHealMaxAttempts();
   if(heal_attempts < 1)
   {
      PrintFormat("    FAIL: Config_GetSelfHealMaxAttempts() returned invalid value %d", heal_attempts);
      passed = false;
   }
   
   int alert_throttle = Config_GetErrorAlertThrottleSec();
   if(alert_throttle < 1)
   {
      PrintFormat("    FAIL: Config_GetErrorAlertThrottleSec() returned invalid value %d", alert_throttle);
      passed = false;
   }
   
   // BreakerProtectiveExitBypass is bool, just call it
   bool bypass = Config_GetBreakerProtectiveExitBypass();
   // No validation needed for bool, just verify it's callable
   
   if(passed)
      Print("    PASS");
   return passed;
}

//+------------------------------------------------------------------+
//| Test: Breakeven config getter                                    |
//+------------------------------------------------------------------+
bool Test_Breakeven_Getter()
{
   Print("  [Test] Breakeven_Getter");
   bool passed = true;
   
   double extra_points = Config_GetBreakevenExtraPoints();
   // Extra points should be >= 0
   if(extra_points < 0)
   {
      PrintFormat("    FAIL: Config_GetBreakevenExtraPoints() returned negative value %.4f", extra_points);
      passed = false;
   }
   
   if(passed)
      Print("    PASS");
   return passed;
}

//+------------------------------------------------------------------+
//| Run all config validation tests                                  |
//+------------------------------------------------------------------+
bool TestConfigValidation_RunAll()
{
   Print("=================================================================");
   Print("M6-Task01: Config Validation Tests");
   Print("=================================================================");
   
   bool all_passed = true;
   
   // Core validation logic tests
   all_passed &= Test_ORMinutes_NearestValue();
   all_passed &= Test_HourClamping();
   all_passed &= Test_NonNegativeIntClamping();
   
   // Getter function tests (verify they return valid values)
   all_passed &= Test_GetterFunctions_TestContext();
   all_passed &= Test_SpreadMultATR_Getter();
   all_passed &= Test_SpreadMultATR_Clamp();
   all_passed &= Test_LeverageOverride_Getters();
   all_passed &= Test_RiskParameter_Getters();
   all_passed &= Test_Stabilization_Getters();
   all_passed &= Test_SlippageSpread_Getters();
   all_passed &= Test_Task17Resilience_Getters();
   all_passed &= Test_Breakeven_Getter();
   
   if(all_passed)
      Print("[SUCCESS] All config validation tests passed");
   else
      Print("[FAILURE] Some config validation tests failed");
   
   return all_passed;
}

#endif // TEST_CONFIG_VALIDATION_MQH
