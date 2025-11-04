#ifndef TEST_NEWS_CSV_MQH
#define TEST_NEWS_CSV_MQH
// test_news_csv.mqh - Unit tests for Task 10 News CSV fallback loader

#include <RPEA/news.mqh>

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
#endif // TEST_FRAMEWORK_DEFINED

bool NewsCsv_WriteFixture(const string filename, const string &lines[], const int line_count, string &out_path)
{
   FolderCreate(RPEA_DIR);
   const string fixture_dir = RPEA_DIR"/test_fixtures";
   FolderCreate(fixture_dir);
   string path = fixture_dir + "/" + filename;
   int handle = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;
   for(int i = 0; i < line_count; i++)
      FileWrite(handle, lines[i]);
   FileClose(handle);
   out_path = path;
   return true;
}

bool NewsCsv_LoadsValidFile()
{
   g_current_test = "NewsCsv_LoadsValidFile";
   Print("=================================================================");
   Print("RPEA News CSV Fallback Tests - Task 10");
   Print("=================================================================");
   PrintFormat("[TEST START] %s", g_current_test);

   string lines[];
   ArrayResize(lines, 3);
   lines[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min";
   lines[1] = "2024-01-15T14:30:00Z,XAUUSD,High,ForexFactory,NFP,10,15";
   lines[2] = "2024-01-15T16:00:00Z,EURUSD,Medium,NewsWire,PMI,5,5";

   string fixture_path = "";
   ASSERT_TRUE(NewsCsv_WriteFixture("news_valid.csv", lines, ArraySize(lines), fixture_path), "Fixture created");
   News_Test_SetOverridePath(fixture_path);
   News_Test_SetOverrideMaxAgeHours(24);

   datetime server_now = TimeCurrent();
   datetime utc_now = StringToTime("2024.01.15 14:29");
   News_Test_SetCurrentTimes(server_now, utc_now);
   ASSERT_TRUE(News_LoadCsvFallback(), "Reload succeeds for valid CSV");

   ASSERT_TRUE(News_IsBlocked("XAUUSD"), "XAUUSD blocked inside window");
   NewsEvent events[];
   ASSERT_TRUE(News_GetEventsForSymbol("XAUUSD", events), "Retrieved events for XAUUSD");
   ASSERT_EQUALS(1, ArraySize(events), "Single event parsed for XAUUSD");
   ASSERT_EQUALS(10, events[0].prebuffer_min, "Prebuffer stored");

   News_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool NewsCsv_InvalidHeaderRejected()
{
   g_current_test = "NewsCsv_InvalidHeaderRejected";
   PrintFormat("[TEST START] %s", g_current_test);

   string lines[];
   ArrayResize(lines, 2);
   lines[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min";
   lines[1] = "2024-01-15T14:30:00Z,XAUUSD,High,ForexFactory,NFP,10";

   string fixture_path = "";
   ASSERT_TRUE(NewsCsv_WriteFixture("news_invalid_header.csv", lines, ArraySize(lines), fixture_path), "Fixture created");
   News_Test_SetOverridePath(fixture_path);
   News_Test_SetOverrideMaxAgeHours(24);

   ASSERT_FALSE(News_LoadCsvFallback(), "Reload fails when header missing columns");
   ASSERT_FALSE(News_IsBlocked("XAUUSD"), "Blocking disabled when CSV invalid");

   News_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool NewsCsv_StaleFileRejected()
{
   g_current_test = "NewsCsv_StaleFileRejected";
   PrintFormat("[TEST START] %s", g_current_test);

   string lines[];
   ArrayResize(lines, 2);
   lines[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min";
   lines[1] = "2024-01-15T14:30:00Z,XAUUSD,High,ForexFactory,NFP,10,10";

   string fixture_path = "";
   ASSERT_TRUE(NewsCsv_WriteFixture("news_stale.csv", lines, ArraySize(lines), fixture_path), "Fixture created");
   News_Test_SetOverridePath(fixture_path);
   News_Test_SetOverrideMaxAgeHours(1);

   datetime file_mtime = 0;
   News_GetFileMTime(fixture_path, file_mtime);
   datetime stale_now = file_mtime + 3 * 3600;
   News_Test_SetCurrentTimes(stale_now, stale_now);

   ASSERT_FALSE(News_LoadCsvFallback(), "Reload fails when CSV stale");
   ASSERT_FALSE(News_IsBlocked("XAUUSD"), "No blocking when CSV rejected for staleness");

   News_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool TestNewsCsvFallback_RunAll()
{
   bool ok1 = NewsCsv_LoadsValidFile();
   bool ok2 = NewsCsv_InvalidHeaderRejected();
   bool ok3 = NewsCsv_StaleFileRejected();
   return (ok1 && ok2 && ok3);
}

#endif // TEST_NEWS_CSV_MQH
