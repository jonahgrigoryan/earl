#ifndef RPEA_NEWS_MQH
#define RPEA_NEWS_MQH
// news.mqh - News filter with CSV fallback (M3 Task 10)
// References: finalspec.md (News Compliance), .kiro/specs/rpea-m3/tasks.md §10

#include <RPEA/config.mqh>

extern int NewsBufferS;

struct NewsEvent
{
   datetime timestamp_utc;
   string   symbol;
   string   impact;
   string   source;
   string   event;
   int      prebuffer_min;
   int      postbuffer_min;
   datetime block_start;
   datetime block_end;
   bool     is_valid;
};

static NewsEvent g_news_events[];
static int       g_news_event_count = 0;
static datetime  g_news_last_mtime = 0;
static bool      g_news_cache_valid = false;
static int       g_news_last_load_code = 0;
static bool      g_news_force_reload = false;

//------------------------------------------------------------------------------
// Helpers
//------------------------------------------------------------------------------

void News_ClearCache()
{
   ArrayResize(g_news_events, 0);
   g_news_event_count = 0;
   g_news_cache_valid = false;
   g_news_last_load_code = -1;
}

string News_Trim(const string value)
{
   string tmp = value;
   StringReplace(tmp, "\r", "");
   StringTrimLeft(tmp);
   StringTrimRight(tmp);
   return tmp;
}

string News_ResolveRelativePath(const string path)
{
   if(StringLen(path) >= 6 && StringSubstr(path, 0, 6) == "Files/")
      return StringSubstr(path, 6);
   return path;
}

