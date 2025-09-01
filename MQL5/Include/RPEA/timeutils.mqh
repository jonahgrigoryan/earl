#pragma once
// timeutils.mqh - Time helpers (M1 stubs)
// References: finalspec.md (Timezone, DST handling)

// Return true if TimeCurrent() is a new server day vs dt_prev (anchor on date change)
bool TimeUtils_IsNewServerDay(const datetime dt_prev)
{
   datetime now = TimeCurrent();
   MqlDateTime a,b;
   TimeToStruct(now,a);
   TimeToStruct(dt_prev,b);
   return (a.year!=b.year || a.mon!=b.mon || a.day!=b.day);
}

// TODO[M4]: DST handling and CEST mapping helpers
