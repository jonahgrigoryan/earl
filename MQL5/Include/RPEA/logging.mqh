#pragma once
// logging.mqh - CSV audit/log API (M1)
// References: finalspec.md (Logging)

// Simple append of an audit row; rotate by day filename
void LogAuditRow(const string event, const string component, const int level,
                 const string message, const string fields_json)
{
   MqlDateTime tm; TimeToStruct(TimeCurrent(), tm);
   string ymd = StringFormat("%04d%02d%02d", tm.year, tm.mon, tm.day);
   string path = StringFormat("%s/audit_%s.csv", RPEA_LOGS_DIR, ymd);
   int h = FileOpen(path, FILE_READ|FILE_WRITE|FILE_COMMON|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;
   // one-time header if new file
   if(FileSize(h)==0)
   {
      FileWrite(h, "date,time,event,component,level,message,fields_json");
   }
   FileSeek(h, 0, SEEK_END);
   string date = StringFormat("%04d-%02d-%02d", tm.year, tm.mon, tm.day);
   string time = StringFormat("%02d:%02d:%02d", tm.hour, tm.min, tm.sec);
   string row = date + "," + time + "," + event + "," + component + "," + (string)level + "," + message + "," + fields_json;
   FileWrite(h, row);
   FileClose(h);
}

// Decision log
void LogDecision(const string component, const string message, const string fields_json)
{
   MqlDateTime tm; TimeToStruct(TimeCurrent(), tm);
   string ymd = StringFormat("%04d%02d%02d", tm.year, tm.mon, tm.day);
   string path = StringFormat("%s/decisions_%s.csv", RPEA_LOGS_DIR, ymd);
   int h = FileOpen(path, FILE_READ|FILE_WRITE|FILE_COMMON|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;
   // one-time header if new file
   if(FileSize(h)==0)
   {
      FileWrite(h, "date,time,event,component,level,message,fields_json");
   }
   FileSeek(h, 0, SEEK_END);
   string date = StringFormat("%04d-%02d-%02d", tm.year, tm.mon, tm.day);
   string time = StringFormat("%02d:%02d:%02d", tm.hour, tm.min, tm.sec);
   string row = date + "," + time + ",DECISION," + component + ",1," + message + "," + fields_json;
   FileWrite(h, row);
   FileClose(h);
}

// TODO[M5]: structured CSV headers and rotation
