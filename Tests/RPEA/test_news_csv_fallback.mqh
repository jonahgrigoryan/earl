#ifndef TEST_NEWS_CSV_FALLBACK_MQH
#define TEST_NEWS_CSV_FALLBACK_MQH
// test_news_csv_fallback.mqh - Unit tests for Task 10 (News CSV fallback)
// References: .kiro/specs/rpea-m3/tasks.md §10, requirements.md §10

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

#define ASSERT_FALSE(condition, message) \
   ASSERT_TRUE(!(condition), message)

#define ASSERT_EQUALS_INT(expected, actual, message) \
   do { \
      int __exp = (expected); \
      int __act = (actual); \
      if(__exp == __act) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%d, actual=%d)", g_current_test, message, __exp, __act); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%d, actual=%d)", g_current_test, message, __exp, __act); \
      } \
   } while(false)

#endif // TEST_FRAMEWORK_DEFINED

//------------------------------------------------------------------------------
// Helpers
//------------------------------------------------------------------------------

string NewsTests_IsoFromDatetime(const datetime ts)
{
   MqlDateTime tm; TimeToStruct(ts, tm);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                       tm.year, tm.mon, tm.day, tm.hour, tm.min, tm.sec);
}

bool NewsTests_WriteCsv(const string rows[], const int rows_count)
{
   string path = "RPEA/news/calendar_high_impact.csv";
   int handle = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   for(int i = 0; i < rows_count; ++i)
   {
      FileWriteString(handle, rows[i]);
      FileWriteString(handle, "\n");
   }
   FileFlush(handle);
   FileClose(handle);
   return true;
}

bool NewsTests_SetFileMTime(const datetime ts)
{
   string path = "RPEA/news/calendar_high_impact.csv";
   int handle = FileOpen(path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;
   bool ok = FileSetInteger(handle, FILE_MODIFY_DATE, ts);
   FileClose(handle);
   return ok;
}

void NewsTests_ClearCsv()
{
   FileDelete("RPEA/news/calendar_high_impact.csv");
   News_ForceReload();
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

bool NewsCsv_LoadsValidRows()
{
   g_current_test = "NewsCsv_LoadsValidRows";
   PrintFormat("[TEST START] %s", g_current_test);

   NewsTests_ClearCsv();
   NewsBufferS = 300;

   datetime now_utc = TimeGMT();
   string header = "timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min";
   string lines[4];
   lines[0] = header;
   lines[1] = NewsTests_IsoFromDatetime(now_utc) + ",XAUUSD,HIGH,FF,NFP,1,2";
   lines[2] = NewsTests_IsoFromDatetime(now_utc + 3600) + ",EURUSD,MEDIUM,ECB,Presser,0,0";
   lines[3] = NewsTests_IsoFromDatetime(now_utc + 7200) + ",USDJPY,LOW,DOE,Inventory,-5,10";

   ASSERT_TRUE(NewsTests_WriteCsv(lines, 4), "CSV written to fallback path");
   ASSERT_TRUE(News_LoadCsvFallback(), "CSV load succeeds with valid rows");

   NewsEvent events[];
   ASSERT_TRUE(News_GetEventsForSymbol("XAUUSD", events), "Event list returned for XAUUSD");
   ASSERT_EQUALS_INT(1, ArraySize(events), "Single XAUUSD event parsed");

   datetime expected_start = events[0].timestamp_utc - NewsBufferS;
   datetime expected_end = events[0].timestamp_utc + NewsBufferS;
   ASSERT_TRUE(MathAbs((double)(expected_start - events[0].block_start)) <= 1.0, "Block start honors NewsBufferS");
   ASSERT_TRUE(MathAbs((double)(expected_end - events[0].block_end)) <= 1.0, "Block end honors NewsBufferS");

   ASSERT_TRUE(News_IsBlocked("XAUUSD"), "High-impact event blocks symbol inside buffer");
   ASSERT_FALSE(News_IsBlocked("EURUSD"), "Medium-impact events do not block symbol");

   NewsTests_ClearCsv();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool NewsCsv_SchemaRejectsMissingColumn()
{
   g_current_test = "NewsCsv_SchemaRejectsMissingColumn";
   PrintFormat("[TEST START] %s", g_current_test);

   NewsTests_ClearCsv();

   string rows[2];
   rows[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min"; // missing postbuffer
   rows[1] = "2025-01-01T10:00:00Z,XAUUSD,HIGH,FF,NFP,5";

   ASSERT_TRUE(NewsTests_WriteCsv(rows, 2), "CSV with missing column written");
   ASSERT_FALSE(News_LoadCsvFallback(), "Loader rejects file with invalid schema");
   ASSERT_FALSE(News_IsBlocked("XAUUSD"), "No blocking when schema rejected");

   NewsTests_ClearCsv();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool NewsCsv_RejectsStaleFile()
{
   g_current_test = "NewsCsv_RejectsStaleFile";
   PrintFormat("[TEST START] %s", g_current_test);

   NewsTests_ClearCsv();

   string rows[2];
   rows[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min";
   rows[1] = "2025-01-02T15:00:00Z,XAUUSD,HIGH,FF,NFP,5,5";

   ASSERT_TRUE(NewsTests_WriteCsv(rows, 2), "CSV written for stale test");

   datetime stale_mtime = TimeCurrent() - (DEFAULT_NewsCSVMaxAgeHours + 2) * 3600;
   ASSERT_TRUE(NewsTests_SetFileMTime(stale_mtime), "File mtime adjusted to stale");

   News_ForceReload();
   ASSERT_FALSE(News_LoadCsvFallback(), "Loader rejects stale CSV data");
   ASSERT_FALSE(News_IsBlocked("XAUUSD"), "Blocking disabled when CSV stale");

   NewsTests_ClearCsv();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool NewsCsv_ForceReloadMissingFile()
{
   g_current_test = "NewsCsv_ForceReloadMissingFile";
   PrintFormat("[TEST START] %s", g_current_test);

   NewsTests_ClearCsv();

   string rows[2];
   rows[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min";
   rows[1] = "2025-01-03T10:00:00Z,XAUUSD,HIGH,FF,NFP,5,5";

   ASSERT_TRUE(NewsTests_WriteCsv(rows, 2), "CSV written for reload test");
   ASSERT_TRUE(News_LoadCsvFallback(), "Initial load succeeds");

   ASSERT_TRUE(FileDelete("RPEA/news/calendar_high_impact.csv"), "Fallback CSV deleted");
   News_ForceReload();
   ASSERT_FALSE(News_ReloadIfChanged(), "Reload detects missing file and clears cache");
   NewsEvent events[];
   ASSERT_FALSE(News_GetEventsForSymbol("XAUUSD", events), "Cache empty after missing file");

   NewsTests_ClearCsv();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool TestNewsCsvFallback_RunAll()
{
   int failed_before = g_test_failed;

   bool ok = true;
   ok &= NewsCsv_LoadsValidRows();
   ok &= NewsCsv_SchemaRejectsMissingColumn();
   ok &= NewsCsv_RejectsStaleFile();
   ok &= NewsCsv_ForceReloadMissingFile();

   return ok && (g_test_failed == failed_before);
}

#endif // TEST_NEWS_CSV_FALLBACK_MQH
