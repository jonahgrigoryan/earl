#ifndef TEST_ORDER_ENGINE_BREAKEVEN_MQH
#define TEST_ORDER_ENGINE_BREAKEVEN_MQH

#include <RPEA/breakeven.mqh>
#include <RPEA/queue.mqh>
#include <RPEA/trailing.mqh>

// Stub to observe apply calls in tests
static bool g_be_stub_called = false;
static double g_be_stub_last_sl = 0.0;
static string g_be_stub_last_ctx = "";

bool Breakeven_Test_Modify(const string symbol,
                           const long ticket,
                           const double new_sl,
                           const double new_tp,
                           const string context)
{
   g_be_stub_called = true;
   g_be_stub_last_sl = new_sl;
   g_be_stub_last_ctx = context;
   return true;
}

int tbe_passed = 0;
int tbe_failed = 0;
string tbe_current = "";

#define TBE_ASSERT_TRUE(cond, msg) \
   do { \
      if(cond) { \
         tbe_passed++; \
         PrintFormat("[PASS] %s: %s", tbe_current, msg); \
      } else { \
         tbe_failed++; \
         PrintFormat("[FAIL] %s: %s", tbe_current, msg); \
      } \
   } while(false)

#define TBE_ASSERT_NEAR(expected, actual, tol, msg) \
   do { \
      double __exp = (expected); \
      double __act = (actual); \
      double __tol = (tol); \
      if(MathAbs(__exp - __act) <= __tol) { \
         tbe_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%.6f actual=%.6f tol=%.6f)", tbe_current, msg, __exp, __act, __tol); \
      } else { \
         tbe_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%.6f actual=%.6f tol=%.6f)", tbe_current, msg, __exp, __act, __tol); \
      } \
   } while(false)

bool TestBreakeven_TriggerAtHalfR()
{
   tbe_current = "Breakeven_TriggerAtHalfR";
   bool long_not = Breakeven_ShouldTriggerFromState(true, 1000.0, 1003.0, 10.0);
   TBE_ASSERT_TRUE(!long_not, "Long not triggered below +0.5R");

   bool long_yes = Breakeven_ShouldTriggerFromState(true, 1000.0, 1005.1, 10.0);
   TBE_ASSERT_TRUE(long_yes, "Long triggers at +0.5R");

   bool short_not = Breakeven_ShouldTriggerFromState(false, 1000.0, 998.0, 10.0);
   TBE_ASSERT_TRUE(!short_not, "Short not triggered above -0.5R");

   bool short_yes = Breakeven_ShouldTriggerFromState(false, 1000.0, 994.8, 10.0);
   TBE_ASSERT_TRUE(short_yes, "Short triggers at -0.5R");

   return (tbe_failed == 0);
}

bool TestBreakeven_TargetSL_LongShort()
{
   tbe_current = "Breakeven_TargetSL";
   double point = 0.01;
   int digits = 2;
   double spread = 0.40; // 40 points * 0.01

   double target_long = Breakeven_ComputeTargetSLFromState(true,
                                                           1000.00,
                                                           995.00,
                                                           spread,
                                                           point,
                                                           digits);
   TBE_ASSERT_NEAR(1000.40, target_long, 1e-4, "Long breakeven adds spread and rounds");

   double target_short = Breakeven_ComputeTargetSLFromState(false,
                                                            1000.00,
                                                            1005.00,
                                                            spread,
                                                            point,
                                                            digits);
   TBE_ASSERT_NEAR(999.60, target_short, 1e-4, "Short breakeven subtracts spread and rounds");

   return (tbe_failed == 0);
}

bool TestBreakeven_Monotonic_NoWiden()
{
   tbe_current = "Breakeven_Monotonic";
   double point = 0.01;
   int digits = 2;
   double spread = 0.40;

   double target_long = Breakeven_ComputeTargetSLFromState(true,
                                                           1000.00,
                                                           1002.00, // already above entry
                                                           spread,
                                                           point,
                                                           digits);
   TBE_ASSERT_NEAR(1002.00, target_long, 1e-4, "Long breakeven does not widen SL backward");

   double target_short = Breakeven_ComputeTargetSLFromState(false,
                                                            1000.00,
                                                            998.00, // already below entry
                                                            spread,
                                                            point,
                                                            digits);
   TBE_ASSERT_NEAR(998.00, target_short, 1e-4, "Short breakeven does not widen SL backward");

   return (tbe_failed == 0);
}

