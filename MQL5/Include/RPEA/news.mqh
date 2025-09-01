#pragma once
// news.mqh - News filter stubs (M1)
// References: finalspec.md (News Compliance)

bool News_IsBlocked(const string symbol)
{
   // TODO[M4]: implement Master 10-minute window logic; CSV fallback parse
   return false;
}

void News_LoadCsvFallback()
{
   // TODO[M4]: tolerate empty/missing CSV without errors
}

void News_PostNewsStabilization()
{
   // TODO[M4]: post-news stabilization checks
}
