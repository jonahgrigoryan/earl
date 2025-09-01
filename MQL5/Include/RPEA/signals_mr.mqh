#pragma once
// signals_mr.mqh - MR signal API (M1 stubs)
// References: finalspec.md (Signal Engine: MR)

void SignalsMR_Propose(const AppContext& ctx, const string symbol,
                       bool &hasSetup, string &setupType,
                       int &slPoints, int &tpPoints,
                       double &bias, double &confidence)
{
   // TODO[M7]: wire EMRT rank, RL confidence, time-stop bounds
   hasSetup = false;
   setupType = "None";
   slPoints = 0;
   tpPoints = 0;
   bias = 0.0;
   confidence = 0.0;
}
