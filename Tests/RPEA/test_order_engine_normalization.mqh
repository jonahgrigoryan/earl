#ifndef TEST_ORDER_ENGINE_NORMALIZATION_MQH
#define TEST_ORDER_ENGINE_NORMALIZATION_MQH
// test_order_engine_normalization.mqh - Unit tests for normalization helpers (M3 Task 3)
// References: .kiro/specs/rpea-m3/tasks.md, design.md

#include "../../MQL5/Include/RPEA/order_engine.mqh"

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

#define ASSERT_FALSE(condition, message) \
   ASSERT_TRUE(!(condition), message)

#define ASSERT_EQUALS(expected, actual, message) \
   do { \
      if((expected) == (actual)) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%d, actual=%d)", g_current_test, message, (int)(expected), (int)(actual)); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%d, actual=%d)", g_current_test, message, (int)(expected), (int)(actual)); \
      } \
   } while(false)

#define ASSERT_NEAR(expected, actual, tolerance, message) \
   do { \
      double __exp = (expected); \
      double __act = (actual); \
      double __tol = (tolerance); \
      if(MathAbs(__exp - __act) <= __tol) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%.10f, actual=%.10f, tol=%.10f)", g_current_test, message, __exp, __act, __tol); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%.10f, actual=%.10f, tol=%.10f)", g_current_test, message, __exp, __act, __tol); \
      } \
   } while(false)

#endif // TEST_FRAMEWORK_DEFINED

//------------------------------------------------------------------------------
// Test helpers
//------------------------------------------------------------------------------

void OE_NormalizationTests_Reset()
{
   OE_Test_ClearOverrides();
}

//------------------------------------------------------------------------------
// Test cases
//------------------------------------------------------------------------------

bool NormalizeVolume_RoundsStep()
{
   g_current_test = "NormalizeVolume_RoundsStep";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   const string symbol = "TEST.VOL.ROUND";
   const double step = 0.05;
   const double min_vol = 0.10;
   const double max_vol = 10.0;
   OE_Test_SetVolumeOverride(symbol, step, min_vol, max_vol);

   const double raw_volume = 1.123;
   const double expected = MathRound(raw_volume / step) * step;
   const double normalized = OE_NormalizeVolume(symbol, raw_volume);

   ASSERT_NEAR(expected, normalized, 1e-8, "Volume rounds to configured step");
   ASSERT_TRUE(normalized >= min_vol && normalized <= max_vol, "Normalized volume within configured bounds");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool NormalizeVolume_ClampRange()
{
   g_current_test = "NormalizeVolume_ClampRange";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   const string symbol = "TEST.VOL.CLAMP";
   const double step = 0.10;
   const double min_vol = 0.30;
   const double max_vol = 5.0;
   OE_Test_SetVolumeOverride(symbol, step, min_vol, max_vol);

   const double below_min = min_vol - step;
   const double above_max = max_vol + step;

   const double normalized_below = OE_NormalizeVolume(symbol, below_min);
   const double normalized_above = OE_NormalizeVolume(symbol, above_max);

   ASSERT_NEAR(min_vol, normalized_below, 1e-8, "Volume below minimum clamps to minimum");
   ASSERT_NEAR(max_vol, normalized_above, 1e-8, "Volume above maximum clamps to maximum");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool NormalizePrice_RoundsPoint()
{
   g_current_test = "NormalizePrice_RoundsPoint";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   const string symbol = "TEST.PRICE.ROUND";
   const double point = 0.01;
   const int digits = 2;
   const double bid = 100.00;
   const double ask = 100.05;
   const int stops_level = 0;
   OE_Test_SetPriceOverride(symbol, point, digits, bid, ask, stops_level);

   const double raw_price = 100.123;
   const double expected = NormalizeDouble(MathRound(raw_price / point) * point, digits);
   const double normalized = OE_NormalizePrice(symbol, raw_price);

   ASSERT_NEAR(expected, normalized, 1e-8, "Price snaps to point grid");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool NormalizePrice_StopsLevel()
{
   g_current_test = "NormalizePrice_StopsLevel";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   const string symbol = "TEST.PRICE.STOPS";
   const double point = 0.01;
   const int digits = 2;
   const double bid = 100.00;
   const double ask = 100.05;
   const int stops_level_points = 3; // 3 * point = 0.03 distance
   OE_Test_SetPriceOverride(symbol, point, digits, bid, ask, stops_level_points);

   const double inside_bid = bid - 0.01; // 1 point inside stops zone
   const double normalized_inside_bid = OE_NormalizePrice(symbol, inside_bid);
   const double expected_bid_guard = NormalizeDouble(bid - point * stops_level_points, digits);

   const double inside_ask = ask + 0.01;
   const double normalized_inside_ask = OE_NormalizePrice(symbol, inside_ask);
   const double expected_ask_guard = NormalizeDouble(ask + point * stops_level_points, digits);

   ASSERT_NEAR(expected_bid_guard, normalized_inside_bid, 1e-8, "Price below bid adjusted to respect stops distance");
   ASSERT_NEAR(expected_ask_guard, normalized_inside_ask, 1e-8, "Price above ask adjusted to respect stops distance");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool ValidateVolumeRange_InvalidThrows()
{
   g_current_test = "ValidateVolumeRange_InvalidThrows";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   const string symbol = "TEST.VOL.VALIDATE";
   const double step = 0.10;
   const double min_vol = 0.50;
   const double max_vol = 3.00;
   OE_Test_SetVolumeOverride(symbol, step, min_vol, max_vol);

   ASSERT_TRUE(OE_IsVolumeWithinRange(symbol, 1.00), "Volume within range returns true");
   ASSERT_FALSE(OE_IsVolumeWithinRange(symbol, min_vol - 0.20), "Volume below minimum flagged as invalid");
   ASSERT_FALSE(OE_IsVolumeWithinRange(symbol, max_vol + 0.30), "Volume above maximum flagged as invalid");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

//------------------------------------------------------------------------------
// Test runner
//------------------------------------------------------------------------------

bool TestOrderEngineNormalization_RunAll()
{
   PrintFormat("=================================================================");
   PrintFormat("RPEA Order Engine Tests - Normalization (Task 3)");
   PrintFormat("=================================================================");

   g_test_passed = 0;
   g_test_failed = 0;

   NormalizeVolume_RoundsStep();
   NormalizeVolume_ClampRange();
   NormalizePrice_RoundsPoint();
   NormalizePrice_StopsLevel();
   ValidateVolumeRange_InvalidThrows();

   PrintFormat("=================================================================");
   PrintFormat("Test Summary: %d passed, %d failed", g_test_passed, g_test_failed);
   if(g_test_failed == 0)
      PrintFormat("ALL NORMALIZATION TESTS PASSED!");
   else
      PrintFormat("NORMALIZATION TESTS FAILED - Review output for details");
   PrintFormat("=================================================================");

   OE_NormalizationTests_Reset();
   return (g_test_failed == 0);
}

#endif // TEST_ORDER_ENGINE_NORMALIZATION_MQH
