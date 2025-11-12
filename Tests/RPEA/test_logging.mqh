#ifndef TEST_LOGGING_MQH
#define TEST_LOGGING_MQH
// test_logging.mqh - Unit tests for Task 14 audit logger

#include <RPEA/logging.mqh>

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
#define TEST_FRAMEWORK_DEFINED
#endif

string TestLogging_BuildTodayFilename(const string base_path)
{
   datetime now = TimeCurrent();
   MqlDateTime tm; TimeToStruct(now, tm);
   string date_key = StringFormat("%04d%02d%02d", tm.year, tm.mon, tm.day);
   return StringFormat("%s/audit_%s.csv", base_path, date_key);
}

bool TestLogging_BasicWrite()
{
   int failures_before = g_test_failed;
   g_current_test = "TestLogging_BasicWrite";

   string base_path = "RPEA/logs/test_logging_basic";
   string filename = TestLogging_BuildTodayFilename(base_path);
   FileDelete(filename);

   PrintFormat("[DEBUG] Creating audit logger with base_path: %s", base_path);
   PrintFormat("[DEBUG] Expected filename: %s", filename);

   AuditLogger_Init(base_path, 2, true);

   AuditRecord rec;
   rec.timestamp = TimeCurrent();
   rec.intent_id = "intent_basic";
   rec.action_id = "intent_basic:LOG";
   rec.symbol = "XAUUSD";
   rec.mode = "MARKET";
   rec.requested_price = 1900.0;
   rec.executed_price = 1900.5;
   rec.requested_vol = 0.10;
   rec.filled_vol = 0.10;
   rec.remaining_vol = 0.0;
   ArrayResize(rec.tickets, 1);
   rec.tickets[0] = 1001;
   rec.retry_count = 0;
   rec.gate_pass = true;
   rec.decision = "TEST_DECISION";
   rec.confidence = 0.7;
   rec.efficiency = 0.8;
   rec.rho_est = 0.3;
   rec.est_value = 1.2;
   rec.hold_time = 15.0;
   rec.gating_reason = "test";
   rec.news_window_state = "CLEAR";

   PrintFormat("[DEBUG] Logging audit record with action_id: %s", rec.action_id);
   AuditLogger_Log(rec);
   AuditLogger_Shutdown();

   int handle = FileOpen(filename, FILE_READ|FILE_TXT|FILE_ANSI);
   ASSERT_TRUE(handle != INVALID_HANDLE, "Audit file created on disk");
   string contents = "";
   if(handle != INVALID_HANDLE)
   {
      while(!FileIsEnding(handle))
      {
         string line = FileReadString(handle);
         if(StringLen(line) == 0 && FileIsEnding(handle))
            break;
         contents += line + "\n";
      }
      FileClose(handle);
      PrintFormat("[DEBUG] File contents: '%s'", contents);
   }

   ASSERT_TRUE(StringFind(contents, "timestamp,intent_id,action_id") == 0, "Header present");
   ASSERT_TRUE(StringFind(contents, "intent_basic:LOG") > 0, "Record appended");
   FileDelete(filename);
   return (g_test_failed == failures_before);
}

bool TestLogging_BufferFlush()
{
   int failures_before = g_test_failed;
   g_current_test = "TestLogging_BufferFlush";

   string base_path = "RPEA/logs/test_logging_buffer";
   string filename = TestLogging_BuildTodayFilename(base_path);
   FileDelete(filename);

   AuditLogger_Init(base_path, 1, true);

   AuditRecord rec1;
   rec1.timestamp = TimeCurrent();
   rec1.intent_id = "intent_buffer_1";
   rec1.action_id = "intent_buffer_1:LOG";
   rec1.symbol = "XAUUSD";
   rec1.mode = "MARKET";
   rec1.gate_pass = true;
   rec1.decision = "BUFFER_A";
   rec1.news_window_state = "CLEAR";

   AuditRecord rec2 = rec1;
   rec2.intent_id = "intent_buffer_2";
   rec2.action_id = "intent_buffer_2:LOG";
   rec2.decision = "BUFFER_B";

   AuditLogger_Log(rec1);
   AuditLogger_Log(rec2);
   AuditLogger_Shutdown();

   int handle = FileOpen(filename, FILE_READ|FILE_TXT|FILE_ANSI);
   ASSERT_TRUE(handle != INVALID_HANDLE, "Buffer file created");
   bool has_two_rows = false;
   if(handle != INVALID_HANDLE)
   {
      string contents = "";
      while(!FileIsEnding(handle))
      {
         string line = FileReadString(handle);
         if(StringLen(line) == 0 && FileIsEnding(handle))
            break;
         contents += line + "\n";
      }
      FileClose(handle);
      int first_row = StringFind(contents, "intent_buffer_1:LOG");
      int second_row = StringFind(contents, "intent_buffer_2:LOG");
      has_two_rows = (first_row >= 0 && second_row > first_row);
   }
   ASSERT_TRUE(has_two_rows, "Multiple buffered rows flushed");
   FileDelete(filename);
   return (g_test_failed == failures_before);
}

bool TestLogging_RunAll()
{
   bool ok1 = TestLogging_BasicWrite();
   bool ok2 = TestLogging_BufferFlush();
   return (ok1 && ok2);
}

#endif // TEST_LOGGING_MQH
