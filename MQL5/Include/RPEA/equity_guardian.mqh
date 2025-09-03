#pragma once
// equity_guardian.mqh - Equity rooms and floors (M1 stubs)
// References: finalspec.md (Equity & Risk Caps)

struct AppContext;
struct EquityRooms { double room_today; double room_overall; };

EquityRooms Equity_ComputeRooms(const AppContext& ctx)
{
   // Placeholder rooms: large positive to allow flow in M1
   EquityRooms r; r.room_today = 1e9; r.room_overall = 1e9;
   return r;
}

bool Equity_CheckFloors(const AppContext& ctx)
{
   // TODO[M4]: daily/overall floors, kill-switch behavior
   return true; // OK to proceed
}

bool Equity_RoomAllowsNextTrade()
{
   // TODO[M4]: compute from rooms and pending/open risk
   return true;
}
