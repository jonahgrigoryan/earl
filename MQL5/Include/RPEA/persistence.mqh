#pragma once
// persistence.mqh - Persistence & folder creation (M1 stubs)
// References: finalspec.md (Persistence/Logs & Learning Artifacts)

#include <Files\File.mqh>
#include <RPEA/config.mqh>
#include <RPEA/state.mqh>

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

// Load challenge state (tolerate missing)
void Persistence_LoadChallengeState()
{
   Persistence_EnsureFolders();
   int h = FileOpen(FILE_CHALLENGE_STATE, FILE_READ|FILE_WRITE|FILE_COMMON|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      // initialize defaults and create file
      ChallengeState s = State_Get();
      s.initial_baseline = AccountInfoDouble(ACCOUNT_EQUITY);
      s.baseline_today = s.initial_baseline;
      s.trading_enabled = true;
      State_Set(s);
      int hw = FileOpen(FILE_CHALLENGE_STATE, FILE_WRITE|FILE_COMMON|FILE_TXT|FILE_ANSI);
      if(hw!=INVALID_HANDLE)
      {
         FileWrite(hw, "initial_baseline="+DoubleToString(s.initial_baseline,2));
         FileWrite(hw, "baseline_today="+DoubleToString(s.baseline_today,2));
         FileWrite(hw, "gDaysTraded=0");
         FileWrite(hw, "last_counted_server_date=0");
         FileWrite(hw, "trading_enabled=1");
         FileWrite(hw, "disabled_permanent=0");
         FileClose(hw);
      }
      return;
   }
   // simple key=value parse
   ChallengeState s = State_Get();
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      int pos = StringFind(line, "=");
      if(pos>0)
      {
         string k = StringSubstr(line,0,pos);
         string v = StringSubstr(line,pos+1);
         if(k=="initial_baseline") s.initial_baseline = StringToDouble(v);
         else if(k=="baseline_today") s.baseline_today = StringToDouble(v);
         else if(k=="gDaysTraded") s.gDaysTraded = (int)StringToInteger(v);
         else if(k=="last_counted_server_date") s.last_counted_server_date = (int)StringToInteger(v);
         else if(k=="trading_enabled") s.trading_enabled = (StringToInteger(v)!=0);
         else if(k=="disabled_permanent") s.disabled_permanent = (StringToInteger(v)!=0);
      }
   }
   FileClose(h);
   State_Set(s);
}

// Flush state to disk
void Persistence_Flush()
{
   ChallengeState s = State_Get();
   int h = FileOpen(FILE_CHALLENGE_STATE, FILE_WRITE|FILE_COMMON|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
   {
      FileWrite(h, "initial_baseline="+DoubleToString(s.initial_baseline,2));
      FileWrite(h, "baseline_today="+DoubleToString(s.baseline_today,2));
      FileWrite(h, "gDaysTraded="+(string)s.gDaysTraded);
      FileWrite(h, "last_counted_server_date="+(string)s.last_counted_server_date);
      FileWrite(h, "trading_enabled="+(s.trading_enabled?"1":"0"));
      FileWrite(h, "disabled_permanent="+(s.disabled_permanent?"1":"0"));
      FileClose(h);
   }
   // TODO[M4/M6]: idempotent recovery and TTL for queued actions
}
