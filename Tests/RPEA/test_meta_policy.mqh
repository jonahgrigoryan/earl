#ifndef TEST_META_POLICY_MQH
#define TEST_META_POLICY_MQH
// test_meta_policy.mqh - Unit tests for M7 Meta-Policy (Task 05)
// Tests MetaPolicy_DeterministicChoice() directly to verify rule ordering.

#include <RPEA/meta_policy.mqh>

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

#define ASSERT_STR_EQ(expected, actual, msg) \
   do { \
      if((expected) == (actual)) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s (got \"%s\")", g_current_test, msg, actual); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected \"%s\", got \"%s\")", \
            g_current_test, msg, expected, actual); \
      } \
   } while(false)

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
int TestMP_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool TestMP_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s - %s", g_current_test, ok ? "OK" : "FAILED");
   return ok;
}

// Returns a neutral context where no rule fires (default = Skip).
MetaPolicyContext MakeDefaultContext()
{
   MetaPolicyContext mpc;
   mpc.bwisc_has_setup      = false;
   mpc.bwisc_confidence     = 0.0;
   mpc.bwisc_ore            = 0.80;
   mpc.bwisc_efficiency     = 0.0;
   mpc.mr_has_setup         = false;
   mpc.mr_confidence        = 0.0;
   mpc.emrt_rank            = 0.50;
   mpc.q_advantage          = 0.50;
   mpc.mr_efficiency        = 0.0;
   mpc.atr_d1_percentile    = 0.50;
   mpc.session_age_minutes  = 60;
   mpc.news_within_15m      = false;
   mpc.entry_blocked        = false;
   mpc.spread_quantile      = 0.50;
   mpc.slippage_quantile    = 0.50;
   mpc.regime_label         = 0;
   mpc.entries_this_session = 0;
   mpc.locked_to_mr         = false;
   return mpc;
}

