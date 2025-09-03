#pragma once
// news.mqh - News filter stubs (M1)
// References: finalspec.md (News Compliance)

/// Returns whether news window blocks entries for the symbol (M1: always false)
bool News_IsBlocked(const string symbol)
{
   // TODO[M4]: implement Master 10-minute window logic; CSV fallback parse
   return false;
}

/// Tolerant CSV fallback reader for calendar_high_impact.csv
/// Expected columns: timestamp,impact,countries,symbols
/// M1: only attempts to open and read; ignores content; safe if missing/empty.
void News_LoadCsvFallback()
{
   string path = FILE_NEWS_FALLBACK;
   int h = FileOpen(path, FILE_READ|FILE_COMMON|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
      return; // tolerate missing
   // Naive tolerant pass over lines
   while(!FileIsEnding(h))
   {
      string _line = FileReadString(h);
      // ignore content
   }
   FileClose(h);
}

void News_PostNewsStabilization()
{
   // TODO[M4]: post-news stabilization checks
}
