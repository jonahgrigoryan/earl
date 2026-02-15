#ifndef TEST_LEARNING_MQH
#define TEST_LEARNING_MQH
// test_learning.mqh - Post-M7 Phase 4 learning calibration tests

#include <RPEA/learning.mqh>
#include <RPEA/persistence.mqh>

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

int TestLearning_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool TestLearning_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s - %s", g_current_test, ok ? "OK" : "FAILED");
   return ok;
}

void TestLearning_PrepareFiles()
{
   Persistence_EnsureFolders();
   FileDelete(FILE_CALIBRATION);
}

void TestLearning_Cleanup()
{
   Learning_TestResetState();
   Telemetry_TestReset();
   SLO_TestResetState();
   FileDelete(FILE_CALIBRATION);
}

bool TestLearning_WriteCalibrationFixture(const string &lines[])
{
   int h = FileOpen(FILE_CALIBRATION, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;

   int count = ArraySize(lines);
   for(int i = 0; i < count; i++)
      FileWrite(h, lines[i]);

   FileClose(h);
   return true;
}

bool TestLearning_Load_MissingFileFallback()
{
   int f = TestLearning_Begin("TestLearning_Load_MissingFileFallback");

   TestLearning_PrepareFiles();
   Learning_TestResetState();
   Learning_LoadCalibration();

   ASSERT_FALSE(Learning_TestLoadedFromFile(), "missing file falls back to defaults");
   ASSERT_TRUE(MathAbs(Learning_TestGetBWISCBias() - 0.5) < 1e-9, "default BWISC bias is neutral");
   ASSERT_TRUE(MathAbs(Learning_TestGetMRBias() - 0.5) < 1e-9, "default MR bias is neutral");
   ASSERT_TRUE(Learning_TestGetSampleCount() == 0, "default sample_count is zero");

   return TestLearning_End(f);
}

bool TestLearning_Load_MalformedFileFallback()
{
   int f = TestLearning_Begin("TestLearning_Load_MalformedFileFallback");

   TestLearning_PrepareFiles();
   string lines[];
   ArrayResize(lines, 3);
   lines[0] = "schema_version=99";
   lines[1] = "bwisc_bias=0.8";
   lines[2] = "mr_bias=0.2";
   ASSERT_TRUE(TestLearning_WriteCalibrationFixture(lines), "malformed fixture written");

   Learning_TestResetState();
   Learning_LoadCalibration();

   ASSERT_FALSE(Learning_TestLoadedFromFile(), "schema mismatch falls back to defaults");
   ASSERT_TRUE(MathAbs(Learning_TestGetBWISCBias() - 0.5) < 1e-9, "fallback BWISC bias is neutral");
   ASSERT_TRUE(MathAbs(Learning_TestGetMRBias() - 0.5) < 1e-9, "fallback MR bias is neutral");

   return TestLearning_End(f);
}

bool TestLearning_Load_ValidFile()
{
   int f = TestLearning_Begin("TestLearning_Load_ValidFile");

   TestLearning_PrepareFiles();
   string lines[];
   ArrayResize(lines, 5);
   lines[0] = "schema_version=1";
   lines[1] = "bwisc_bias=0.7";
   lines[2] = "mr_bias=0.3";
   lines[3] = "sample_count=12";
   lines[4] = "updated_at=1704067200";
   ASSERT_TRUE(TestLearning_WriteCalibrationFixture(lines), "valid fixture written");

   Learning_TestResetState();
   Learning_LoadCalibration();

   ASSERT_TRUE(Learning_TestLoadedFromFile(), "valid calibration file is loaded");
   ASSERT_TRUE(MathAbs(Learning_TestGetBWISCBias() - 0.7) < 1e-9, "BWISC bias loaded from file");
   ASSERT_TRUE(MathAbs(Learning_TestGetMRBias() - 0.3) < 1e-9, "MR bias loaded from file");
   ASSERT_TRUE(Learning_TestGetSampleCount() == 12, "sample_count loaded from file");

   return TestLearning_End(f);
}

bool TestLearning_Update_PersistsCalibration()
{
   int f = TestLearning_Begin("TestLearning_Update_PersistsCalibration");

   TestLearning_PrepareFiles();
   string lines[];
   ArrayResize(lines, 4);
   lines[0] = "schema_version=1";
   lines[1] = "bwisc_bias=0.5";
   lines[2] = "mr_bias=0.5";
   lines[3] = "sample_count=0";
   ASSERT_TRUE(TestLearning_WriteCalibrationFixture(lines), "seed calibration file written");

   Learning_TestResetState();
   Learning_LoadCalibration();
   Telemetry_TestReset();
   Telemetry_TestSetMinSamples(1);
   SLO_TestResetState();

   Telemetry_TestRecordOutcome("BWISC", 2.0);
   Telemetry_TestRecordOutcome("MR", -1.0);

   int writes_before = Learning_TestGetPersistWriteCount();
   Learning_Update();

   ASSERT_FALSE(Learning_TestLastUpdateFrozen(), "update runs when SLO throttle is inactive");
   ASSERT_TRUE(Learning_TestLastUpdatePersisted(), "update persists calibration atomically");
   ASSERT_TRUE(Learning_TestGetPersistWriteCount() == writes_before + 1, "persist write counter increments");
   ASSERT_TRUE(FileIsExist(FILE_CALIBRATION), "calibration file exists after update");

   Learning_TestResetState();
   Learning_LoadCalibration();
   ASSERT_TRUE(Learning_TestLoadedFromFile(), "updated calibration reloads from file");
   ASSERT_TRUE(Learning_TestGetSampleCount() == 2, "sample_count reflects telemetry samples");
   ASSERT_TRUE(Learning_TestGetBWISCBias() > Learning_TestGetMRBias(), "bias tilts toward higher-efficiency strategy");

   return TestLearning_End(f);
}

bool TestLearning_Update_FreezeOnSLOBreach()
{
   int f = TestLearning_Begin("TestLearning_Update_FreezeOnSLOBreach");

   TestLearning_PrepareFiles();
   string lines[];
   ArrayResize(lines, 4);
   lines[0] = "schema_version=1";
   lines[1] = "bwisc_bias=0.6";
   lines[2] = "mr_bias=0.4";
   lines[3] = "sample_count=8";
   ASSERT_TRUE(TestLearning_WriteCalibrationFixture(lines), "seed calibration file written");

   Learning_TestResetState();
   Learning_LoadCalibration();
   Telemetry_TestReset();
   Telemetry_TestSetMinSamples(1);
   Telemetry_TestRecordOutcome("BWISC", 1.0);
   Telemetry_TestRecordOutcome("MR", 1.0);

   SLO_TestResetState();
   g_slo_metrics.slo_breached = true;

   int writes_before = Learning_TestGetPersistWriteCount();
   Learning_Update();

   ASSERT_TRUE(Learning_TestLastUpdateFrozen(), "SLO breach freezes learning update");
   ASSERT_FALSE(Learning_TestLastUpdatePersisted(), "frozen update does not write calibration");
   ASSERT_TRUE(Learning_TestGetPersistWriteCount() == writes_before, "persist write counter unchanged on freeze");

   return TestLearning_End(f);
}

bool TestLearning_RunAll()
{
   Print("=================================================================");
   Print("Post-M7 Task12/13 - Learning Tests");
   Print("=================================================================");

   bool ok1 = TestLearning_Load_MissingFileFallback();
   bool ok2 = TestLearning_Load_MalformedFileFallback();
   bool ok3 = TestLearning_Load_ValidFile();
   bool ok4 = TestLearning_Update_PersistsCalibration();
   bool ok5 = TestLearning_Update_FreezeOnSLOBreach();
   TestLearning_Cleanup();

   return (ok1 && ok2 && ok3 && ok4 && ok5);
}

#endif // TEST_LEARNING_MQH