//+------------------------------------------------------------------+
//| Test: Rule 0 - Entry blocked                                      |
//+------------------------------------------------------------------+
bool TestMP_Rule0_EntryBlocked()
{
   int f = TestMP_Begin("TestMP_Rule0_EntryBlocked");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.entry_blocked = true;
   // Even with MR lock and setup, entry_blocked takes priority
   mpc.locked_to_mr  = true;
   mpc.mr_has_setup  = true;
   mpc.mr_confidence = 0.95;
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("Skip", result, "entry_blocked overrides all");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Rule 0b - Spread quantile gate                              |
//+------------------------------------------------------------------+
bool TestMP_Rule0b_SpreadGate()
{
   int f = TestMP_Begin("TestMP_Rule0b_SpreadGate");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.spread_quantile = 0.95;
   mpc.mr_has_setup    = true;
   mpc.mr_confidence   = 0.95;
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("Skip", result, "high spread_quantile blocks entry");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Rule 0b - Slippage quantile gate                            |
//+------------------------------------------------------------------+
bool TestMP_Rule0b_SlippageGate()
{
   int f = TestMP_Begin("TestMP_Rule0b_SlippageGate");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.slippage_quantile = 0.92;
   mpc.mr_has_setup      = true;
   mpc.mr_confidence     = 0.95;
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("Skip", result, "high slippage_quantile blocks entry");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Rule 1 - Session cap                                        |
//+------------------------------------------------------------------+
bool TestMP_Rule1_SessionCap()
{
   int f = TestMP_Begin("TestMP_Rule1_SessionCap");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.entries_this_session = 2;
   mpc.bwisc_has_setup      = true;
   mpc.bwisc_confidence     = 0.85;
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("Skip", result, "session cap >= 2 blocks entry");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Rule 2 - MR lock hysteresis                                 |
//+------------------------------------------------------------------+
bool TestMP_Rule2_MRLock()
{
   int f = TestMP_Begin("TestMP_Rule2_MRLock");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.locked_to_mr = true;
   mpc.mr_has_setup = true;
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("MR", result, "locked_to_mr with mr_has_setup returns MR");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Rule 2 - MR lock without setup falls through                |
//+------------------------------------------------------------------+
bool TestMP_Rule2_MRLockNoSetup()
{
   int f = TestMP_Begin("TestMP_Rule2_MRLockNoSetup");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.locked_to_mr = true;
   mpc.mr_has_setup = false;
   // No BWISC either, so should fall through to default Skip
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("Skip", result, "locked_to_mr without mr_has_setup falls through");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Rule 3 - Confidence tie-breaker favours MR                  |
//+------------------------------------------------------------------+
bool TestMP_Rule3_ConfidenceTieBreaker()
{
   int f = TestMP_Begin("TestMP_Rule3_ConfidenceTieBreaker");
   MetaPolicyContext mpc = MakeDefaultContext();
   // BWISC conf below cut (default 0.70), MR conf above cut (default 0.80)
   mpc.bwisc_confidence = 0.60;
   mpc.mr_confidence    = 0.85;
   mpc.mr_efficiency    = 0.5;
   mpc.bwisc_efficiency = 0.3;
   mpc.mr_has_setup     = true;
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("MR", result, "low BWISC conf + high MR conf = MR");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Rule 4 - Conditional BWISC replacement                      |
//+------------------------------------------------------------------+
bool TestMP_Rule4_ConditionalReplacement()
{
   int f = TestMP_Begin("TestMP_Rule4_ConditionalReplacement");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.bwisc_ore           = 0.30;   // < 0.40
   mpc.atr_d1_percentile   = 0.40;   // < 0.50
   mpc.emrt_rank           = 0.35;   // <= 40/100 = 0.40
   mpc.session_age_minutes = 90;     // < 120
   mpc.news_within_15m     = false;
   mpc.mr_has_setup        = true;
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("MR", result, "conditional BWISC replacement triggers MR");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Rule 4 - Fails if any condition unmet (high ORE)            |
//+------------------------------------------------------------------+
bool TestMP_Rule4_FailsHighORE()
{
   int f = TestMP_Begin("TestMP_Rule4_FailsHighORE");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.bwisc_ore           = 0.50;   // >= 0.40: fails condition
   mpc.atr_d1_percentile   = 0.40;
   mpc.emrt_rank           = 0.35;
   mpc.session_age_minutes = 90;
   mpc.news_within_15m     = false;
   mpc.mr_has_setup        = true;
   // Should fall to Rule 6 (no bwisc setup, mr has setup)
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("MR", result, "high ORE skips Rule 4, falls to Rule 6");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Rule 5 - BWISC qualified                                    |
//+------------------------------------------------------------------+
bool TestMP_Rule5_BWISCQualified()
{
   int f = TestMP_Begin("TestMP_Rule5_BWISCQualified");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.bwisc_has_setup  = true;
   mpc.bwisc_confidence = 0.85;  // >= 0.70 default cut
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("BWISC", result, "qualified BWISC returns BWISC");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Rule 5 - BWISC below cut falls through                     |
//+------------------------------------------------------------------+
bool TestMP_Rule5_BWISCBelowCut()
{
   int f = TestMP_Begin("TestMP_Rule5_BWISCBelowCut");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.bwisc_has_setup  = true;
   mpc.bwisc_confidence = 0.60;  // < 0.70 default cut
   // No MR setup either
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("Skip", result, "BWISC below conf cut falls to default");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Rule 6 - MR fallback                                        |
//+------------------------------------------------------------------+
bool TestMP_Rule6_MRFallback()
{
   int f = TestMP_Begin("TestMP_Rule6_MRFallback");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.bwisc_has_setup = false;
   mpc.mr_has_setup    = true;
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("MR", result, "no BWISC + MR setup = MR fallback");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Default - Skip                                               |
//+------------------------------------------------------------------+
bool TestMP_Default_Skip()
{
   int f = TestMP_Begin("TestMP_Default_Skip");
   MetaPolicyContext mpc = MakeDefaultContext();
   // Neither strategy has setup
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("Skip", result, "no setups returns Skip");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Precedence - entry_blocked overrides MR lock                 |
//+------------------------------------------------------------------+
bool TestMP_Precedence_BlockedOverridesLock()
{
   int f = TestMP_Begin("TestMP_Precedence_BlockedOverridesLock");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.entry_blocked  = true;
   mpc.locked_to_mr   = true;
   mpc.mr_has_setup   = true;
   mpc.bwisc_has_setup = true;
   mpc.bwisc_confidence = 0.90;
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("Skip", result, "entry_blocked overrides MR lock and BWISC");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Precedence - session cap overrides MR lock                   |
//+------------------------------------------------------------------+
bool TestMP_Precedence_SessionCapOverridesLock()
{
   int f = TestMP_Begin("TestMP_Precedence_SessionCapOverridesLock");
   MetaPolicyContext mpc = MakeDefaultContext();
   mpc.entries_this_session = 3;
   mpc.locked_to_mr         = true;
   mpc.mr_has_setup         = true;
   string result = MetaPolicy_DeterministicChoice(mpc);
   ASSERT_STR_EQ("Skip", result, "session cap overrides MR lock");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: BanditIsReady returns false in Phase 4                      |
//+------------------------------------------------------------------+
bool TestMP_BanditNotReady()
{
   int f = TestMP_Begin("TestMP_BanditNotReady");
   bool ready = MetaPolicy_BanditIsReady();
   ASSERT_TRUE(!ready, "BanditIsReady returns false in Phase 4");
   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Efficiency helpers return safe zero without samples        |
//+------------------------------------------------------------------+
bool TestMP_EfficiencyHelpers_DefaultZero()
{
   int f = TestMP_Begin("TestMP_EfficiencyHelpers_DefaultZero");
   Telemetry_TestReset();
   Telemetry_TestSetMinSamples(3);

   ASSERT_TRUE(MathAbs(MetaPolicy_GetBWISCEfficiency()) < 1e-9,
               "BWISC efficiency defaults to 0.0 with no samples");
   ASSERT_TRUE(MathAbs(MetaPolicy_GetMREfficiency()) < 1e-9,
               "MR efficiency defaults to 0.0 with no samples");

   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Test: Efficiency helpers become non-zero after threshold         |
//+------------------------------------------------------------------+
bool TestMP_EfficiencyHelpers_Thresholded()
{
   int f = TestMP_Begin("TestMP_EfficiencyHelpers_Thresholded");
   Telemetry_TestReset();
   Telemetry_TestSetMinSamples(3);

   Telemetry_TestRecordOutcome("BWISC", 1.0);
   Telemetry_TestRecordOutcome("BWISC", -0.5);
   ASSERT_TRUE(MathAbs(MetaPolicy_GetBWISCEfficiency()) < 1e-9,
               "BWISC efficiency remains zero before threshold");

   Telemetry_TestRecordOutcome("BWISC", 0.5);
   ASSERT_TRUE(MathAbs(MetaPolicy_GetBWISCEfficiency() - 0.75) < 1e-6,
               "BWISC efficiency updates after threshold");

   Telemetry_TestRecordOutcome("MR", 2.0);
   Telemetry_TestRecordOutcome("MR", 1.0);
   ASSERT_TRUE(MathAbs(MetaPolicy_GetMREfficiency()) < 1e-9,
               "MR efficiency remains zero before threshold");

   Telemetry_TestRecordOutcome("MR", -1.0);
   ASSERT_TRUE(MathAbs(MetaPolicy_GetMREfficiency() - 0.75) < 1e-6,
               "MR efficiency updates after threshold");

   return TestMP_End(f);
}

//+------------------------------------------------------------------+
//| Suite runner                                                       |
//+------------------------------------------------------------------+
bool TestMetaPolicy_RunAll()
{
   Print("=================================================================");
   Print("M7 Meta-Policy Tests - Task 05");
   Print("=================================================================");

   bool ok1  = TestMP_Rule0_EntryBlocked();
   bool ok2  = TestMP_Rule0b_SpreadGate();
   bool ok3  = TestMP_Rule0b_SlippageGate();
   bool ok4  = TestMP_Rule1_SessionCap();
   bool ok5  = TestMP_Rule2_MRLock();
   bool ok6  = TestMP_Rule2_MRLockNoSetup();
   bool ok7  = TestMP_Rule3_ConfidenceTieBreaker();
   bool ok8  = TestMP_Rule4_ConditionalReplacement();
   bool ok9  = TestMP_Rule4_FailsHighORE();
   bool ok10 = TestMP_Rule5_BWISCQualified();
   bool ok11 = TestMP_Rule5_BWISCBelowCut();
   bool ok12 = TestMP_Rule6_MRFallback();
   bool ok13 = TestMP_Default_Skip();
   bool ok14 = TestMP_Precedence_BlockedOverridesLock();
   bool ok15 = TestMP_Precedence_SessionCapOverridesLock();
   bool ok16 = TestMP_BanditNotReady();
   bool ok17 = TestMP_EfficiencyHelpers_DefaultZero();
   bool ok18 = TestMP_EfficiencyHelpers_Thresholded();

   return (ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7 && ok8 &&
           ok9 && ok10 && ok11 && ok12 && ok13 && ok14 && ok15 && ok16 &&
           ok17 && ok18);
}

#endif // TEST_META_POLICY_MQH
