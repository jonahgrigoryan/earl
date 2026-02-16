#ifndef TEST_ADAPTIVE_RISK_MQH
#define TEST_ADAPTIVE_RISK_MQH
// test_adaptive_risk.mqh - Post-M7 Phase 3 adaptive risk tests

#include <RPEA/adaptive.mqh>

#ifndef TEST_FRAMEWORK_DEFINED
extern int g_test_passed;
extern int g_test_failed;
extern string g_current_test;

#define ASSERT_TRUE(condition, message) \
   do { \
      if(condition) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s", g_current_test, message); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s", g_current_test, message); \
      } \
   } while(false)

#define ASSERT_FALSE(condition, message) ASSERT_TRUE(!(condition), message)

#define TEST_FRAMEWORK_DEFINED
#endif

int TestAdaptive_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool TestAdaptive_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s - %s", g_current_test, ok ? "OK" : "FAILED");
   return ok;
}

bool TestAdaptiveRisk_MappingDeterministic()
{
   int f = TestAdaptive_Begin("TestAdaptiveRisk_MappingDeterministic");

   double trending = Adaptive_RiskMultiplierWithBounds("TRENDING", 0.80, 0.80, 1.20);
   double ranging = Adaptive_RiskMultiplierWithBounds("RANGING", 0.55, 0.80, 1.20);
   double volatile = Adaptive_RiskMultiplierWithBounds("VOLATILE", 0.20, 0.80, 1.20);

   ASSERT_TRUE(MathAbs(trending - 1.15) < 1e-6, "trending + high efficiency boosts multiplier");
   ASSERT_TRUE(MathAbs(ranging - 0.97) < 1e-6, "ranging + neutral efficiency stays near baseline");
   ASSERT_TRUE(MathAbs(volatile - 0.80) < 1e-6, "volatile + weak efficiency clamps at lower bound");

   return TestAdaptive_End(f);
}

bool TestAdaptiveRisk_InvalidEfficiencyFallsBack()
{
   int f = TestAdaptive_Begin("TestAdaptiveRisk_InvalidEfficiencyFallsBack");

   double above_one = Adaptive_RiskMultiplierWithBounds("TRENDING", 1.50, 0.80, 1.20);
   double below_zero = Adaptive_RiskMultiplierWithBounds("VOLATILE", -0.10, 0.80, 1.20);

   ASSERT_TRUE(MathAbs(above_one - 1.0) < 1e-6, "efficiency > 1 falls back to neutral multiplier");
   ASSERT_TRUE(MathAbs(below_zero - 1.0) < 1e-6, "efficiency < 0 falls back to neutral multiplier");

   return TestAdaptive_End(f);
}

bool TestAdaptiveRisk_StrictClampBounds()
{
   int f = TestAdaptive_Begin("TestAdaptiveRisk_StrictClampBounds");

   double clamped_high = Adaptive_RiskMultiplierWithBounds("TRENDING", 0.80, 0.95, 1.05);
   double clamped_low = Adaptive_RiskMultiplierWithBounds("VOLATILE", 0.20, 0.95, 1.05);
   double swapped_bounds = Adaptive_RiskMultiplierWithBounds("TRENDING", 0.80, 1.10, 0.90);

   ASSERT_TRUE(MathAbs(clamped_high - 1.05) < 1e-6, "upper clamp enforced");
   ASSERT_TRUE(MathAbs(clamped_low - 0.95) < 1e-6, "lower clamp enforced");
   ASSERT_TRUE(MathAbs(swapped_bounds - 1.10) < 1e-6, "invalid bound order is sanitized before clamp");

   return TestAdaptive_End(f);
}

bool TestAdaptiveRisk_UsesConfiguredBounds()
{
   int f = TestAdaptive_Begin("TestAdaptiveRisk_UsesConfiguredBounds");

   Config_Test_SetAdaptiveRiskBoundsOverride(true, 0.90, 1.10);
   double multiplier = Adaptive_RiskMultiplier("TRENDING", 0.80);
   Config_Test_ClearAdaptiveRiskBoundsOverride();

   ASSERT_TRUE(MathAbs(multiplier - 1.10) < 1e-6, "main API clamps using configured bounds");

   return TestAdaptive_End(f);
}

bool TestAdaptiveRisk_RunAll()
{
   Print("=================================================================");
   Print("Post-M7 Task10/11 - Adaptive Risk Tests");
   Print("=================================================================");

   bool ok1 = TestAdaptiveRisk_MappingDeterministic();
   bool ok2 = TestAdaptiveRisk_InvalidEfficiencyFallsBack();
   bool ok3 = TestAdaptiveRisk_StrictClampBounds();
   bool ok4 = TestAdaptiveRisk_UsesConfiguredBounds();

   return (ok1 && ok2 && ok3 && ok4);
}

#endif // TEST_ADAPTIVE_RISK_MQH
