#ifndef TIMEUTILS_MQH
#define TIMEUTILS_MQH
// timeutils.mqh - Time helpers (M1 stubs)
// References: finalspec.md (Timezone, DST handling)

// Compute server midnight (00:00:00) for given timestamp (no DST adjustments in M1)
datetime TimeUtils_ServerMidnight(const datetime ts)
{
   MqlDateTime t;
   TimeToStruct(ts, t);
   t.hour = 0;
   t.min  = 0;
   t.sec  = 0;
   return StructToTime(t);
}

// Return true if TimeCurrent() is a new server day vs dt_prev (anchor on midnight)
bool TimeUtils_IsNewServerDay(const datetime dt_prev)
{
   datetime prev_mid = TimeUtils_ServerMidnight(dt_prev);
   datetime cur_mid  = TimeUtils_ServerMidnight(TimeCurrent());
   return (prev_mid != cur_mid);
}

// Alias stub mirroring prompt naming (no namespaces in MQL5)
bool IsNewServerDay(datetime previousTimestamp)
{
   return TimeUtils_IsNewServerDay(previousTimestamp);
}

//==============================================================================
// M4-Task02: Server-Day + CEST Reporting Helpers
//==============================================================================

// Get server date string "YYYY.MM.DD" from server time
string TimeUtils_ServerDateString(const datetime server_time)
{
   MqlDateTime dt;
   TimeToStruct(server_time, dt);
   return StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day);
}

// Get server date int yyyymmdd from server time
int TimeUtils_ServerDateInt(const datetime server_time)
{
   MqlDateTime dt;
   TimeToStruct(server_time, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

// Convert server time to CEST using configured offset (reporting only)
// Note: ServerToCEST_OffsetMinutes must be defined as an input variable in RPEA.mq5
#ifdef RPEA_TEST_RUNNER
#ifndef ServerToCEST_OffsetMinutes
#define ServerToCEST_OffsetMinutes 0
#endif
#endif

datetime TimeUtils_ServerToCEST(const datetime server_time)
{
   return server_time + ServerToCEST_OffsetMinutes * 60;
}

// Get CEST report date string "YYYY.MM.DD" from server time
string TimeUtils_CestDateString(const datetime server_time)
{
   datetime cest_time = TimeUtils_ServerToCEST(server_time);
   MqlDateTime dt;
   TimeToStruct(cest_time, dt);
   return StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day);
}

#endif // TIMEUTILS_MQH
