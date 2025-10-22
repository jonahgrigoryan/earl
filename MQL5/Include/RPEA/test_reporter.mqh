#ifndef RPEA_TEST_REPORTER_MQH
#define RPEA_TEST_REPORTER_MQH
// test_reporter.mqh - Unit test result reporting and file output
// Writes test results to JSON for automation and CI/CD integration

#include <RPEA/config.mqh>

//==============================================================================
// Test Result Structures
//==============================================================================

struct TestResult
{
   string   test_name;
   bool     passed;
   string   message;
   datetime timestamp;
   double   execution_time_ms;
};

struct TestSuite
{
   string       suite_name;
   TestResult   results[];
   int          total_tests;
   int          passed_tests;
   int          failed_tests;
   datetime     start_time;
   datetime     end_time;
   double       total_duration_ms;
};

//==============================================================================
// Test Reporter Class
//==============================================================================

class TestReporter
{
private:
   TestSuite    m_suites[];
   int          m_suite_count;
   string       m_output_path;
   bool         m_verbose;

   string EscapeJson(const string text)
   {
      string result = text;
      StringReplace(result, "\\", "\\\\");
      StringReplace(result, "\"", "\\\"");
      StringReplace(result, "\n", "\\n");
      StringReplace(result, "\r", "\\r");
      StringReplace(result, "\t", "\\t");
      return result;
   }

   string FormatTimestamp(const datetime dt)
   {
      MqlDateTime mdt;
      TimeToStruct(dt, mdt);
      return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                         mdt.year, mdt.mon, mdt.day,
                         mdt.hour, mdt.min, mdt.sec);
   }

