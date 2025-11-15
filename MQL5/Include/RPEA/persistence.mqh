#ifndef RPEA_PERSISTENCE_MQH
#define RPEA_PERSISTENCE_MQH
// persistence.mqh - Persistence & folder creation (M1 stubs)
// References: finalspec.md (Persistence/Logs & Learning Artifacts)

#include <RPEA/config.mqh>
#include <RPEA/state.mqh>

#ifndef RPEA_PERSISTENCE_LOG_VERBOSE
#define RPEA_PERSISTENCE_LOG_VERBOSE 0
#endif

//==============================================================================
// Intent Journal Data Structures
//==============================================================================

struct OrderIntent
{
   string           intent_id;
   string           accept_once_key;
   datetime         timestamp;
   string           symbol;
   string           signal_symbol;
   ENUM_ORDER_TYPE  order_type;
   double           volume;
   double           price;
   double           sl;
   double           tp;
   datetime         expiry;
   string           status;
   string           execution_mode;
   bool             is_proxy;
   double           proxy_rate;
   string           proxy_context;
   string           oco_sibling_id;
   int              retry_count;
   string           reasoning;
   string           error_messages[];
   ulong            executed_tickets[];
   double           partial_fills[];
   double           confidence;
   double           efficiency;
   double           rho_est;
   double           est_value;
   double           expected_hold_minutes;
   double           gate_open_risk;
   double           gate_pending_risk;
   double           gate_next_risk;
   double           room_today;
   double           room_overall;
   bool             gate_pass;
   string           gating_reason;
   string           news_window_state;
   string           decision_context;
   ulong            tickets_snapshot[];
   double           last_executed_price;
   double           last_filled_volume;
   double           hold_time_seconds;
};

struct PersistedQueuedAction
{
   string   action_id;
   string   accept_once_key;
   ulong    ticket;
   string   action_type;
   double   new_value;
   double   validation_threshold;
   datetime queued_time;
   datetime expires_time;
   string   trigger_condition;
   string   intent_id;
   string   intent_key;
   double   queued_confidence;
   double   queued_efficiency;
   double   rho_est;
   double   est_value;
   double   gate_open_risk;
   double   gate_pending_risk;
   double   gate_next_risk;
   double   room_today;
   double   room_overall;
   bool     gate_pass;
   string   gating_reason;
   string   news_window_state;
};

struct IntentJournal
{
   OrderIntent            intents[];
   PersistedQueuedAction  queued_actions[];
};

//==============================================================================
// Journal Helpers (forward declarations)
//==============================================================================

void IntentJournal_Clear(IntentJournal &journal);
bool IntentJournal_Load(IntentJournal &journal);
bool IntentJournal_Save(const IntentJournal &journal);
int  IntentJournal_FindIntentById(const IntentJournal &journal, const string intent_id);
int  IntentJournal_FindIntentByAcceptKey(const IntentJournal &journal, const string accept_key);
int  IntentJournal_FindActionById(const IntentJournal &journal, const string action_id);
int  IntentJournal_FindActionByAcceptKey(const IntentJournal &journal, const string accept_key);
bool IntentJournal_RemoveIntentById(IntentJournal &journal, const string intent_id);
bool IntentJournal_RemoveActionById(IntentJournal &journal, const string action_id);
void IntentJournal_TouchSequences(const IntentJournal &journal, int &out_intent_seq, int &out_action_seq);

string Persistence_FormatIso8601(const datetime value);
datetime Persistence_ParseIso8601(const string value);
string Persistence_JoinJsonObjects(const string &objects[]);
string Persistence_JoinJsonArray(const double &values[]);
string Persistence_JoinJsonULongArray(const ulong &values[]);
string Persistence_JoinJsonStringArray(const string &values[]);
bool Persistence_SplitJsonArrayObjects(const string json, string &objects[]);
string Persistence_EscapeJson(const string value);
string Persistence_UnescapeJson(const string value);
string Persistence_Trim(const string value);
string Persistence_RemoveOuterBrackets(const string source);
bool  Persistence_OrderIntentToJson(const OrderIntent &intent, string &out_json);
bool  Persistence_ActionToJson(const PersistedQueuedAction &action, string &out_json);
bool  Persistence_OrderIntentFromJson(const string json, OrderIntent &out_intent);
bool  Persistence_ActionFromJson(const string json, PersistedQueuedAction &out_action);
string Persistence_ExtractJsonArray(const string json, const string key);
string Persistence_ReadWholeFile(const string path);
bool   Persistence_WriteWholeFile(const string path, const string contents);
bool   Persistence_EnsureIntentFileExists();

// Ensure all parent folders exist under MQL5/Files/RPEA/**
void Persistence_EnsureFolders()
{
   FolderCreate(RPEA_DIR);
   FolderCreate(RPEA_STATE_DIR);
   FolderCreate(RPEA_LOGS_DIR);
   FolderCreate(RPEA_REPORTS_DIR);
   FolderCreate(RPEA_NEWS_DIR);
   FolderCreate(RPEA_EMRT_DIR);
   FolderCreate(RPEA_QTABLE_DIR);
   FolderCreate(RPEA_BANDIT_DIR);
   FolderCreate(RPEA_LIQUIDITY_DIR);
   FolderCreate(RPEA_CALIBRATION_DIR);
   FolderCreate(RPEA_SETS_DIR);
   FolderCreate(RPEA_TESTER_DIR);
}