bool OE_Test_Modify(const QueuedAction &qa)
{
   g_be_stub_called = true;
   g_be_stub_last_sl = qa.new_sl;
   g_be_stub_last_ctx = qa.context_hex;
   return true;
}

bool TestBreakeven_QueuesDuringNews()
{
   tbe_current = "Breakeven_QueuesDuringNews";

   Queue_Test_Reset();
   Queue_Init(5, 5, true);
   Queue_Test_SetRiskOverrides(true, true, true, true, true);
   Queue_Test_SetNewsBlocked(true);
   Queue_Test_RegisterPosition(6101, true, 1005.0, 999.0, 0.0);

   long queued_id = 0;
   bool queued = Breakeven_QueueDuringNews("XAUUSD",
                                           6101,
                                           1005.0,
                                           "{\"source\":\"breakeven\"}",
                                           queued_id);
   TBE_ASSERT_TRUE(queued, "Breakeven enqueues during news window");
   TBE_ASSERT_TRUE(Queue_Size() == 1, "Queue contains one breakeven action");

   QueuedAction qa;
   bool got = Queue_Test_GetAction(0, qa);
   TBE_ASSERT_TRUE(got, "Queued action retrievable");
   if(got)
   {
      TBE_ASSERT_TRUE(qa.ticket == 6101, "Queued ticket matches");
      TBE_ASSERT_NEAR(1005.0, qa.new_sl, 1e-6, "Queued SL matches target");
      TBE_ASSERT_TRUE(qa.action_type == QA_SL_MODIFY, "Action type is SL modify");
   }

   Queue_Test_SetNewsBlocked(false);
   g_be_stub_called = false;
   g_be_stub_last_sl = 0.0;
   g_be_stub_last_ctx = "";

   Queue_RevalidateAndApply();

   TBE_ASSERT_TRUE(Queue_Size() == 0, "Queue empties after apply");
   TBE_ASSERT_TRUE(g_be_stub_called, "Modify stub called on apply");

   Queue_Test_Reset();
   return (tbe_failed == 0);
}

bool TestBreakeven_AllowsTrailingAtOneR()
{
   tbe_current = "Breakeven_AllowsTrailingAtOneR";

   double entry = 1000.0;
   double entry_sl = 990.0;
   double baseline_r = MathAbs(entry - entry_sl);

   bool trigger_half = Breakeven_ShouldTriggerFromState(true, entry, entry + baseline_r * 0.5 + 0.1, baseline_r);
   TBE_ASSERT_TRUE(trigger_half, "Breakeven triggers at +0.5R");

   double point = 0.01;
   int digits = 2;
   double spread_price = 0.40;
   double target_sl = Breakeven_ComputeTargetSLFromState(true,
                                                         entry,
                                                         entry_sl,
                                                         spread_price,
                                                         point,
                                                         digits);

   bool trail_active = Trail_ShouldActivateFromState(true,
                                                     entry,
                                                     entry + baseline_r,
                                                     baseline_r);
   TBE_ASSERT_TRUE(trail_active, "Trailing activates at +1R after breakeven");
   TBE_ASSERT_TRUE(target_sl <= entry + spread_price + 1e-6, "Breakeven SL stays near entry + spread");

   return (tbe_failed == 0);
}

bool TestBreakeven_RunAll()
{
   Print("=================================================================");
   Print("RPEA Breakeven Manager Tests - Task 23");
   Print("=================================================================");
   tbe_passed = 0;
   tbe_failed = 0;

   bool trigger_ok = TestBreakeven_TriggerAtHalfR();
   bool target_ok = TestBreakeven_TargetSL_LongShort();
   bool monotonic_ok = TestBreakeven_Monotonic_NoWiden();
   bool queue_news_ok = TestBreakeven_QueuesDuringNews();
   bool trailing_ok = TestBreakeven_AllowsTrailingAtOneR();

   if(!trigger_ok || !target_ok || !monotonic_ok || !queue_news_ok || !trailing_ok)
      Print("Breakeven tests reported failures");
   else
      Print("Breakeven tests passed");

   return (tbe_failed == 0);
}

#endif // TEST_ORDER_ENGINE_BREAKEVEN_MQH

