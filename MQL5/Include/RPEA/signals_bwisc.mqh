#pragma once
// signals_bwisc.mqh - BWISC signal API (M1 stubs)
// References: finalspec.md (Original Strategy: BWISC)

// Propose a BWISC setup for symbol
// Params:
//  - ctx: app context
//  - symbol: target symbol
//  - hasSetup: out flag if setup proposed
//  - setupType: out string "BC"/"MSC"/"None"
//  - slPoints/tpPoints: suggested distances in points
//  - bias: computed bias -1..+1
//  - confidence: 0..1
void SignalsBWISC_Propose(const AppContext& ctx, const string symbol,
                          bool &hasSetup, string &setupType,
                          int &slPoints, int &tpPoints,
                          double &bias, double &confidence)
{
   // TODO[M2]: implement BTR/SDR/ORE/RSI → Bias → BC/MSC gating and target calc
   hasSetup = false;
   setupType = "None";
   slPoints = 0;
   tpPoints = 0;
   bias = 0.0;
   confidence = 0.0;
}
