#ifndef RPEA_PERSISTENCE_MQH
#define RPEA_PERSISTENCE_MQH
// persistence.mqh - Persistence & folder creation (M1 stubs)
// References: finalspec.md (Persistence/Logs & Learning Artifacts)

#include <Files\\File.mqh>
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

// Ensure placeholder files exist (tolerate if already present)
void Persistence_EnsurePlaceholderFiles()
{
   // State files
   int h;
   h = FileOpen(FILE_INTENTS, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
   {
      if(FileSize(h)==0) FileWrite(h, "{}");
      FileClose(h);
   }
   // News CSV fallback
   h = FileOpen(FILE_NEWS_FALLBACK, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
   {
      if(FileSize(h)==0) FileWrite(h, "timestamp,impact,countries,symbols");
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
         FileWrite(h, "QueuedActionTTLMin=5");
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