string News_NormalizeSymbol(const string raw)
{
   string sym = News_Trim(raw);
   sym = StringToUpper(sym);
   int len = StringLen(sym);
   if(len == 0)
      return "";

   string normalized = "";
   for(int i = 0; i < len; ++i)
   {
      ushort ch = StringGetCharacter(sym, i);
      if(ch == '.')
         break;
      if(ch == '_' || ch == '-' || ch == ' ')
         continue;
      if((ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9'))
         normalized += (string)ch;
   }

   if(normalized == "")
      normalized = sym;
   return normalized;
}

string News_NormalizeImpact(const string raw, bool &ok)
{
   string impact = StringToUpper(News_Trim(raw));
   if(impact == "HIGH" || impact == "MEDIUM" || impact == "LOW")
   {
      ok = true;
      return impact;
   }
   ok = false;
   return impact;
}

bool News_ParseIso8601Utc(const string text, datetime &out_value)
{
   string value = News_Trim(text);
   if(value == "")
      return false;

   int pos_t = StringFind(value, "T");
   if(pos_t < 0)
      pos_t = StringFind(value, " ");
   if(pos_t <= 0)
      return false;

   string date_part = StringSubstr(value, 0, pos_t);
   string time_part = StringSubstr(value, pos_t + 1);

   string tz_suffix = "Z";
   int pos_z = StringFind(time_part, "Z");
   int pos_plus = StringFind(time_part, "+");
   int pos_minus = -1;
   for(int i = 0; i < StringLen(time_part); ++i)
   {
      ushort ch = StringGetCharacter(time_part, i);
      if(ch == '-')
      {
         pos_minus = i;
         break;
      }
   }

   if(pos_z >= 0)
   {
      tz_suffix = "Z";
      time_part = StringSubstr(time_part, 0, pos_z);
   }
   else if(pos_plus >= 0 || pos_minus >= 0)
   {
      int pos = pos_plus >= 0 ? pos_plus : pos_minus;
      tz_suffix = StringSubstr(time_part, pos);
      time_part = StringSubstr(time_part, 0, pos);
   }

   string date_fields[];
   if(StringSplit(date_part, '-', date_fields) != 3)
      return false;

   string time_fields[];
   if(StringSplit(time_part, ':', time_fields) < 2)
      return false;

   int year = (int)StringToInteger(date_fields[0]);
   int month = (int)StringToInteger(date_fields[1]);
   int day = (int)StringToInteger(date_fields[2]);
   int hour = (int)StringToInteger(time_fields[0]);
   int minute = (int)StringToInteger(time_fields[1]);
   int second = 0;
   if(ArraySize(time_fields) >= 3)
      second = (int)StringToInteger(time_fields[2]);

   if(year < 1970 || month < 1 || month > 12 || day < 1 || day > 31)
      return false;
   if(hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59)
      return false;

   MqlDateTime tm = {year, month, day, hour, minute, second};
   datetime calculated = StructToTime(tm);
   if(calculated <= 0)
      return false;

   int offset_sign = 0;
   int offset_seconds = 0;
   if(tz_suffix == "" || tz_suffix == "Z")
   {
      offset_sign = 0;
      offset_seconds = 0;
   }
   else
   {
      offset_sign = (StringGetCharacter(tz_suffix, 0) == '-') ? -1 : 1;
      string tz_body = StringSubstr(tz_suffix, 1);
      string tz_fields[];
      if(StringSplit(tz_body, ':', tz_fields) < 1)
         return false;
      int tz_hour = (int)StringToInteger(tz_fields[0]);
      int tz_min = 0;
      if(ArraySize(tz_fields) >= 2)
         tz_min = (int)StringToInteger(tz_fields[1]);
      if(tz_hour < 0 || tz_hour > 23 || tz_min < 0 || tz_min > 59)
         return false;
      offset_seconds = offset_sign * (tz_hour * 3600 + tz_min * 60);
   }

   datetime utc_time = calculated - offset_seconds;
   if(utc_time <= 0)
      return false;

   out_value = utc_time;
   return true;
}

bool News_ParseMinutes(const string text, int &out_value)
{
   string trimmed = News_Trim(text);
   if(trimmed == "")
      return false;

   int start = 0;
   bool negative_allowed = false;
   if(StringLen(trimmed) > 0)
   {
      ushort first = StringGetCharacter(trimmed, 0);
      if(first == '+')
         start = 1;
      else if(first == '-')
      {
         start = 1;
         negative_allowed = true;
      }
   }

   if(start >= StringLen(trimmed))
      return false;

   for(int i = start; i < StringLen(trimmed); ++i)
   {
      ushort ch = StringGetCharacter(trimmed, i);
      if(ch < '0' || ch > '9')
         return false;
   }

   int value = (int)StringToInteger(trimmed);
   if(!negative_allowed && value < 0)
      return false;

   out_value = value;
   return true;
}

bool News_ValidateCsvSchema(const string header_line,
                            int &idx_timestamp,
                            int &idx_symbol,
                            int &idx_impact,
                            int &idx_source,
                            int &idx_event,
                            int &idx_prebuffer,
                            int &idx_postbuffer)
{
   idx_timestamp = -1;
   idx_symbol = -1;
   idx_impact = -1;
   idx_source = -1;
   idx_event = -1;
   idx_prebuffer = -1;
   idx_postbuffer = -1;

   string fields[];
   int count = StringSplit(header_line, ',', fields);
   if(count <= 0)
      return false;

   for(int i = 0; i < count; ++i)
   {
      string field = StringToLower(News_Trim(fields[i]));
      if(field == "timestamp_utc")
         idx_timestamp = i;
      else if(field == "symbol")
         idx_symbol = i;
      else if(field == "impact")
         idx_impact = i;
      else if(field == "source")
         idx_source = i;
      else if(field == "event")
         idx_event = i;
      else if(field == "prebuffer_min")
         idx_prebuffer = i;
      else if(field == "postbuffer_min")
         idx_postbuffer = i;
   }

   bool ok = (idx_timestamp >= 0 && idx_symbol >= 0 && idx_impact >= 0 &&
              idx_source >= 0 && idx_event >= 0 && idx_prebuffer >= 0 && idx_postbuffer >= 0);
   return ok;
}

bool News_GetFileMTime(const string path, datetime &mtime)
{
   mtime = 0;
   string name = "";
   int attributes = 0;
   datetime found_time = 0;
   string mask = News_ResolveRelativePath(path);
   int find_handle = FileFindFirst(mask, name, attributes, found_time);
   if(find_handle == INVALID_HANDLE)
   {
      PrintFormat("[News] CSV missing: %s", path);
      return false;
   }
   FileFindClose(find_handle);
   mtime = found_time;
   return true;
}

bool News_IsCsvFresh(const datetime mtime, const int max_age_hours, const string path)
{
   if(mtime <= 0)
      return false;
   if(max_age_hours <= 0)
      return true;

   datetime now = TimeCurrent();
   if(now <= 0)
      now = mtime;
   double age_hours = (double)(now - mtime) / 3600.0;
   if(age_hours > (double)max_age_hours)
   {
      PrintFormat("[News] CSV stale (age %.1f h > max %d): %s", age_hours, max_age_hours, path);
      return false;
   }
   return true;
}

int News_GlobalBufferSeconds()
{
   if(NewsBufferS <= 0)
      return 0;
   return NewsBufferS;
}

//------------------------------------------------------------------------------
// Public API
//------------------------------------------------------------------------------

bool News_LoadCsvFallback()
{
   // Task 10 assumption: hard-coded defaults until configurable inputs are added.
   string path = DEFAULT_NewsCSVPath;
   string relative_path = News_ResolveRelativePath(path);

   datetime mtime = 0;
   if(!News_GetFileMTime(path, mtime))
   {
      News_ClearCache();
      g_news_last_mtime = 0;
      g_news_last_load_code = 1;
      return false;
   }

   if(!g_news_force_reload && g_news_cache_valid && g_news_last_mtime == mtime)
      return true;

   if(!News_IsCsvFresh(mtime, DEFAULT_NewsCSVMaxAgeHours, path))
   {
      News_ClearCache();
      g_news_last_mtime = mtime;
      g_news_last_load_code = 2;
      return false;
   }

   int handle = FileOpen(relative_path, FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("[News] CSV missing: %s", path);
      News_ClearCache();
      g_news_last_mtime = 0;
      g_news_last_load_code = 3;
      return false;
   }

   if(FileIsEnding(handle))
   {
      FileClose(handle);
      News_ClearCache();
      g_news_last_mtime = mtime;
      g_news_cache_valid = true;
      g_news_last_load_code = 0;
      PrintFormat("[News] Loaded %d events (skipped %d) from fallback CSV", 0, 0);
      g_news_force_reload = false;
      return true;
   }

   string header = FileReadString(handle);
   header = News_Trim(header);

   int idx_timestamp = -1;
   int idx_symbol = -1;
   int idx_impact = -1;
   int idx_source = -1;
   int idx_event = -1;
   int idx_prebuffer = -1;
   int idx_postbuffer = -1;

   if(!News_ValidateCsvSchema(header,
                              idx_timestamp,
                              idx_symbol,
                              idx_impact,
                              idx_source,
                              idx_event,
                              idx_prebuffer,
                              idx_postbuffer))
   {
      Print("[News] CSV invalid headers: expected timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min");
      FileClose(handle);
      News_ClearCache();
      g_news_last_mtime = mtime;
      g_news_last_load_code = 4;
      return false;
   }

   NewsEvent parsed_events[];
   int accepted = 0;
   int skipped = 0;
   int line_number = 1;

   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      line_number++;
      line = News_Trim(line);
      if(line == "")
         continue;

      string columns[];
      int column_count = StringSplit(line, ',', columns);
      if(column_count <= idx_postbuffer)
      {
         skipped++;
         PrintFormat("[News] CSV parse error on line %d: insufficient columns", line_number);
         continue;
      }

      NewsEvent event;
      event.timestamp_utc = 0;
      event.symbol = "";
      event.impact = "";
      event.source = "";
      event.event = "";
      event.prebuffer_min = 0;
      event.postbuffer_min = 0;
      event.block_start = 0;
      event.block_end = 0;
      event.is_valid = false;

      if(!News_ParseIso8601Utc(columns[idx_timestamp], event.timestamp_utc))
      {
         skipped++;
         PrintFormat("[News] CSV parse error on line %d: invalid timestamp", line_number);
         continue;
      }

      event.symbol = News_NormalizeSymbol(columns[idx_symbol]);
      if(event.symbol == "")
      {
         skipped++;
         PrintFormat("[News] CSV parse error on line %d: invalid symbol", line_number);
         continue;
      }

      bool impact_ok = false;
      event.impact = News_NormalizeImpact(columns[idx_impact], impact_ok);
      if(!impact_ok)
      {
         skipped++;
         PrintFormat("[News] CSV parse error on line %d: invalid impact", line_number);
         continue;
      }

      event.source = News_Trim(columns[idx_source]);
      event.event = News_Trim(columns[idx_event]);

      int prebuffer = 0;
      int postbuffer = 0;
      if(!News_ParseMinutes(columns[idx_prebuffer], prebuffer))
      {
         skipped++;
         PrintFormat("[News] CSV parse error on line %d: invalid prebuffer", line_number);
         continue;
      }
      if(!News_ParseMinutes(columns[idx_postbuffer], postbuffer))
      {
         skipped++;
         PrintFormat("[News] CSV parse error on line %d: invalid postbuffer", line_number);
         continue;
      }

      if(prebuffer < 0)
         prebuffer = 0;
      if(postbuffer < 0)
         postbuffer = 0;

      event.prebuffer_min = prebuffer;
      event.postbuffer_min = postbuffer;

      int global_buffer_sec = News_GlobalBufferSeconds();
      int effective_pre_sec = prebuffer * 60;
      int effective_post_sec = postbuffer * 60;
      if(global_buffer_sec > effective_pre_sec)
         effective_pre_sec = global_buffer_sec;
      if(global_buffer_sec > effective_post_sec)
         effective_post_sec = global_buffer_sec;

      event.block_start = event.timestamp_utc - effective_pre_sec;
      if(event.block_start < 0)
         event.block_start = 0;
      event.block_end = event.timestamp_utc + effective_post_sec;
      event.is_valid = true;

      int next_index = ArraySize(parsed_events);
      ArrayResize(parsed_events, next_index + 1);
      parsed_events[next_index] = event;
      accepted++;
   }

   FileClose(handle);

   if(accepted == 0 && skipped > 0)
   {
      News_ClearCache();
      g_news_last_mtime = mtime;
      g_news_last_load_code = 5;
      return false;
   }

   ArrayResize(g_news_events, accepted);
   for(int k = 0; k < accepted; ++k)
      g_news_events[k] = parsed_events[k];

   g_news_event_count = accepted;
   g_news_cache_valid = true;
   g_news_last_mtime = mtime;
   g_news_last_load_code = 0;
   g_news_force_reload = false;

   PrintFormat("[News] Loaded %d events (skipped %d) from fallback CSV", accepted, skipped);
   return true;
}

bool News_ReloadIfChanged()
{
   if(g_news_force_reload)
   {
      return News_LoadCsvFallback();
   }

   string path = DEFAULT_NewsCSVPath;
   datetime current_mtime = 0;
   if(!News_GetFileMTime(path, current_mtime))
   {
      News_ClearCache();
      g_news_last_mtime = 0;
      g_news_last_load_code = 1;
      return false;
   }

   if(g_news_cache_valid && g_news_last_mtime == current_mtime)
      return true;

   return News_LoadCsvFallback();
}

void News_ForceReload()
{
   g_news_force_reload = true;
   g_news_cache_valid = false;
   g_news_last_mtime = 0;
}

bool News_GetEventsForSymbol(const string symbol, NewsEvent &out[])
{
   ArrayResize(out, 0);
   if(!g_news_cache_valid || g_news_event_count <= 0)
      return false;

   string normalized = News_NormalizeSymbol(symbol);
   if(normalized == "")
      return false;

   int matches = 0;
   for(int i = 0; i < g_news_event_count; ++i)
   {
      if(!g_news_events[i].is_valid)
         continue;
      if(g_news_events[i].symbol != normalized)
         continue;
      int idx = ArraySize(out);
      ArrayResize(out, idx + 1);
      out[idx] = g_news_events[i];
      matches++;
   }
   return (matches > 0);
}

bool News_IsBlocked(const string symbol)
{
   if(symbol == "")
      return false;

   News_ReloadIfChanged();
   if(!g_news_cache_valid || g_news_event_count <= 0)
      return false;

   string normalized = News_NormalizeSymbol(symbol);
   if(normalized == "")
      return false;

   datetime now_utc = TimeGMT();
   for(int i = 0; i < g_news_event_count; ++i)
   {
      NewsEvent event = g_news_events[i];
      if(!event.is_valid)
         continue;
      if(event.symbol != normalized)
         continue;
      if(event.impact != "HIGH")
         continue;
      if(now_utc >= event.block_start && now_utc <= event.block_end)
         return true;
   }
   return false;
}

void News_PostNewsStabilization()
{
   // TODO[M4]: post-news stabilization checks
}

#endif // RPEA_NEWS_MQH
