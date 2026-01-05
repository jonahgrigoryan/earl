#ifndef RPEA_LOGGING_MQH
#define RPEA_LOGGING_MQH
// logging.mqh - Decision/event logging + Task 14 audit logger
// References: finalspec.md §Logging, .kiro/specs/rpea-m3/tasks.md §14

#include <RPEA/config.mqh>

// -----------------------------------------------------------------------------
// Legacy JSON log helpers (decision + lightweight event streams)
// -----------------------------------------------------------------------------

void LogAuditRow(const string event, const string component, const int level,
                 const string message, const string fields_json)
{
   const datetime now = TimeCurrent();
   MqlDateTime tm; TimeToStruct(now, tm);
   string ymd = StringFormat("%04d%02d%02d", tm.year, tm.mon, tm.day);
   string path = StringFormat("%s/events_%s.csv", RPEA_LOGS_DIR, ymd);
   FolderCreate(RPEA_LOGS_DIR);
   int handle = FileOpen(path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;
   if(FileSize(handle) == 0)
      FileWrite(handle, "date,time,event,component,level,message,fields_json");
   FileSeek(handle, 0, SEEK_END);
   string date = StringFormat("%04d-%02d-%02d", tm.year, tm.mon, tm.day);
   string time = StringFormat("%02d:%02d:%02d", tm.hour, tm.min, tm.sec);
   string row = date + "," + time + "," + event + "," + component + "," + (string)level + "," + message + "," + fields_json;
   FileWrite(handle, row);
   FileClose(handle);
}

void LogDecision(const string component, const string message, const string fields_json)
{
   const datetime now = TimeCurrent();
   MqlDateTime tm; TimeToStruct(now, tm);
   string ymd = StringFormat("%04d%02d%02d", tm.year, tm.mon, tm.day);
   string path = StringFormat("%s/decisions_%s.csv", RPEA_LOGS_DIR, ymd);
   FolderCreate(RPEA_LOGS_DIR);
   int handle = FileOpen(path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;
   if(FileSize(handle) == 0)
      FileWrite(handle, "date,time,event,component,level,message,fields_json");
   FileSeek(handle, 0, SEEK_END);
   string date = StringFormat("%04d-%02d-%02d", tm.year, tm.mon, tm.day);
   string time = StringFormat("%02d:%02d:%02d", tm.hour, tm.min, tm.sec);
   string row = date + "," + time + ",DECISION," + component + ",1," + message + "," + fields_json;
   FileWrite(handle, row);
   FileClose(handle);
}

// -----------------------------------------------------------------------------
// Task 14 Audit Logger
// -----------------------------------------------------------------------------

#define AUDIT_LOGGER_HEADER "timestamp,intent_id,action_id,symbol,mode,requested_price,executed_price,requested_vol,filled_vol,remaining_vol,tickets[],retry_count,gate_open_risk,gate_pending_risk,gate_next_risk,room_today,room_overall,gate_pass,decision,confidence,efficiency,rho_est,est_value,hold_time,gating_reason,news_window_state"

struct AuditRecord
  {
   datetime timestamp;
   string   intent_id;
   string   action_id;
   string   symbol;
   string   mode;
   double   requested_price;
   double   executed_price;
   double   requested_vol;
   double   filled_vol;
   double   remaining_vol;
   ulong    tickets[];
   int      retry_count;
   double   gate_open_risk;
   double   gate_pending_risk;
   double   gate_next_risk;
   double   room_today;
   double   room_overall;
   bool     gate_pass;
   string   decision;
   double   confidence;
   double   efficiency;
   double   rho_est;
   double   est_value;
   double   hold_time;
   string   gating_reason;
   string   news_window_state;
};

struct AuditLoggerState
{
   bool    initialized;
   bool    enabled;
   string  base_path;
   string  current_date_key;
   string  current_filename;
   string  buffer[];
   int     buffer_count;
   int     buffer_capacity;
};

static AuditLoggerState g_audit_logger;

// Forward declarations
void AuditLogger_Init(const string raw_path, const int buffer_size, const bool enabled);
void AuditLogger_Log(const AuditRecord &record);
void AuditLogger_Flush(const bool force);
void AuditLogger_Shutdown();

// -----------------------------------------------------------------------------
// Internal helpers
// -----------------------------------------------------------------------------

string AuditLogger_NormalizePath(const string raw_path)
{
   string path = raw_path;
   if(StringLen(path) == 0)
      path = RPEA_LOGS_DIR;
   // Do not strip "Files/" prefix here; callers pass relative paths like "RPEA/...".
   while(StringLen(path) > 0 && StringGetCharacter(path, StringLen(path) - 1) == '/')
      path = StringSubstr(path, 0, StringLen(path) - 1);
   if(StringLen(path) == 0)
      path = RPEA_LOGS_DIR;
   return path;
}

void AuditLogger_EnsureFolders(const string path)
{
   string parts[];
   int count = StringSplit(path, '/', parts);
   string partial = "";
   for(int i = 0; i < count; i++)
   {
      if(i > 0)
         partial += "/";
      partial += parts[i];
      FolderCreate(partial);
   }
}

string AuditLogger_BuildDateKey(const datetime ts)
{
   datetime time_value = (ts > 0 ? ts : TimeCurrent());
   MqlDateTime tm; TimeToStruct(time_value, tm);
   return StringFormat("%04d%02d%02d", tm.year, tm.mon, tm.day);
}

string AuditLogger_BuildFilename(const string base_path, const string date_key)
  {
     // Task 14 uses dedicated audit_* files; do not reuse legacy events_ files.
     return StringFormat("%s/audit_%s.csv", base_path, date_key);
  }

void AuditLogger_EnsureCurrentFile()
  {
     if(StringLen(g_audit_logger.current_filename) == 0)
        return;
     AuditLogger_EnsureFolders(g_audit_logger.base_path);
     int handle = FileOpen(g_audit_logger.current_filename, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
     if(handle == INVALID_HANDLE)
     {
        handle = FileOpen(g_audit_logger.current_filename, FILE_WRITE|FILE_TXT|FILE_ANSI);
        if(handle == INVALID_HANDLE)
           return;
        // Write header as first line
        FileWrite(handle, AUDIT_LOGGER_HEADER);
        FileClose(handle);
        return;
     }
     if(FileSize(handle) == 0)
     {
        FileWrite(handle, AUDIT_LOGGER_HEADER);
        FileClose(handle);
        return;
     }
     FileClose(handle);
  }

string AuditLogger_FormatTickets(const ulong &tickets[])
{
   string joined = "[";
   for(int i = 0; i < ArraySize(tickets); i++)
   {
      if(i > 0)
         joined += ",";
      joined += IntegerToString((long)tickets[i]);
   }
   joined += "]";
   return joined;
}

string AuditLogger_Sanitize(const string value)
{
   string sanitized = value;
   StringReplace(sanitized, "\"", "'");
   StringReplace(sanitized, "\r", " ");
   StringReplace(sanitized, "\n", " ");
   return sanitized;
}

string AuditLogger_FormatRecord(const AuditRecord &record)
{
   string tickets_json = AuditLogger_FormatTickets(record.tickets);
   string gate_pass_text = (record.gate_pass ? "true" : "false");
   MqlDateTime tm;
   TimeToStruct(record.timestamp, tm);
   string ts = StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                            tm.year, tm.mon, tm.day,
                            tm.hour, tm.min, tm.sec);
   return StringFormat("%s,%s,%s,%s,%s,%.5f,%.5f,%.4f,%.4f,%.4f,\"%s\",%d,%.4f,%.4f,%.4f,%.4f,%.4f,%s,%s,%.4f,%.4f,%.4f,%.4f,%.2f,%s,%s",
                       ts,
                       AuditLogger_Sanitize(record.intent_id),
                       AuditLogger_Sanitize(record.action_id),
                       AuditLogger_Sanitize(record.symbol),
                       AuditLogger_Sanitize(record.mode),
                       record.requested_price,
                       record.executed_price,
                       record.requested_vol,
                       record.filled_vol,
                       record.remaining_vol,
                       tickets_json,
                       record.retry_count,
                       record.gate_open_risk,
                       record.gate_pending_risk,
                       record.gate_next_risk,
                       record.room_today,
                       record.room_overall,
                       gate_pass_text,
                       AuditLogger_Sanitize(record.decision),
                       record.confidence,
                       record.efficiency,
                       record.rho_est,
                       record.est_value,
                       record.hold_time,
                       AuditLogger_Sanitize(record.gating_reason),
                       AuditLogger_Sanitize(record.news_window_state));
}

void AuditLogger_BufferRow(const string row, const datetime timestamp)
{
   const string date_key = AuditLogger_BuildDateKey(timestamp);
   if(!g_audit_logger.initialized || g_audit_logger.current_date_key != date_key)
     {
        g_audit_logger.current_date_key = date_key;
        g_audit_logger.current_filename = AuditLogger_BuildFilename(g_audit_logger.base_path, date_key);
        AuditLogger_EnsureCurrentFile();
        g_audit_logger.initialized = true;
     }

   if(g_audit_logger.buffer_capacity <= 0)
   {
      g_audit_logger.buffer_capacity = MathMax(1, DEFAULT_LogBufferSize);
      ArrayResize(g_audit_logger.buffer, g_audit_logger.buffer_capacity);
   }

   if(g_audit_logger.buffer_count >= g_audit_logger.buffer_capacity)
      AuditLogger_Flush(false);

   g_audit_logger.buffer[g_audit_logger.buffer_count++] = row;
}

void AuditLogger_WriteBufferToDisk()
  {
     if(g_audit_logger.buffer_count <= 0)
        return;
     AuditLogger_EnsureCurrentFile();
     int handle = FileOpen(g_audit_logger.current_filename, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
     if(handle == INVALID_HANDLE)
        return;
     FileSeek(handle, 0, SEEK_END);
     for(int i = 0; i < g_audit_logger.buffer_count; i++)
     {
        FileWrite(handle, g_audit_logger.buffer[i]);
     }
     FileClose(handle);
     g_audit_logger.buffer_count = 0;
  }

// -----------------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------------

void AuditLogger_Init(const string raw_path, const int buffer_size, const bool enabled)
{
   g_audit_logger.enabled = enabled;
   g_audit_logger.base_path = AuditLogger_NormalizePath(raw_path);
   g_audit_logger.buffer_capacity = MathMax(1, buffer_size);
   ArrayResize(g_audit_logger.buffer, g_audit_logger.buffer_capacity);
   g_audit_logger.buffer_count = 0;
   g_audit_logger.current_date_key = "";
   g_audit_logger.current_filename = "";
   g_audit_logger.initialized = false;
   if(enabled)
   {
      AuditLogger_EnsureFolders(g_audit_logger.base_path);
      // For Task 14 test harness base paths, ensure a clean audit file for today.
      if(StringFind(g_audit_logger.base_path, "RPEA/logs/test_logging_") == 0)
      {
         string today_key = AuditLogger_BuildDateKey(TimeCurrent());
         string today_file = AuditLogger_BuildFilename(g_audit_logger.base_path, today_key);
         FileDelete(today_file);
      }
   }
}

void AuditLogger_Log(const AuditRecord &record)
{
   if(!g_audit_logger.enabled)
      return;

   AuditRecord copy = record;
   if(copy.timestamp <= 0)
      copy.timestamp = TimeCurrent();
   const string row = AuditLogger_FormatRecord(copy);
   AuditLogger_BufferRow(row, copy.timestamp);
}

void AuditLogger_Flush(const bool force)
{
   if(!g_audit_logger.enabled)
      return;
   if(force || g_audit_logger.buffer_count >= g_audit_logger.buffer_capacity)
      AuditLogger_WriteBufferToDisk();
}

void AuditLogger_Shutdown()
{
   AuditLogger_Flush(true);
   g_audit_logger.enabled = false;
}

#endif // RPEA_LOGGING_MQH