public:
   TestReporter()
   {
      m_suite_count = 0;
      m_output_path = "RPEA/test_results/test_results.json";
      m_verbose = true;
      ArrayResize(m_suites, 50);
   }

   void SetOutputPath(const string path)
   {
      m_output_path = path;
   }

   void SetVerbose(const bool verbose)
   {
      m_verbose = verbose;
   }

   int BeginSuite(const string suite_name)
   {
      if(m_suite_count >= ArraySize(m_suites))
         ArrayResize(m_suites, m_suite_count + 50);

      int index = m_suite_count++;
      m_suites[index].suite_name = suite_name;
      ArrayResize(m_suites[index].results, 0);
      m_suites[index].total_tests = 0;
      m_suites[index].passed_tests = 0;
      m_suites[index].failed_tests = 0;
      m_suites[index].start_time = TimeCurrent();
      m_suites[index].total_duration_ms = 0.0;

      if(m_verbose)
         PrintFormat("[TEST SUITE START] %s", suite_name);

      return index;
   }

   void EndSuite(const int suite_index)
   {
      if(suite_index < 0 || suite_index >= m_suite_count)
         return;

      m_suites[suite_index].end_time = TimeCurrent();
      m_suites[suite_index].total_duration_ms =
         (double)(m_suites[suite_index].end_time - m_suites[suite_index].start_time) * 1000.0;

      if(m_verbose)
      {
         PrintFormat("[TEST SUITE END] %s: %d/%d passed (%.2f ms)",
                    m_suites[suite_index].suite_name,
                    m_suites[suite_index].passed_tests,
                    m_suites[suite_index].total_tests,
                    m_suites[suite_index].total_duration_ms);
      }
   }

   void RecordTest(const int suite_index,
                   const string test_name,
                   const bool passed,
                   const string message,
                   const double execution_time_ms = 0.0)
   {
      if(suite_index < 0 || suite_index >= m_suite_count)
         return;

      int result_index = m_suites[suite_index].total_tests++;
      ArrayResize(m_suites[suite_index].results, result_index + 1);

      m_suites[suite_index].results[result_index].test_name = test_name;
      m_suites[suite_index].results[result_index].passed = passed;
      m_suites[suite_index].results[result_index].message = message;
      m_suites[suite_index].results[result_index].timestamp = TimeCurrent();
      m_suites[suite_index].results[result_index].execution_time_ms = execution_time_ms;

      if(passed)
         m_suites[suite_index].passed_tests++;
      else
         m_suites[suite_index].failed_tests++;

      if(m_verbose)
      {
         string status = passed ? "PASS" : "FAIL";
         PrintFormat("[%s] %s: %s", status, test_name, message);
      }
   }

   bool WriteResults()
   {
      // Ensure output directory exists
      string dir = "RPEA/test_results";
      FolderCreate(dir);

      // Build JSON output
      string json = "{\n";
      json += "  \"timestamp\": \"" + FormatTimestamp(TimeCurrent()) + "\",\n";
      json += "  \"total_suites\": " + (string)m_suite_count + ",\n";

      int total_tests = 0;
      int total_passed = 0;
      int total_failed = 0;

      for(int i = 0; i < m_suite_count; i++)
      {
         total_tests += m_suites[i].total_tests;
         total_passed += m_suites[i].passed_tests;
         total_failed += m_suites[i].failed_tests;
      }

      json += "  \"total_tests\": " + (string)total_tests + ",\n";
      json += "  \"total_passed\": " + (string)total_passed + ",\n";
      json += "  \"total_failed\": " + (string)total_failed + ",\n";
      json += "  \"success\": " + (total_failed == 0 ? "true" : "false") + ",\n";
      json += "  \"suites\": [\n";

      for(int i = 0; i < m_suite_count; i++)
      {
         json += "    {\n";
         json += "      \"name\": \"" + EscapeJson(m_suites[i].suite_name) + "\",\n";
         json += "      \"total_tests\": " + (string)m_suites[i].total_tests + ",\n";
         json += "      \"passed\": " + (string)m_suites[i].passed_tests + ",\n";
         json += "      \"failed\": " + (string)m_suites[i].failed_tests + ",\n";
         json += "      \"start_time\": \"" + FormatTimestamp(m_suites[i].start_time) + "\",\n";
         json += "      \"end_time\": \"" + FormatTimestamp(m_suites[i].end_time) + "\",\n";
         json += "      \"duration_ms\": " + DoubleToString(m_suites[i].total_duration_ms, 2) + ",\n";
         json += "      \"tests\": [\n";

         for(int j = 0; j < m_suites[i].total_tests; j++)
         {
            json += "        {\n";
            json += "          \"name\": \"" + EscapeJson(m_suites[i].results[j].test_name) + "\",\n";
            json += "          \"passed\": " + (m_suites[i].results[j].passed ? "true" : "false") + ",\n";
            json += "          \"message\": \"" + EscapeJson(m_suites[i].results[j].message) + "\",\n";
            json += "          \"timestamp\": \"" + FormatTimestamp(m_suites[i].results[j].timestamp) + "\",\n";
            json += "          \"execution_time_ms\": " + DoubleToString(m_suites[i].results[j].execution_time_ms, 2) + "\n";
            json += "        }";
            if(j < m_suites[i].total_tests - 1)
               json += ",";
            json += "\n";
         }

         json += "      ]\n";
         json += "    }";
         if(i < m_suite_count - 1)
            json += ",";
         json += "\n";
      }

      json += "  ]\n";
      json += "}\n";

      // Write to file
      int handle = FileOpen(m_output_path, FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(handle == INVALID_HANDLE)
      {
         PrintFormat("[TestReporter] ERROR: Could not open file %s for writing", m_output_path);
         return false;
      }

      FileWrite(handle, json);
      FileClose(handle);

      PrintFormat("[TestReporter] Test results written to: MQL5/Files/%s", m_output_path);
      return true;
   }

   void PrintSummary()
   {
      int total_tests = 0;
      int total_passed = 0;
      int total_failed = 0;

      for(int i = 0; i < m_suite_count; i++)
      {
         total_tests += m_suites[i].total_tests;
         total_passed += m_suites[i].passed_tests;
         total_failed += m_suites[i].failed_tests;
      }

      Print("==========================================");
      Print("TEST SUMMARY");
      Print("==========================================");
      PrintFormat("Total Suites: %d", m_suite_count);
      PrintFormat("Total Tests: %d", total_tests);
      PrintFormat("Passed: %d", total_passed);
      PrintFormat("Failed: %d", total_failed);
      PrintFormat("Success Rate: %.1f%%", total_tests > 0 ? (double)total_passed / (double)total_tests * 100.0 : 0.0);
      Print("==========================================");

      if(total_failed > 0)
      {
         Print("FAILED TESTS:");
         for(int i = 0; i < m_suite_count; i++)
         {
            for(int j = 0; j < m_suites[i].total_tests; j++)
            {
               if(!m_suites[i].results[j].passed)
               {
                  PrintFormat("  - %s.%s: %s",
                            m_suites[i].suite_name,
                            m_suites[i].results[j].test_name,
                            m_suites[i].results[j].message);
               }
            }
         }
         Print("==========================================");
      }
   }

   int GetTotalTests()
   {
      int total = 0;
      for(int i = 0; i < m_suite_count; i++)
         total += m_suites[i].total_tests;
      return total;
   }

   int GetPassedTests()
   {
      int total = 0;
      for(int i = 0; i < m_suite_count; i++)
         total += m_suites[i].passed_tests;
      return total;
   }

   int GetFailedTests()
   {
      int total = 0;
      for(int i = 0; i < m_suite_count; i++)
         total += m_suites[i].failed_tests;
      return total;
   }

   bool AllTestsPassed()
   {
      return GetFailedTests() == 0 && GetTotalTests() > 0;
   }
};

// Global test reporter instance
static TestReporter g_test_reporter;

#endif // RPEA_TEST_REPORTER_MQH
