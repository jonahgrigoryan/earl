#ifndef TEST_BANDIT_MQH
#define TEST_BANDIT_MQH
// test_bandit.mqh - Post-M7 Phase 4 bandit selector and persistence tests

#include <RPEA/bandit.mqh>
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

int TestBandit_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool TestBandit_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s - %s", g_current_test, ok ? "OK" : "FAILED");
   return ok;
}

void TestBandit_PrepareFiles()
{
   Persistence_EnsureFolders();
   FileDelete(FILE_BANDIT_POSTERIOR);
}

void TestBandit_ResetIsolation()
{
   TestBandit_PrepareFiles();
   Bandit_TestResetState();
   Config_Test_ClearBanditStateModeOverride();
   Liquidity_TestResetState();
}

void TestBandit_Cleanup()
{
   Bandit_TestResetState();
   Config_Test_ClearBanditStateModeOverride();
   Liquidity_TestResetState();
   FileDelete(FILE_BANDIT_POSTERIOR);
}

bool TestBandit_PosteriorMissingFileFallback()
{
   int f = TestBandit_Begin("TestBandit_PosteriorMissingFileFallback");

   TestBandit_ResetIsolation();

   ASSERT_FALSE(Bandit_TestLoadPosterior(), "missing posterior file does not load");
   ASSERT_FALSE(Bandit_IsPosteriorReady(), "posterior is not ready without file-backed samples");

   return TestBandit_End(f);
}

bool TestBandit_PosteriorPersistRoundTrip()
{
   int f = TestBandit_Begin("TestBandit_PosteriorPersistRoundTrip");

   TestBandit_ResetIsolation();
   Bandit_TestSetPosterior(4, 3.0, 4, 1.0, 8);
   ASSERT_TRUE(Bandit_TestSavePosterior(), "posterior persists atomically");
   ASSERT_TRUE(FileIsExist(FILE_BANDIT_POSTERIOR), "posterior file created");

   Bandit_TestResetState();
   ASSERT_TRUE(Bandit_TestLoadPosterior(), "posterior reloads from file");
   ASSERT_TRUE(Bandit_TestIsReady(), "posterior is ready after sufficient updates");
   ASSERT_TRUE(Bandit_TestGetTotalUpdates() == 8, "total_updates preserved across reload");

   AppContext ctx;
   ZeroMemory(ctx);
   ctx.symbols_count = 1;
   BanditPolicy policy = Bandit_SelectPolicy(ctx, "EURUSD");
   ASSERT_TRUE(policy == Bandit_BWISC, "higher posterior mean selects BWISC deterministically");

   return TestBandit_End(f);
}

bool TestBandit_RecordTradeOutcome_UpdatesPosterior()
{
   int f = TestBandit_Begin("TestBandit_RecordTradeOutcome_UpdatesPosterior");

   TestBandit_ResetIsolation();
   Config_Test_SetBanditStateModeOverride(true, "live");
   Bandit_TestSetPosterior(0, 0.0, 0, 0.0, 0);

   ASSERT_TRUE(Bandit_RecordTradeOutcome("BWISC", 15.0), "positive close outcome persists BWISC update");
   ASSERT_TRUE(Bandit_TestGetTotalUpdates() == 1, "total_updates increments after trade outcome");

   ASSERT_TRUE(Bandit_RecordTradeOutcome("MR", -4.0), "negative close outcome persists MR update");
   ASSERT_TRUE(Bandit_TestGetTotalUpdates() == 2, "total_updates increments on second outcome");

   return TestBandit_End(f);
}

bool TestBandit_RecordTradeOutcome_FrozenSkipsMutation()
{
   int f = TestBandit_Begin("TestBandit_RecordTradeOutcome_FrozenSkipsMutation");

   TestBandit_ResetIsolation();
   Config_Test_SetBanditStateModeOverride(true, "frozen");
   Bandit_TestSetPosterior(1, 1.0, 1, 0.0, 2);

   ASSERT_FALSE(Bandit_RecordTradeOutcome("BWISC", 15.0), "frozen mode blocks bandit mutation");
   ASSERT_TRUE(Bandit_TestGetTotalUpdates() == 2, "total_updates stay unchanged in frozen mode");

   return TestBandit_End(f);
}

bool TestBandit_SelectPolicy_DisabledStateSkips()
{
   int f = TestBandit_Begin("TestBandit_SelectPolicy_DisabledStateSkips");

   TestBandit_ResetIsolation();
   Config_Test_SetBanditStateModeOverride(true, "disabled");
   Bandit_TestSetPosterior(8, 7.0, 8, 6.0, 16);

   AppContext ctx;
   ZeroMemory(ctx);
   ctx.symbols_count = 1;

   BanditPolicy policy = Bandit_SelectPolicy(ctx, "EURUSD");
   ASSERT_TRUE(policy == Bandit_Skip, "disabled mode suppresses bandit selection");

   return TestBandit_End(f);
}

bool TestBandit_SelectPolicy_HardLiquidityBlock()
{
   int f = TestBandit_Begin("TestBandit_SelectPolicy_HardLiquidityBlock");

   TestBandit_ResetIsolation();
   Bandit_TestSetPosterior(8, 7.0, 8, 6.0, 16);

   for(int i = 1; i <= 100; i++)
      Liquidity_UpdateStats("EURUSD", (double)i, (double)i);

   AppContext ctx;
   ZeroMemory(ctx);
   ctx.symbols_count = 1;

   BanditPolicy policy = Bandit_SelectPolicy(ctx, "EURUSD");
   ASSERT_TRUE(policy == Bandit_Skip, "bandit returns Skip when liquidity quantiles breach hard threshold");

   return TestBandit_End(f);
}

bool TestBandit_RunAll()
{
   Print("=================================================================");
   Print("Post-M7 Task14/15 - Bandit Tests");
   Print("=================================================================");

   bool ok1 = TestBandit_PosteriorMissingFileFallback();
   bool ok2 = TestBandit_PosteriorPersistRoundTrip();
   bool ok3 = TestBandit_RecordTradeOutcome_UpdatesPosterior();
   bool ok4 = TestBandit_RecordTradeOutcome_FrozenSkipsMutation();
   bool ok5 = TestBandit_SelectPolicy_DisabledStateSkips();
   bool ok6 = TestBandit_SelectPolicy_HardLiquidityBlock();
   TestBandit_Cleanup();

   return (ok1 && ok2 && ok3 && ok4 && ok5 && ok6);
}

#endif // TEST_BANDIT_MQH
