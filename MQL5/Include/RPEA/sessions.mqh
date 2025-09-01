#pragma once
// sessions.mqh - Session predicates (M1 stubs)
// References: finalspec.md (Session Governance, Session window predicate)

// Predicate signatures
bool Sessions_InLondon(const datetime now, const int startHourLO) { return false; }
bool Sessions_InNewYork(const datetime now, const int startHourNY) { return false; }
bool Sessions_InORWindow(const datetime t0, const int ORMinutes) { return false; }
bool Sessions_CutoffReached(const datetime now, const int cutoffHour) { return false; }

// InSession signature per spec; placeholder returns false
bool InSession(const datetime t0, const int ORMinutes)
{
   // TODO[M2]: proper window math per spec and server-day anchoring
   return false;
}
