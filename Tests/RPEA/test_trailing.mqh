#ifndef TEST_TRAILING_MQH
#define TEST_TRAILING_MQH

#include <RPEA/trailing.mqh>
#include <RPEA/queue.mqh>

int ttrail_passed = 0;
int ttrail_failed = 0;
string ttrail_current = "";

#define TTR_ASSERT_TRUE(cond, msg) \
   do { \
      if(cond) { \
         ttrail_passed++; \
         PrintFormat("[PASS] %s: %s", ttrail_current, msg); \
      } else { \
         ttrail_failed++; \
         PrintFormat("[FAIL] %s: %s", ttrail_current, msg); \
      } \
   } while(false)

#define TTR_ASSERT_EQUALS(exp, act, msg) \
   do { \
      int __exp = (int)(exp); \
      int __act = (int)(act); \
      if(__exp == __act) { \
         ttrail_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%d actual=%d)", ttrail_current, msg, __exp, __act); \
      } else { \
         ttrail_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%d actual=%d)", ttrail_current, msg, __exp, __act); \
      } \
   } while(false)

#define TTR_ASSERT_NEAR(expected, actual, tol, msg) \
   do { \
      double __exp = (expected); \
      double __act = (actual); \
      double __tol = (tol); \
      if(MathAbs(__exp - __act) <= __tol) { \
         ttrail_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%.6f actual=%.6f tol=%.6f)", ttrail_current, msg, __exp, __act, __tol); \
      } else { \
         ttrail_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%.6f actual=%.6f tol=%.6f)", ttrail_current, msg, __exp, __act, __tol); \
      } \
   } while(false)

bool TestTrailing_ActivatesAtPlus1R_Only()
{
   ttrail_current = "Trailing_ActivatePlus1R";
   bool long_not_active = Trail_ShouldActivateFromState(true, 1000.0, 1008.0, 10.0);
   TTR_ASSERT_TRUE(!long_not_active, "Long position remains inactive before +1R");

   bool long_active = Trail_ShouldActivateFromState(true, 1000.0, 1010.5, 10.0);
   TTR_ASSERT_TRUE(long_active, "Long position activates at +1R");

   bool short_not_active = Trail_ShouldActivateFromState(false, 1000.0, 995.5, 10.0);
   TTR_ASSERT_TRUE(!short_not_active, "Short position inactive before +1R");

   bool short_active = Trail_ShouldActivateFromState(false, 1000.0, 989.5, 10.0);
   TTR_ASSERT_TRUE(short_active, "Short position activates at +1R");

   return (ttrail_failed == 0);
}

bool TestTrailing_TrailStep_Monotonic_Long()
{
   ttrail_current = "Trailing_StepLong";
   double new_sl = Trail_ComputeNewSLFromState(true,
                                               1020.0,
                                               1005.0,
                                               1008.0,
                                               5.0,
                                               0.8,
                                               0.01,
                                               2);
   TTR_ASSERT_NEAR(1016.00, new_sl, 1e-2, "Long trailing SL moves forward by ATR*TrailMult");

   return (ttrail_failed == 0);
}

bool TestTrailing_TrailStep_Monotonic_Short()
{
   ttrail_current = "Trailing_StepShort";
   double new_sl = Trail_ComputeNewSLFromState(false,
                                               980.0,
                                               995.0,
                                               990.0,
                                               3.0,
                                               1.0,
                                               0.01,
                                               2);
   TTR_ASSERT_NEAR(983.00, new_sl, 1e-2, "Short trailing SL moves lower by ATR*TrailMult");
   TTR_ASSERT_TRUE(new_sl <= 990.0, "Short trailing does not widen beyond last trail");

   return (ttrail_failed == 0);
}

bool TestTrailing_Rounding_Precision()
{
   ttrail_current = "Trailing_Rounding";
   double new_sl = Trail_ComputeNewSLFromState(true,
                                               1234.56789,
                                               1220.12345,
                                               1225.00000,
                                               2.3456,
                                               0.7,
                                               0.001,
                                               3);
   TTR_ASSERT_TRUE(MathAbs(new_sl - NormalizeDouble(new_sl, 3)) < 1e-9, "Trailing SL aligned to digits precision");

   return (ttrail_failed == 0);
}

bool TestTrailing_QueueDuringNews()
{
   ttrail_current = "Trailing_NewsQueue";
   Queue_Test_Reset();
   Queue_Init(5, 5, true);
   Queue_Test_SetRiskOverrides(true, true, true, true, true);
   Queue_Test_SetNewsBlocked(true);
   Queue_Test_RegisterPosition(6101, true, 1010.0, 1000.0, 0.0);

   long queued_id = 0;
   bool queued = Trail_QueueDuringNews("XAUUSD",
                                       6101,
                                       1005.0,
                                       "{\"source\":\"trailing\"}",
                                       queued_id);
   TTR_ASSERT_TRUE(queued, "Trailing enqueues modification during news window");
   TTR_ASSERT_EQUALS(1, Queue_Size(), "Queue contains trailing action");

   Queue_Test_SetNewsBlocked(false);
   Queue_Test_Reset();
   return (ttrail_failed == 0);
}

bool TestTrailing_RunAll()
{
   Print("=================================================================");
   Print("RPEA Trailing Manager Tests - Task 13");
   Print("=================================================================");
   ttrail_passed = 0;
   ttrail_failed = 0;

   bool activate_ok = TestTrailing_ActivatesAtPlus1R_Only();
   bool step_long_ok = TestTrailing_TrailStep_Monotonic_Long();
   bool step_short_ok = TestTrailing_TrailStep_Monotonic_Short();
   bool rounding_ok = TestTrailing_Rounding_Precision();
   bool news_queue_ok = TestTrailing_QueueDuringNews();

   if(!activate_ok || !step_long_ok || !step_short_ok || !rounding_ok || !news_queue_ok)
      Print("Trailing tests reported failures");
   else
      Print("Trailing tests passed");

   return (ttrail_failed == 0);
}

#endif // TEST_TRAILING_MQH
