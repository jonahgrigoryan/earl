#pragma once
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
static bool IsNewServerDay(datetime previousTimestamp)
{
   return TimeUtils_IsNewServerDay(previousTimestamp);
}

// TODO[M4]: DST handling and CEST mapping helpers
