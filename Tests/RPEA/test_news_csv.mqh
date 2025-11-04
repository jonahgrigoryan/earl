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

void NewsCsv_SetTimesUtcOffset(const string utc_str, const int offset_minutes)
{
   datetime utc_time = StringToTime(utc_str);
   ASSERT_TRUE(utc_time > 0, "UTC timestamp parsed");
   datetime server_time = utc_time + offset_minutes * 60;
   News_Test_SetCurrentTimes(server_time, utc_time);
}

int NewsCsv_BeginTest(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool NewsCsv_EndTest(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s", g_current_test);
   return ok;
}

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
   Print("=================================================================");
   Print("RPEA News CSV Fallback Tests - Task 10");
   Print("=================================================================");
   const int failures_before = NewsCsv_BeginTest("NewsCsv_LoadsValidFile");

   string lines[];
   ArrayResize(lines, 3);
   lines[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min";
   lines[1] = "2024-01-15T14:30:00Z,XAUUSD,High,ForexFactory,NFP,10,15";
   lines[2] = "2024-01-15T16:00:00Z,EURUSD,Medium,NewsWire,PMI,5,5";

   string fixture_path = "";
   ASSERT_TRUE(NewsCsv_WriteFixture("news_valid.csv", lines, ArraySize(lines), fixture_path), "Fixture created");
   News_Test_SetOverridePath(fixture_path);
   News_Test_SetOverrideMaxAgeHours(24);

   NewsCsv_SetTimesUtcOffset("2024.01.15 14:29", 0);
   ASSERT_TRUE(News_LoadCsvFallback(), "Reload succeeds for valid CSV");

   ASSERT_TRUE(News_IsBlocked("XAUUSD"), "XAUUSD blocked inside window");
   NewsEvent events[];
   ASSERT_TRUE(News_GetEventsForSymbol("XAUUSD", events), "Retrieved events for XAUUSD");
   ASSERT_EQUALS(1, ArraySize(events), "Single event parsed for XAUUSD");
   ASSERT_EQUALS(10, events[0].prebuffer_min, "Prebuffer stored");

   News_Test_ClearOverrides();
   return NewsCsv_EndTest(failures_before);
}

bool NewsCsv_InvalidHeaderRejected()
{
   const int failures_before = NewsCsv_BeginTest("NewsCsv_InvalidHeaderRejected");

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
   return NewsCsv_EndTest(failures_before);
}

bool NewsCsv_StaleFileRejected()
{
   const int failures_before = NewsCsv_BeginTest("NewsCsv_StaleFileRejected");

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
   return NewsCsv_EndTest(failures_before);
}

bool NewsCsv_GlobalBufferDominates()
{
   const int failures_before = NewsCsv_BeginTest("NewsCsv_GlobalBufferDominates");

   string lines[];
   ArrayResize(lines, 2);
   lines[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min";
   lines[1] = "2024-02-01T10:00:00Z,XAUUSD,High,NewsDesk,FOMC,1,1";

   string fixture_path = "";
   ASSERT_TRUE(NewsCsv_WriteFixture("news_global_buffer.csv", lines, ArraySize(lines), fixture_path), "Fixture created");
   News_Test_SetOverridePath(fixture_path);
   News_Test_SetOverrideMaxAgeHours(24);

   NewsCsv_SetTimesUtcOffset("2024.02.01 09:57", 0);
   ASSERT_TRUE(News_LoadCsvFallback(), "Reload succeeds for global buffer test");

   NewsEvent events[];
   ASSERT_TRUE(News_GetEventsForSymbol("XAUUSD", events), "Events retrieved for XAUUSD");
   ASSERT_EQUALS(1, ArraySize(events), "Single event parsed for XAUUSD global buffer");

   int expected_pre_seconds = events[0].prebuffer_min * 60;
   int expected_post_seconds = events[0].postbuffer_min * 60;
#ifdef NewsBufferS
   if(NewsBufferS > expected_pre_seconds)
      expected_pre_seconds = NewsBufferS;
   if(NewsBufferS > expected_post_seconds)
      expected_post_seconds = NewsBufferS;
#endif
   ASSERT_TRUE(events[0].block_start_utc == events[0].timestamp_utc - expected_pre_seconds,
               "Global prebuffer dominates row prebuffer");
   ASSERT_TRUE(events[0].block_end_utc == events[0].timestamp_utc + expected_post_seconds,
               "Global postbuffer dominates row postbuffer");
   ASSERT_TRUE(News_IsBlocked("XAUUSD"), "XAUUSD blocked due to global buffer window");

   News_Test_ClearOverrides();
   return NewsCsv_EndTest(failures_before);
}

bool NewsCsv_MediumImpactDoesNotBlock()
{
   const int failures_before = NewsCsv_BeginTest("NewsCsv_MediumImpactDoesNotBlock");

   string lines[];
   ArrayResize(lines, 2);
   lines[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min";
   lines[1] = "2024-02-05T08:00:00Z,EURUSD,Medium,Desk,ECB Presser,15,15";

   string fixture_path = "";
   ASSERT_TRUE(NewsCsv_WriteFixture("news_medium.csv", lines, ArraySize(lines), fixture_path), "Fixture created");
   News_Test_SetOverridePath(fixture_path);
   News_Test_SetOverrideMaxAgeHours(24);

   NewsCsv_SetTimesUtcOffset("2024.02.05 07:55", 0);
   ASSERT_TRUE(News_LoadCsvFallback(), "Reload succeeds for medium impact test");

   ASSERT_FALSE(News_IsBlocked("EURUSD"), "Medium impact event does not block trading");
   NewsEvent events[];
   ASSERT_TRUE(News_GetEventsForSymbol("EURUSD", events), "Events retrieved for EURUSD medium impact");
   ASSERT_TRUE(events[0].impact == "MEDIUM", "Impact normalized to MEDIUM");

   News_Test_ClearOverrides();
   return NewsCsv_EndTest(failures_before);
}

bool NewsCsv_ForceReloadReparsesFile()
{
   const int failures_before = NewsCsv_BeginTest("NewsCsv_ForceReloadReparsesFile");

   string lines[];
   ArrayResize(lines, 2);
   lines[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min";
   lines[1] = "2024-02-10T12:00:00Z,XAUUSD,High,Wire,Gold Update,5,5";

   string fixture_path = "";
   ASSERT_TRUE(NewsCsv_WriteFixture("news_reload.csv", lines, ArraySize(lines), fixture_path), "Initial fixture created");
   News_Test_SetOverridePath(fixture_path);
   News_Test_SetOverrideMaxAgeHours(24);
   NewsCsv_SetTimesUtcOffset("2024.02.10 11:55", 0);

   News_Test_ResetReadCount();
   ASSERT_TRUE(News_LoadCsvFallback(), "Initial load succeeds");
   ASSERT_EQUALS(1, News_Test_GetReadCount(), "Initial load increments read count");

   ASSERT_TRUE(News_ReloadIfChanged(), "Subsequent reload uses cache");
   ASSERT_EQUALS(1, News_Test_GetReadCount(), "Cache prevents redundant reload");

   News_ForceReload();
   ASSERT_TRUE(News_ReloadIfChanged(), "Force reload succeeds");
   ASSERT_EQUALS(2, News_Test_GetReadCount(), "Force reload triggers fresh parse");

   News_Test_ClearOverrides();
   return NewsCsv_EndTest(failures_before);
}

bool NewsCsv_UtcWindowRespected()
{
   const int failures_before = NewsCsv_BeginTest("NewsCsv_UtcWindowRespected");

   string lines[];
   ArrayResize(lines, 2);
   lines[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min";
   lines[1] = "2024-03-01T15:30:00Z,XAUUSD,High,Bureau,NFP,10,10";

   string fixture_path = "";
   ASSERT_TRUE(NewsCsv_WriteFixture("news_utc.csv", lines, ArraySize(lines), fixture_path), "UTC fixture created");
   News_Test_SetOverridePath(fixture_path);
   News_Test_SetOverrideMaxAgeHours(24);

   datetime utc_inside = StringToTime("2024.03.01 15:26");
   datetime server_inside = utc_inside + 2 * 3600;
   News_Test_SetCurrentTimes(server_inside, utc_inside);
   ASSERT_TRUE(News_LoadCsvFallback(), "Reload succeeds with UTC override");

   ASSERT_TRUE(News_IsBlocked("XAUUSD"), "Blocking respects UTC timestamps");

   NewsEvent events[];
   ASSERT_TRUE(News_GetEventsForSymbol("XAUUSD", events), "Events retrieved for UTC check");
   ASSERT_TRUE(events[0].timestamp_utc == utc_inside + 4 * 60, "Timestamp stored in UTC space");

   datetime utc_outside = StringToTime("2024.03.01 15:50");
   datetime server_outside = utc_outside + 2 * 3600;
   News_Test_SetCurrentTimes(server_outside, utc_outside);
   ASSERT_FALSE(News_IsBlocked("XAUUSD"), "Outside of UTC window resumes trading");

   News_Test_ClearOverrides();
   return NewsCsv_EndTest(failures_before);
}

bool TestNewsCsvFallback_RunAll()
{
   bool ok1 = NewsCsv_LoadsValidFile();
   bool ok2 = NewsCsv_InvalidHeaderRejected();
   bool ok3 = NewsCsv_StaleFileRejected();
   bool ok4 = NewsCsv_GlobalBufferDominates();
   bool ok5 = NewsCsv_MediumImpactDoesNotBlock();
   bool ok6 = NewsCsv_ForceReloadReparsesFile();
   bool ok7 = NewsCsv_UtcWindowRespected();
   return (ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7);
}

#endif // TEST_NEWS_CSV_MQH