// Ensure placeholder files exist (tolerate if already present)
void Persistence_EnsurePlaceholderFiles()
{
   // State files
   int h;
    h = FileOpen(FILE_INTENTS, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
    if(h!=INVALID_HANDLE)
    {
       if(FileSize(h)==0)
          FileWrite(h, "{\"intents\":[],\"queued_actions\":[]}");
       FileClose(h);
    }

   h = FileOpen(FILE_QUEUE_ACTIONS, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
   {
      if(FileSize(h)==0)
         FileWrite(h, "id,ticket,action_type,symbol,created_at,expires_at,priority,new_sl,new_tp,context,retry_count,intent_id,intent_key");
      FileClose(h);
   }
   // News CSV fallback
   h = FileOpen(FILE_NEWS_FALLBACK, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
   {
      if(FileSize(h)==0) FileWrite(h, "timestamp,impact,countries,symbols");
      FileClose(h);
   }
   // SL enforcement state
   h = FileOpen(FILE_SL_ENFORCEMENT, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
   {
      if(FileSize(h)==0)
         FileWrite(h, "[]");
      FileClose(h);
   }
   // EMRT, Q-table, bandit, liquidity, calibration
   string files_to_touch[] = {
      FILE_EMRT_CACHE, FILE_EMRT_BETA_GRID, FILE_QTABLE_BIN,
      FILE_BANDIT_POSTERIOR, FILE_LIQUIDITY_STATS, FILE_CALIBRATION,
      FILE_AUDIT_REPORT
   };
   for(int i=0;i<ArraySize(files_to_touch);i++)
   {
      h = FileOpen(files_to_touch[i], FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h!=INVALID_HANDLE)
      {
         if(FileSize(h)==0)
         {
            if(files_to_touch[i]==FILE_AUDIT_REPORT)
               FileWrite(h, "date,time,event,component,level,message,fields_json");
            else
               FileWrite(h, "{}");
         }
         FileClose(h);
      }
   }
   // Sets and tester artifacts
   h = FileOpen(FILE_SET_DEFAULT, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
   {
      if(FileSize(h)==0)
      {
         // Syntactically valid .set exposing all inputs
         FileWrite(h, "DailyLossCapPct=4.0");
         FileWrite(h, "OverallLossCapPct=6.0");
         FileWrite(h, "MinTradeDaysRequired=3");
         FileWrite(h, "TradingEnabledDefault=true");
         FileWrite(h, "MinRiskDollar=10.0");
         FileWrite(h, "OneAndDoneR=1.5");
         FileWrite(h, "NYGatePctOfDailyCap=0.50");
         FileWrite(h, "UseLondonOnly=false");
         FileWrite(h, "StartHourLO=7");
         FileWrite(h, "StartHourNY=12");
         FileWrite(h, "ORMinutes=60");
         FileWrite(h, "CutoffHour=16");
         FileWrite(h, "RiskPct=1.5");
         FileWrite(h, "MicroRiskPct=0.10");
         FileWrite(h, "MicroTimeStopMin=45");
         FileWrite(h, "GivebackCapDayPct=0.50");
         FileWrite(h, "NewsBufferS=300");
         FileWrite(h, "MaxSpreadPoints=40");
         FileWrite(h, "MaxSlippagePoints=10");
         FileWrite(h, "MinHoldSeconds=120");
         FileWrite(h, "QueueTTLMinutes=5");
         FileWrite(h, "UseServerMidnightBaseline=true");
         FileWrite(h, "ServerToCEST_OffsetMinutes=0");
         FileWrite(h, "InpSymbols=EURUSD;XAUUSD");
         FileWrite(h, "UseXAUEURProxy=true");
         FileWrite(h, "LeverageOverrideFX=50");
         FileWrite(h, "LeverageOverrideMetals=20");
         FileWrite(h, "RtargetBC=2.2");
         FileWrite(h, "RtargetMSC=2.0");
         FileWrite(h, "SLmult=1.0");
         FileWrite(h, "TrailMult=0.8");
         FileWrite(h, "EntryBufferPoints=3");
         FileWrite(h, "MinStopPoints=1");
         FileWrite(h, "MagicBase=990200");
         FileWrite(h, "MaxOpenPositionsTotal=2");
         FileWrite(h, "MaxOpenPerSymbol=1");
         FileWrite(h, "MaxPendingsPerSymbol=2");
         FileWrite(h, "BWISC_ConfCut=0.70");
         FileWrite(h, "MR_ConfCut=0.80");
         FileWrite(h, "EMRT_FastThresholdPct=40");
         FileWrite(h, "CorrelationFallbackRho=0.50");
         FileWrite(h, "MR_RiskPct_Default=0.90");
         FileWrite(h, "MR_TimeStopMin=60");
         FileWrite(h, "MR_TimeStopMax=90");
         FileWrite(h, "MR_LongOnly=false");
         FileWrite(h, "EMRT_ExtremeThresholdMult=2.0");
         FileWrite(h, "EMRT_VarCapMult=2.5");
         FileWrite(h, "EMRT_BetaGridMin=-2.0");
         FileWrite(h, "EMRT_BetaGridMax=2.0");
         FileWrite(h, "QL_LearningRate=0.10");
         FileWrite(h, "QL_DiscountFactor=0.99");
         FileWrite(h, "QL_EpsilonTrain=0.10");
         FileWrite(h, "QL_TrainingEpisodes=10000");
         FileWrite(h, "QL_SimulationPaths=1000");
      }
      FileClose(h);
   }
   h = FileOpen(FILE_OPT_RANGES, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
   {
      if(FileSize(h)==0)
      {
         FileWrite(h, "RiskPct: 0.8..2.0 step 0.1");
         FileWrite(h, "SLmult: 0.7..1.3 step 0.1");
         FileWrite(h, "RtargetBC: 1.8..2.6 step 0.1");
         FileWrite(h, "RtargetMSC: 1.6..2.4 step 0.1");
         FileWrite(h, "ORMinutes: {30,45,60,75}");
         FileWrite(h, "TrailMult: 0.6..1.2 step 0.1");
      }
      FileClose(h);
   }
   h = FileOpen(FILE_TESTER_INI, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
   {
      if(FileSize(h)==0)
      {
         FileWrite(h, "[Tester]");
         FileWrite(h, "Deposit=10000");
         FileWrite(h, "Currency=USD");
         FileWrite(h, "Leverage=50");
         FileWrite(h, "Model=4 ; Every tick based on real ticks");
         FileWrite(h, "ExecutionMode=0");
      }
      FileClose(h);
   }
}

//==============================================================================
// Intent Journal Helpers
//==============================================================================

string Persistence_Trim(const string value)
{
   int start = 0;
   int finish = StringLen(value);
   while(start < finish)
   {
      const ushort ch = StringGetCharacter(value, start);
      if(ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t')
         start++;
      else
         break;
   }
   while(finish > start)
   {
      const ushort ch = StringGetCharacter(value, finish - 1);
      if(ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t')
         finish--;
      else
         break;
   }
   if(finish <= start)
      return "";
   return StringSubstr(value, start, finish - start);
}

string Persistence_RemoveOuterBrackets(const string source)
{
   string trimmed = Persistence_Trim(source);
   if(StringLen(trimmed) >= 2)
   {
      if(StringGetCharacter(trimmed, 0) == '[' && StringGetCharacter(trimmed, StringLen(trimmed) - 1) == ']')
      {
         return StringSubstr(trimmed, 1, StringLen(trimmed) - 2);
      }
   }
   return trimmed;
}

string Persistence_EscapeJson(const string value)
{
   string escaped = "";
   int len = StringLen(value);
   for(int i = 0; i < len; ++i)
   {
      ushort ch = StringGetCharacter(value, i);
      switch(ch)
      {
         case '\\': escaped += "\\\\"; break;
         case '"':  escaped += "\\\""; break;
         case '\r': escaped += "\\r";  break;
         case '\n': escaped += "\\n";  break;
         case '\t': escaped += "\\t";  break;
         default:
            escaped += CharToString(ch);
            break;
      }
   }
   return escaped;
}

string Persistence_UnescapeJson(const string value)
{
   string result;
   result = "";
   int len = StringLen(value);
   for(int i = 0; i < len; ++i)
   {
      ushort ch = StringGetCharacter(value, i);
      if(ch == '\\' && (i + 1) < len)
      {
         ushort next = StringGetCharacter(value, i + 1);
         switch(next)
         {
            case '\\': result += "\\"; break;
            case '"': result += "\""; break;
            case 'r': result += "\r"; break;
            case 'n': result += "\n"; break;
            case 't': result += "\t"; break;
            default: result += CharToString(next); break;
         }
         i++;
      }
      else
      {
         result += CharToString(ch);
      }
   }
   return result;
}

string Persistence_FormatIso8601(const datetime value)
{
   if(value <= 0)
      return "";
   MqlDateTime dt;
   TimeToStruct(value, dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                       dt.year, dt.mon, dt.day,
                       dt.hour, dt.min, dt.sec);
}

datetime Persistence_ParseIso8601(const string value)
{
   if(value == "" || value == "null")
      return (datetime)0;
   string normalized = value;
   normalized = StringReplace(normalized, "T", " ");
   normalized = StringReplace(normalized, "Z", "");
   normalized = StringReplace(normalized, "-", ".");
   return StringToTime(normalized);
}

string Persistence_JoinJsonStringArray(const string &values[])
{
   string joined = "[";
   for(int i = 0; i < ArraySize(values); ++i)
   {
      if(i > 0)
         joined += ",";
      joined += "\"" + Persistence_EscapeJson(values[i]) + "\"";
   }
   joined += "]";
   return joined;
}

string Persistence_JoinJsonULongArray(const ulong &values[])
{
   string joined = "[";
   for(int i = 0; i < ArraySize(values); ++i)
   {
      if(i > 0)
         joined += ",";
      joined += (string)values[i];
   }
   joined += "]";
   return joined;
}

string Persistence_JoinJsonArray(const double &values[])
{
   string joined = "[";
   for(int i = 0; i < ArraySize(values); ++i)
   {
      if(i > 0)
         joined += ",";
      joined += DoubleToString(values[i], 8);
   }
   joined += "]";
   return joined;
}

bool Persistence_SplitJsonArrayObjects(const string json, string &objects[])
{
   string trimmed = Persistence_RemoveOuterBrackets(json);
   ArrayResize(objects, 0);
   if(trimmed == "")
      return true;

   int len = StringLen(trimmed);
   int depth = 0;
   bool in_string = false;
   bool escape = false;
   string current = "";
   for(int i = 0; i < len; ++i)
   {
      ushort ch = StringGetCharacter(trimmed, i);
      if(in_string)
      {
         current += CharToString(ch);
         if(escape)
         {
            escape = false;
         }
         else if(ch == '\\')
         {
            escape = true;
         }
         else if(ch == '"')
         {
            in_string = false;
         }
         continue;
      }

      if(ch == '"')
      {
         in_string = true;
         current += "\"";
         continue;
      }

      if(ch == '{')
      {
         depth++;
         current += "{";
         continue;
      }

      if(ch == '}')
      {
         depth--;
         current += "}";
         if(depth == 0)
         {
            int idx = ArraySize(objects);
            ArrayResize(objects, idx + 1);
            objects[idx] = Persistence_Trim(current);
            current = "";
         }
         continue;
      }

      if(ch == ',' && depth == 0)
      {
         continue;
      }

      current += CharToString(ch);
   }

   return true;
}

string Persistence_ReadWholeFile(const string path)
{
   int handle = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return "";
   string contents = "";
   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      if(contents != "")
         contents += "\n";
      contents += line;
   }
   FileClose(handle);
   return contents;
}

bool Persistence_WriteWholeFile(const string path, const string contents)
{
   int handle = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;
   FileWrite(handle, contents);
   FileClose(handle);
   return true;
}

string Persistence_ExtractJsonArray(const string json, const string key)
{
   string pattern = "\"" + key + "\":[";
   int start = StringFind(json, pattern);
   if(start < 0)
      return "";
   start += StringLen(pattern);
   int len = StringLen(json);
   int depth = 1;
   bool in_string = false;
   bool escape = false;
   for(int i = start; i < len; ++i)
   {
      ushort ch = StringGetCharacter(json, i);
      if(in_string)
      {
         if(escape)
         {
            escape = false;
         }
         else if(ch == '\\')
         {
            escape = true;
         }
         else if(ch == '"')
         {
            in_string = false;
         }
         continue;
      }

      if(ch == '"')
      {
         in_string = true;
         continue;
      }

      if(ch == '[')
      {
         depth++;
         continue;
      }

      if(ch == ']')
      {
         depth--;
         if(depth == 0)
         {
            return StringSubstr(json, start, i - start);
         }
         continue;
      }
   }

   return "";
}

bool Persistence_ParseStringField(const string json, const string key, string &out_value)
{
   string pattern = "\"" + key + "\":";
   int start = StringFind(json, pattern);
   if(start < 0)
      return false;
   start += StringLen(pattern);
   int len = StringLen(json);
   // Skip whitespace
   while(start < len)
   {
      ushort ch = StringGetCharacter(json, start);
      if(ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n')
         start++;
      else
         break;
   }

   if(start >= len)
      return false;

   ushort ch = StringGetCharacter(json, start);
   if(ch != '"')
   {
      // Allow null as empty string
      if(StringSubstr(json, start, 4) == "null")
      {
         out_value = "";
         return true;
      }

      string buffer = "";
      for(int i = start; i < len; ++i)
      {
         ch = StringGetCharacter(json, i);
         if(ch == ',' || ch == '}' || ch == ']')
         {
            out_value = Persistence_Trim(buffer);
            return (StringLen(out_value) > 0);
         }
         buffer += CharToString(ch);
      }
      out_value = Persistence_Trim(buffer);
      return (StringLen(out_value) > 0);
   }

   // Parse quoted string
   start++;
   string buffer = "";
   bool escape = false;
   for(int i = start; i < len; ++i)
   {
      ch = StringGetCharacter(json, i);
      if(escape)
      {
         buffer += CharToString(ch);
         escape = false;
         continue;
      }
      if(ch == '\\')
      {
         escape = true;
         continue;
      }
      if(ch == '"')
      {
         out_value = Persistence_UnescapeJson(buffer);
         return true;
      }
      buffer += CharToString(ch);
   }
   PrintFormat("DEBUG ParseStringField failed: key='%s' snippet='%s'", key,
               StringSubstr(json, MathMax(0, start - 10), 80));
   return false;
}

bool Persistence_ParseNumberField(const string json, const string key, double &out_value)
{
   string pattern = "\"" + key + "\":";
   int start = StringFind(json, pattern);
   if(start < 0)
      return false;
   start += StringLen(pattern);
   int len = StringLen(json);
   string buffer = "";
   for(int i = start; i < len; ++i)
   {
      ushort ch = StringGetCharacter(json, i);
      if(ch == ',' || ch == '}' || ch == ']')
         break;
      if(ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n')
         continue;
      buffer += CharToString(ch);
   }
   buffer = Persistence_Trim(buffer);
   if(buffer == "" || buffer == "null")
      return false;
   out_value = StringToDouble(buffer);
   return true;
}

bool Persistence_ParseIntegerField(const string json, const string key, long &out_value)
{
   double parsed = 0.0;
   if(!Persistence_ParseNumberField(json, key, parsed))
      return false;
   out_value = (long)parsed;
   return true;
}

bool Persistence_ParseULongField(const string json, const string key, ulong &out_value)
{
   long parsed = 0;
   if(!Persistence_ParseIntegerField(json, key, parsed))
      return false;
   if(parsed < 0)
      parsed = 0;
   out_value = (ulong)parsed;
   return true;
}

bool Persistence_ParseIntField(const string json, const string key, int &out_value)
{
   long parsed = 0;
   if(!Persistence_ParseIntegerField(json, key, parsed))
      return false;
   out_value = (int)parsed;
   return true;
}

bool Persistence_ParseArrayOfStrings(const string json, const string key, string &out_values[])
{
   string pattern = "\"" + key + "\":[";
   int start = StringFind(json, pattern);
   ArrayResize(out_values, 0);
   if(start < 0)
      return false;
   start += StringLen(pattern);
   int len = StringLen(json);
   bool in_string = false;
   bool escape = false;
   string current = "";
   for(int i = start; i < len; ++i)
   {
      ushort ch = StringGetCharacter(json, i);
      if(in_string)
      {
         if(escape)
         {
            current += CharToString(ch);
            escape = false;
         }
         else if(ch == '\\')
         {
            escape = true;
         }
         else if(ch == '"')
         {
            int idx = ArraySize(out_values);
            ArrayResize(out_values, idx + 1);
            out_values[idx] = Persistence_UnescapeJson(current);
            current = "";
            in_string = false;
         }
         else
         {
            current += CharToString(ch);
         }
         continue;
      }

      if(ch == '"')
      {
         in_string = true;
         continue;
      }

      if(ch == ']')
         break;
   }
   return true;
}

bool Persistence_ParseArrayOfULong(const string json, const string key, ulong &out_values[])
{
   string pattern = "\"" + key + "\":[";
   int start = StringFind(json, pattern);
   ArrayResize(out_values, 0);
   if(start < 0)
      return false;
   start += StringLen(pattern);
   int len = StringLen(json);
   string current = "";
   for(int i = start; i < len; ++i)
   {
      ushort ch = StringGetCharacter(json, i);
      if(ch == ',' || ch == ']')
      {
         current = Persistence_Trim(current);
         if(current != "")
         {
            int idx = ArraySize(out_values);
            ArrayResize(out_values, idx + 1);
            out_values[idx] = (ulong)StringToInteger(current);
            current = "";
         }
         if(ch == ']')
            break;
         continue;
      }
      current += CharToString(ch);
   }
   return true;
}

bool Persistence_ParseArrayOfDouble(const string json, const string key, double &out_values[])
{
   string pattern = "\"" + key + "\":[";
   int start = StringFind(json, pattern);
   ArrayResize(out_values, 0);
   if(start < 0)
      return false;
   start += StringLen(pattern);
   int len = StringLen(json);
   string current = "";
   for(int i = start; i < len; ++i)
   {
      ushort ch = StringGetCharacter(json, i);
      if(ch == ',' || ch == ']')
      {
         current = Persistence_Trim(current);
         if(current != "")
         {
            int idx = ArraySize(out_values);
            ArrayResize(out_values, idx + 1);
            out_values[idx] = StringToDouble(current);
            current = "";
         }
         if(ch == ']')
            break;
         continue;
      }
      current += CharToString(ch);
   }
   return true;
}

bool Persistence_OrderIntentToJson(const OrderIntent &intent, string &out_json)
{
   string error_messages_json = Persistence_JoinJsonStringArray(intent.error_messages);
   string tickets_json = Persistence_JoinJsonULongArray(intent.executed_tickets);
   string partials_json = Persistence_JoinJsonArray(intent.partial_fills);
   string ticket_snap_json = Persistence_JoinJsonULongArray(intent.tickets_snapshot);

   out_json = "{";
   out_json += "\"intent_id\":\"" + Persistence_EscapeJson(intent.intent_id) + "\",";
   out_json += "\"accept_once_key\":\"" + Persistence_EscapeJson(intent.accept_once_key) + "\",";
   out_json += "\"timestamp\":\"" + Persistence_EscapeJson(Persistence_FormatIso8601(intent.timestamp)) + "\",";
   out_json += "\"symbol\":\"" + Persistence_EscapeJson(intent.symbol) + "\",";
   out_json += "\"signal_symbol\":\"" + Persistence_EscapeJson(intent.signal_symbol) + "\",";
   out_json += "\"order_type\":\"" + Persistence_EscapeJson(EnumToString(intent.order_type)) + "\",";
   out_json += "\"volume\":" + DoubleToString(intent.volume, 4) + ",";
   out_json += "\"price\":" + DoubleToString(intent.price, 5) + ",";
   out_json += "\"sl\":" + DoubleToString(intent.sl, 5) + ",";
   out_json += "\"tp\":" + DoubleToString(intent.tp, 5) + ",";
   out_json += "\"expiry\":\"" + Persistence_EscapeJson(Persistence_FormatIso8601(intent.expiry)) + "\",";
   out_json += "\"status\":\"" + Persistence_EscapeJson(intent.status) + "\",";
   out_json += "\"execution_mode\":\"" + Persistence_EscapeJson(intent.execution_mode) + "\",";
   out_json += "\"is_proxy\":" + (intent.is_proxy ? "true" : "false") + ",";
   out_json += "\"proxy_rate\":" + DoubleToString(intent.proxy_rate, 5) + ",";
   out_json += "\"proxy_context\":\"" + Persistence_EscapeJson(intent.proxy_context) + "\",";
   out_json += "\"oco_sibling_id\":\"" + Persistence_EscapeJson(intent.oco_sibling_id) + "\",";
   out_json += "\"retry_count\":" + (string)intent.retry_count + ",";
   out_json += "\"reasoning\":\"" + Persistence_EscapeJson(intent.reasoning) + "\",";
   out_json += "\"error_messages\":" + error_messages_json + ",";
   out_json += "\"executed_tickets\":" + tickets_json + ",";
   out_json += "\"partial_fills\":" + partials_json + ",";
   out_json += "\"confidence\":" + DoubleToString(intent.confidence, 4) + ",";
   out_json += "\"efficiency\":" + DoubleToString(intent.efficiency, 4) + ",";
   out_json += "\"rho_est\":" + DoubleToString(intent.rho_est, 4) + ",";
   out_json += "\"est_value\":" + DoubleToString(intent.est_value, 4) + ",";
   out_json += "\"expected_hold_minutes\":" + DoubleToString(intent.expected_hold_minutes, 2) + ",";
   out_json += "\"gate_open_risk\":" + DoubleToString(intent.gate_open_risk, 4) + ",";
   out_json += "\"gate_pending_risk\":" + DoubleToString(intent.gate_pending_risk, 4) + ",";
   out_json += "\"gate_next_risk\":" + DoubleToString(intent.gate_next_risk, 4) + ",";
   out_json += "\"room_today\":" + DoubleToString(intent.room_today, 4) + ",";
   out_json += "\"room_overall\":" + DoubleToString(intent.room_overall, 4) + ",";
   out_json += "\"gate_pass\":" + (intent.gate_pass ? "true" : "false") + ",";
   out_json += "\"gating_reason\":\"" + Persistence_EscapeJson(intent.gating_reason) + "\",";
   out_json += "\"news_window_state\":\"" + Persistence_EscapeJson(intent.news_window_state) + "\",";
   out_json += "\"decision_context\":\"" + Persistence_EscapeJson(intent.decision_context) + "\",";
   out_json += "\"tickets_snapshot\":" + ticket_snap_json + ",";
   out_json += "\"last_executed_price\":" + DoubleToString(intent.last_executed_price, 5) + ",";
   out_json += "\"last_filled_volume\":" + DoubleToString(intent.last_filled_volume, 4) + ",";
   out_json += "\"hold_time_seconds\":" + DoubleToString(intent.hold_time_seconds, 2);
   out_json += "}";
   return true;
}

ENUM_ORDER_TYPE Persistence_ParseOrderType(const string value)
{
   if(value == "ORDER_TYPE_BUY" || value == "BUY")
      return ORDER_TYPE_BUY;
   if(value == "ORDER_TYPE_SELL" || value == "SELL")
      return ORDER_TYPE_SELL;
   if(value == "ORDER_TYPE_BUY_LIMIT" || value == "BUY_LIMIT")
      return ORDER_TYPE_BUY_LIMIT;
   if(value == "ORDER_TYPE_SELL_LIMIT" || value == "SELL_LIMIT")
      return ORDER_TYPE_SELL_LIMIT;
   if(value == "ORDER_TYPE_BUY_STOP" || value == "BUY_STOP")
      return ORDER_TYPE_BUY_STOP;
   if(value == "ORDER_TYPE_SELL_STOP" || value == "SELL_STOP")
      return ORDER_TYPE_SELL_STOP;
   if(value == "ORDER_TYPE_BUY_STOP_LIMIT" || value == "BUY_STOP_LIMIT")
      return ORDER_TYPE_BUY_STOP_LIMIT;
   if(value == "ORDER_TYPE_SELL_STOP_LIMIT" || value == "SELL_STOP_LIMIT")
      return ORDER_TYPE_SELL_STOP_LIMIT;
   return ORDER_TYPE_BUY;
}

bool Persistence_OrderIntentFromJson(const string json, OrderIntent &out_intent)
{
   // Verbose raw intent logging removed to reduce noise

   ArrayResize(out_intent.error_messages, 0);
   ArrayResize(out_intent.executed_tickets, 0);
   ArrayResize(out_intent.partial_fills, 0);

   string value;
   if(Persistence_ParseStringField(json, "intent_id", value))
      out_intent.intent_id = value;
   else
      PrintFormat("[Persistence] Load intent missing intent_id in %s", json);
   if(Persistence_ParseStringField(json, "accept_once_key", value))
      out_intent.accept_once_key = value;
   else
      PrintFormat("[Persistence] Load intent missing accept_once_key in %s", json);
   if(Persistence_ParseStringField(json, "timestamp", value))
      out_intent.timestamp = Persistence_ParseIso8601(value);
   if(Persistence_ParseStringField(json, "symbol", value))
      out_intent.symbol = value;
   if(Persistence_ParseStringField(json, "signal_symbol", value))
      out_intent.signal_symbol = value;
   else
      PrintFormat("[Persistence] Load intent missing symbol in %s", json);
   if(Persistence_ParseStringField(json, "order_type", value))
      out_intent.order_type = Persistence_ParseOrderType(value);
   double dbl_value = 0.0;
   if(Persistence_ParseNumberField(json, "volume", dbl_value))
      out_intent.volume = dbl_value;
   if(Persistence_ParseNumberField(json, "price", dbl_value))
      out_intent.price = dbl_value;
   if(Persistence_ParseNumberField(json, "sl", dbl_value))
      out_intent.sl = dbl_value;
   if(Persistence_ParseNumberField(json, "tp", dbl_value))
      out_intent.tp = dbl_value;
   if(Persistence_ParseStringField(json, "expiry", value))
      out_intent.expiry = Persistence_ParseIso8601(value);
   if(Persistence_ParseStringField(json, "status", value))
      out_intent.status = value;
   else
      PrintFormat("[Persistence] Load intent missing status in %s", json);
   if(Persistence_ParseStringField(json, "execution_mode", value))
      out_intent.execution_mode = value;
   if(Persistence_ParseStringField(json, "is_proxy", value))
      out_intent.is_proxy = (StringToLower(value) == "true");
   if(Persistence_ParseNumberField(json, "proxy_rate", dbl_value))
      out_intent.proxy_rate = dbl_value;
   if(Persistence_ParseStringField(json, "proxy_context", value))
      out_intent.proxy_context = value;
   else
      PrintFormat("[Persistence] Load intent missing execution_mode in %s", json);
   if(Persistence_ParseStringField(json, "oco_sibling_id", value))
      out_intent.oco_sibling_id = value;
   int int_value = 0;
   if(Persistence_ParseIntField(json, "retry_count", int_value))
      out_intent.retry_count = int_value;
   if(Persistence_ParseStringField(json, "reasoning", value))
      out_intent.reasoning = value;

   Persistence_ParseArrayOfStrings(json, "error_messages", out_intent.error_messages);
   Persistence_ParseArrayOfULong(json, "executed_tickets", out_intent.executed_tickets);
   Persistence_ParseArrayOfDouble(json, "partial_fills", out_intent.partial_fills);

   out_intent.confidence = 0.0;
   if(Persistence_ParseNumberField(json, "confidence", dbl_value))
      out_intent.confidence = dbl_value;
   out_intent.efficiency = 0.0;
   if(Persistence_ParseNumberField(json, "efficiency", dbl_value))
      out_intent.efficiency = dbl_value;
   out_intent.rho_est = 0.0;
   if(Persistence_ParseNumberField(json, "rho_est", dbl_value))
      out_intent.rho_est = dbl_value;
   out_intent.est_value = 0.0;
   if(Persistence_ParseNumberField(json, "est_value", dbl_value))
      out_intent.est_value = dbl_value;
   out_intent.expected_hold_minutes = 0.0;
   if(Persistence_ParseNumberField(json, "expected_hold_minutes", dbl_value))
      out_intent.expected_hold_minutes = dbl_value;
   out_intent.gate_open_risk = 0.0;
   if(Persistence_ParseNumberField(json, "gate_open_risk", dbl_value))
      out_intent.gate_open_risk = dbl_value;
   out_intent.gate_pending_risk = 0.0;
   if(Persistence_ParseNumberField(json, "gate_pending_risk", dbl_value))
      out_intent.gate_pending_risk = dbl_value;
   out_intent.gate_next_risk = 0.0;
   if(Persistence_ParseNumberField(json, "gate_next_risk", dbl_value))
      out_intent.gate_next_risk = dbl_value;
   out_intent.room_today = 0.0;
   if(Persistence_ParseNumberField(json, "room_today", dbl_value))
      out_intent.room_today = dbl_value;
   out_intent.room_overall = 0.0;
   if(Persistence_ParseNumberField(json, "room_overall", dbl_value))
      out_intent.room_overall = dbl_value;
   out_intent.gate_pass = false;
   if(Persistence_ParseStringField(json, "gate_pass", value))
      out_intent.gate_pass = (StringCompare(value, "true") == 0 || value == "1");
   if(Persistence_ParseStringField(json, "gating_reason", value))
      out_intent.gating_reason = value;
   if(Persistence_ParseStringField(json, "news_window_state", value))
      out_intent.news_window_state = value;
   if(Persistence_ParseStringField(json, "decision_context", value))
      out_intent.decision_context = value;
   Persistence_ParseArrayOfULong(json, "tickets_snapshot", out_intent.tickets_snapshot);
   out_intent.last_executed_price = 0.0;
   if(Persistence_ParseNumberField(json, "last_executed_price", dbl_value))
      out_intent.last_executed_price = dbl_value;
   out_intent.last_filled_volume = 0.0;
   if(Persistence_ParseNumberField(json, "last_filled_volume", dbl_value))
      out_intent.last_filled_volume = dbl_value;
   out_intent.hold_time_seconds = 0.0;
   if(Persistence_ParseNumberField(json, "hold_time_seconds", dbl_value))
      out_intent.hold_time_seconds = dbl_value;

   if(StringLen(out_intent.signal_symbol) == 0)
      out_intent.signal_symbol = out_intent.symbol;
   if(!out_intent.is_proxy && out_intent.signal_symbol != out_intent.symbol)
      out_intent.is_proxy = true;
   if(out_intent.proxy_rate <= 0.0)
      out_intent.proxy_rate = 1.0;
   if(StringLen(out_intent.execution_mode) == 0)
      out_intent.execution_mode = "DIRECT";

   return true;
}

bool Persistence_ActionToJson(const PersistedQueuedAction &action, string &out_json)
{
   out_json = "{";
   out_json += "\"action_id\":\"" + Persistence_EscapeJson(action.action_id) + "\",";
   out_json += "\"accept_once_key\":\"" + Persistence_EscapeJson(action.accept_once_key) + "\",";
   out_json += "\"ticket\":" + (string)action.ticket + ",";
   out_json += "\"action_type\":\"" + Persistence_EscapeJson(action.action_type) + "\",";
   out_json += "\"new_value\":" + DoubleToString(action.new_value, 8) + ",";
   out_json += "\"validation_threshold\":" + DoubleToString(action.validation_threshold, 4) + ",";
   out_json += "\"queued_time\":\"" + Persistence_EscapeJson(Persistence_FormatIso8601(action.queued_time)) + "\",";
   out_json += "\"expires_time\":\"" + Persistence_EscapeJson(Persistence_FormatIso8601(action.expires_time)) + "\",";
   out_json += "\"trigger_condition\":\"" + Persistence_EscapeJson(action.trigger_condition) + "\",";
   out_json += "\"intent_id\":\"" + Persistence_EscapeJson(action.intent_id) + "\",";
   out_json += "\"intent_key\":\"" + Persistence_EscapeJson(action.intent_key) + "\",";
   out_json += "\"queued_confidence\":" + DoubleToString(action.queued_confidence, 4) + ",";
   out_json += "\"queued_efficiency\":" + DoubleToString(action.queued_efficiency, 4) + ",";
   out_json += "\"rho_est\":" + DoubleToString(action.rho_est, 4) + ",";
   out_json += "\"est_value\":" + DoubleToString(action.est_value, 4) + ",";
   out_json += "\"gate_open_risk\":" + DoubleToString(action.gate_open_risk, 4) + ",";
   out_json += "\"gate_pending_risk\":" + DoubleToString(action.gate_pending_risk, 4) + ",";
   out_json += "\"gate_next_risk\":" + DoubleToString(action.gate_next_risk, 4) + ",";
   out_json += "\"room_today\":" + DoubleToString(action.room_today, 4) + ",";
   out_json += "\"room_overall\":" + DoubleToString(action.room_overall, 4) + ",";
   out_json += "\"gate_pass\":" + (action.gate_pass ? "true" : "false") + ",";
   out_json += "\"gating_reason\":\"" + Persistence_EscapeJson(action.gating_reason) + "\",";
   out_json += "\"news_window_state\":\"" + Persistence_EscapeJson(action.news_window_state) + "\"";
   out_json += "}";
   return true;
}

bool Persistence_ActionFromJson(const string json, PersistedQueuedAction &out_action)
{
   string str_value;
   if(Persistence_ParseStringField(json, "action_id", str_value))
      out_action.action_id = str_value;
   if(Persistence_ParseStringField(json, "accept_once_key", str_value))
      out_action.accept_once_key = str_value;
   ulong ul_value = 0;
   if(Persistence_ParseULongField(json, "ticket", ul_value))
      out_action.ticket = ul_value;
   if(Persistence_ParseStringField(json, "action_type", str_value))
      out_action.action_type = str_value;
   double dbl_value = 0.0;
   if(Persistence_ParseNumberField(json, "new_value", dbl_value))
      out_action.new_value = dbl_value;
   if(Persistence_ParseNumberField(json, "validation_threshold", dbl_value))
      out_action.validation_threshold = dbl_value;
   if(Persistence_ParseStringField(json, "queued_time", str_value))
      out_action.queued_time = Persistence_ParseIso8601(str_value);
   if(Persistence_ParseStringField(json, "expires_time", str_value))
      out_action.expires_time = Persistence_ParseIso8601(str_value);
   if(Persistence_ParseStringField(json, "trigger_condition", str_value))
      out_action.trigger_condition = str_value;
   if(Persistence_ParseStringField(json, "intent_id", str_value))
      out_action.intent_id = str_value;
   if(Persistence_ParseStringField(json, "intent_key", str_value))
      out_action.intent_key = str_value;
   if(Persistence_ParseNumberField(json, "queued_confidence", dbl_value))
      out_action.queued_confidence = dbl_value;
   if(Persistence_ParseNumberField(json, "queued_efficiency", dbl_value))
      out_action.queued_efficiency = dbl_value;
   if(Persistence_ParseNumberField(json, "rho_est", dbl_value))
      out_action.rho_est = dbl_value;
   if(Persistence_ParseNumberField(json, "est_value", dbl_value))
      out_action.est_value = dbl_value;
   if(Persistence_ParseNumberField(json, "gate_open_risk", dbl_value))
      out_action.gate_open_risk = dbl_value;
   if(Persistence_ParseNumberField(json, "gate_pending_risk", dbl_value))
      out_action.gate_pending_risk = dbl_value;
   if(Persistence_ParseNumberField(json, "gate_next_risk", dbl_value))
      out_action.gate_next_risk = dbl_value;
   if(Persistence_ParseNumberField(json, "room_today", dbl_value))
      out_action.room_today = dbl_value;
   if(Persistence_ParseNumberField(json, "room_overall", dbl_value))
      out_action.room_overall = dbl_value;
   if(Persistence_ParseStringField(json, "gate_pass", str_value))
      out_action.gate_pass = (StringCompare(str_value, "true") == 0 || str_value == "1");
   if(Persistence_ParseStringField(json, "gating_reason", str_value))
      out_action.gating_reason = str_value;
   if(Persistence_ParseStringField(json, "news_window_state", str_value))
      out_action.news_window_state = str_value;
   return true;
}

string Persistence_JoinJsonObjects(const string &objects[])
{
   string joined = "[";
   for(int i = 0; i < ArraySize(objects); ++i)
   {
      if(i > 0)
         joined += ",";
      joined += objects[i];
   }
   joined += "]";
   return joined;
}

bool Persistence_EnsureIntentFileExists()
{
   Persistence_EnsureFolders();
   int handle = FileOpen(FILE_INTENTS, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;
   if(FileSize(handle) == 0)
      FileWrite(handle, "{\"intents\":[],\"queued_actions\":[]}");
   FileClose(handle);
   return true;
}

void IntentJournal_Clear(IntentJournal &journal)
{
   ArrayResize(journal.intents, 0);
   ArrayResize(journal.queued_actions, 0);
}

bool IntentJournal_Load(IntentJournal &journal)
{
   IntentJournal_Clear(journal);
   if(!Persistence_EnsureIntentFileExists())
      return false;
   string contents = Persistence_ReadWholeFile(FILE_INTENTS);
   if(contents == "" || contents == "{}")
      return true;

   string intents_raw = Persistence_ExtractJsonArray(contents, "intents");
   string actions_raw = Persistence_ExtractJsonArray(contents, "queued_actions");

   string intent_objects[];
   Persistence_SplitJsonArrayObjects(intents_raw, intent_objects);
   ArrayResize(journal.intents, ArraySize(intent_objects));
   for(int i = 0; i < ArraySize(intent_objects); ++i)
      Persistence_OrderIntentFromJson(intent_objects[i], journal.intents[i]);

   string action_objects[];
   Persistence_SplitJsonArrayObjects(actions_raw, action_objects);
   ArrayResize(journal.queued_actions, ArraySize(action_objects));
   for(int i = 0; i < ArraySize(action_objects); ++i)
      Persistence_ActionFromJson(action_objects[i], journal.queued_actions[i]);

   return true;
}

bool IntentJournal_Save(const IntentJournal &journal)
{
   Persistence_EnsureFolders();
   string objects_intents[];
   ArrayResize(objects_intents, ArraySize(journal.intents));
   for(int i = 0; i < ArraySize(journal.intents); ++i)
   {
      // Verbose per-intent save logging removed to reduce noise
      Persistence_OrderIntentToJson(journal.intents[i], objects_intents[i]);
   }

   string objects_actions[];
   ArrayResize(objects_actions, ArraySize(journal.queued_actions));
   for(int i = 0; i < ArraySize(journal.queued_actions); ++i)
      Persistence_ActionToJson(journal.queued_actions[i], objects_actions[i]);

   string serialized = "{";
   serialized += "\"intents\":" + Persistence_JoinJsonObjects(objects_intents) + ",";
   serialized += "\"queued_actions\":" + Persistence_JoinJsonObjects(objects_actions);
   serialized += "}";

   return Persistence_WriteWholeFile(FILE_INTENTS, serialized);
}

int IntentJournal_FindIntentById(const IntentJournal &journal, const string intent_id)
{
   for(int i = 0; i < ArraySize(journal.intents); ++i)
   {
      if(journal.intents[i].intent_id == intent_id)
         return i;
   }
   return -1;
}

int IntentJournal_FindIntentByAcceptKey(const IntentJournal &journal, const string accept_key)
{
   for(int i = 0; i < ArraySize(journal.intents); ++i)
   {
      if(journal.intents[i].accept_once_key == accept_key)
         return i;
   }
   return -1;
}

int IntentJournal_FindActionById(const IntentJournal &journal, const string action_id)
{
   for(int i = 0; i < ArraySize(journal.queued_actions); ++i)
   {
      if(journal.queued_actions[i].action_id == action_id)
         return i;
   }
   return -1;
}

int IntentJournal_FindActionByAcceptKey(const IntentJournal &journal, const string accept_key)
{
   for(int i = 0; i < ArraySize(journal.queued_actions); ++i)
   {
      if(journal.queued_actions[i].accept_once_key == accept_key)
         return i;
   }
   return -1;
}

bool IntentJournal_RemoveIntentById(IntentJournal &journal, const string intent_id)
{
   int index = IntentJournal_FindIntentById(journal, intent_id);
   if(index < 0)
      return false;
   for(int i = index + 1; i < ArraySize(journal.intents); ++i)
      journal.intents[i - 1] = journal.intents[i];
   ArrayResize(journal.intents, ArraySize(journal.intents) - 1);
   return true;
}

bool IntentJournal_RemoveActionById(IntentJournal &journal, const string action_id)
{
   int index = IntentJournal_FindActionById(journal, action_id);
   if(index < 0)
      return false;
   for(int i = index + 1; i < ArraySize(journal.queued_actions); ++i)
      journal.queued_actions[i - 1] = journal.queued_actions[i];
   ArrayResize(journal.queued_actions, ArraySize(journal.queued_actions) - 1);
   return true;
}

void IntentJournal_TouchSequences(const IntentJournal &journal, int &out_intent_seq, int &out_action_seq)
{
   out_intent_seq = 0;
   out_action_seq = 0;
   for(int i = 0; i < ArraySize(journal.intents); ++i)
   {
      const string id = journal.intents[i].intent_id;
      int underscore = -1;
      int pos = StringFind(id, "_");
      while(pos >= 0)
      {
         underscore = pos;
         pos = StringFind(id, "_", pos + 1);
      }
      if(underscore > 0)
      {
         string suffix = StringSubstr(id, underscore + 1);
         int seq = (int)StringToInteger(suffix);
         if(seq > out_intent_seq)
            out_intent_seq = seq;
      }
   }
   for(int j = 0; j < ArraySize(journal.queued_actions); ++j)
   {
      const string id = journal.queued_actions[j].action_id;
      int underscore = -1;
      int pos = StringFind(id, "_");
      while(pos >= 0)
      {
         underscore = pos;
         pos = StringFind(id, "_", pos + 1);
      }
      if(underscore > 0)
      {
         string suffix = StringSubstr(id, underscore + 1);
         int seq = (int)StringToInteger(suffix);
         if(seq > out_action_seq)
            out_action_seq = seq;
      }
   }
}

// Load challenge state (tolerate missing)
void Persistence_LoadChallengeState()
{
   Persistence_EnsureFolders();
   int h = FileOpen(FILE_CHALLENGE_STATE, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      // initialize defaults and create file
      ChallengeState s = State_Get();
      s.initial_baseline = AccountInfoDouble(ACCOUNT_EQUITY);
      s.baseline_today = s.initial_baseline;
      s.trading_enabled = true;
      s.micro_mode = false;
      s.day_peak_equity = s.baseline_today;
      s.server_midnight_ts = (datetime)0;
      s.baseline_today_e0 = s.baseline_today;
      s.baseline_today_b0 = AccountInfoDouble(ACCOUNT_BALANCE);
      State_Set(s);
      int hw = FileOpen(FILE_CHALLENGE_STATE, FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(hw!=INVALID_HANDLE)
      {
         FileWrite(hw, "initial_baseline="+DoubleToString(s.initial_baseline,2));
         FileWrite(hw, "baseline_today="+DoubleToString(s.baseline_today,2));
         FileWrite(hw, "gDaysTraded=0");
         FileWrite(hw, "last_counted_server_date=0");
         FileWrite(hw, "trading_enabled=1");
         FileWrite(hw, "disabled_permanent=0");
         FileWrite(hw, "micro_mode=0");
         FileWrite(hw, "day_peak_equity="+DoubleToString(s.day_peak_equity,2));
         FileWrite(hw, "server_midnight_ts=0");
         FileWrite(hw, "baseline_today_e0="+DoubleToString(s.baseline_today_e0,2));
         FileWrite(hw, "baseline_today_b0="+DoubleToString(s.baseline_today_b0,2));
         FileClose(hw);
      }
      return;
   }
   // simple key=value parse; tolerate placeholder JSON "{}"
   ChallengeState s = State_Get();
   bool parsed_any=false;
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      int pos = StringFind(line, "=");
      if(pos>0)
      {
         string k = StringSubstr(line,0,pos);
         string v = StringSubstr(line,pos+1);
         if(k=="initial_baseline") { s.initial_baseline = StringToDouble(v); parsed_any=true; }
         else if(k=="baseline_today") { s.baseline_today = StringToDouble(v); parsed_any=true; }
         else if(k=="gDaysTraded") { s.gDaysTraded = (int)StringToInteger(v); parsed_any=true; }
         else if(k=="last_counted_server_date") { s.last_counted_server_date = (int)StringToInteger(v); parsed_any=true; }
         else if(k=="trading_enabled") { s.trading_enabled = (StringToInteger(v)!=0); parsed_any=true; }
         else if(k=="disabled_permanent") { s.disabled_permanent = (StringToInteger(v)!=0); parsed_any=true; }
         else if(k=="micro_mode") { s.micro_mode = (StringToInteger(v)!=0); parsed_any=true; }
         else if(k=="day_peak_equity") { s.day_peak_equity = StringToDouble(v); parsed_any=true; }
         else if(k=="server_midnight_ts") { s.server_midnight_ts = (datetime)StringToInteger(v); parsed_any=true; }
         else if(k=="baseline_today_e0") { s.baseline_today_e0 = StringToDouble(v); parsed_any=true; }
         else if(k=="baseline_today_b0") { s.baseline_today_b0 = StringToDouble(v); parsed_any=true; }
      }
   }
   FileClose(h);
   if(!parsed_any)
   {
      // Rewrite defaults over placeholder contents
      s.initial_baseline = AccountInfoDouble(ACCOUNT_EQUITY);
      s.baseline_today = s.initial_baseline;
      s.trading_enabled = true;
      s.disabled_permanent = false;
      s.micro_mode = false;
      s.day_peak_equity = s.baseline_today;
      s.server_midnight_ts = (datetime)0;
      s.baseline_today_e0 = s.baseline_today;
      s.baseline_today_b0 = AccountInfoDouble(ACCOUNT_BALANCE);
      int hw = FileOpen(FILE_CHALLENGE_STATE, FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(hw!=INVALID_HANDLE)
      {
         FileWrite(hw, "initial_baseline="+DoubleToString(s.initial_baseline,2));
         FileWrite(hw, "baseline_today="+DoubleToString(s.baseline_today,2));
         FileWrite(hw, "gDaysTraded="+(string)s.gDaysTraded);
         FileWrite(hw, "last_counted_server_date="+(string)s.last_counted_server_date);
         FileWrite(hw, "trading_enabled="+(s.trading_enabled?"1":"0"));
         FileWrite(hw, "disabled_permanent=0");
         FileWrite(hw, "micro_mode=0");
         FileWrite(hw, "day_peak_equity="+DoubleToString(s.day_peak_equity,2));
         FileWrite(hw, "server_midnight_ts=0");
         FileWrite(hw, "baseline_today_e0="+DoubleToString(s.baseline_today_e0,2));
         FileWrite(hw, "baseline_today_b0="+DoubleToString(s.baseline_today_b0,2));
         FileClose(hw);
      }
   }
   State_Set(s);
}

// Flush state to disk
void Persistence_Flush()
{
   ChallengeState s = State_Get();
   int h = FileOpen(FILE_CHALLENGE_STATE, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
   {
      FileWrite(h, "initial_baseline="+DoubleToString(s.initial_baseline,2));
      FileWrite(h, "baseline_today="+DoubleToString(s.baseline_today,2));
      FileWrite(h, "gDaysTraded="+(string)s.gDaysTraded);
      FileWrite(h, "last_counted_server_date="+(string)s.last_counted_server_date);
      FileWrite(h, "trading_enabled="+(s.trading_enabled?"1":"0"));
      FileWrite(h, "disabled_permanent="+(s.disabled_permanent?"1":"0"));
      FileWrite(h, "micro_mode="+(s.micro_mode?"1":"0"));
      FileWrite(h, "day_peak_equity="+DoubleToString(s.day_peak_equity,2));
      FileWrite(h, "server_midnight_ts="+(string)s.server_midnight_ts);
      FileWrite(h, "baseline_today_e0="+DoubleToString(s.baseline_today_e0,2));
      FileWrite(h, "baseline_today_b0="+DoubleToString(s.baseline_today_b0,2));
      FileClose(h);
   }
   // TODO[M4/M6]: idempotent recovery and TTL for queued actions
}
#endif // RPEA_PERSISTENCE_MQH
