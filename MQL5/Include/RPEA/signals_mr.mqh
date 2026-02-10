#ifndef SIGNALS_MR_MQH
#define SIGNALS_MR_MQH
// signals_mr.mqh - MR signal generation (M7 Task 04)
// References: docs/m7-final-workflow.md (Phase 2), m7-task04.md

#include <RPEA/emrt.mqh>
#include <RPEA/rl_agent.mqh>
#include <RPEA/news.mqh>
#include <RPEA/m7_helpers.mqh>
#include <RPEA/mr_context.mqh>
#include <RPEA/symbol_bridge.mqh>
#include <RPEA/config.mqh>
#include <RPEA/app_context.mqh>
#include <RPEA/logging.mqh>

// Module-scope guard (no static locals per repo rules)
bool g_mr_proxy_warned = false;
datetime g_mr_gate_log_time = 0;
string g_mr_gate_log_symbol = "";
string g_mr_gate_log_reason = "";

bool SignalsMR_ShouldLogGate(const string symbol, const string reason, const datetime now)
{
   if(now <= 0)
      return false;
   if(symbol == g_mr_gate_log_symbol &&
      reason == g_mr_gate_log_reason &&
      (now - g_mr_gate_log_time) < 60)
      return false;
   g_mr_gate_log_symbol = symbol;
   g_mr_gate_log_reason = reason;
   g_mr_gate_log_time = now;
   return true;
}

void SignalsMR_LogGate(const string symbol, const string reason, const string details, const datetime now)
{
   if(!SignalsMR_ShouldLogGate(symbol, reason, now))
      return;
   string fields = StringFormat("{\"symbol\":\"%s\",\"reason\":\"%s\",%s}", symbol, reason, details);
   LogDecision("SignalsMR", "GATE", fields);
}

// Dependency validation (safe defaults)
void SignalsMR_ValidateDependencies()
{
   double rank = EMRT_GetRank("XAUEUR");
   double p50 = EMRT_GetP50("XAUEUR");
   int action = RL_ActionForState(0);
   double qadv = RL_GetQAdvantage(0);
   if(rank < 0.0 || p50 < 0.0 || action < 0 || qadv < 0.0)
   {
      // no-op: suppress unused warnings
   }
}

void SignalsMR_GetSpreadChanges(const string symbol, double &changes[], int periods)
{
   if(periods <= 0)
   {
      ArrayResize(changes, 0);
      return;
   }

   ArrayResize(changes, periods);

   string emrt_symbol = (symbol == "XAUUSD" ? "XAUEUR" : symbol);
   double beta = EMRT_GetBeta(emrt_symbol);

   double xau_close[];
   double eur_close[];
   ArraySetAsSeries(xau_close, true);
   ArraySetAsSeries(eur_close, true);

   int copied_xau = CopyClose("XAUUSD", PERIOD_M1, 0, periods + 1, xau_close);
   int copied_eur = CopyClose("EURUSD", PERIOD_M1, 0, periods + 1, eur_close);

   if(copied_xau < periods + 1 || copied_eur < periods + 1)
   {
      ArrayInitialize(changes, 0.0);
      return;
   }

   for(int i = 0; i < periods; i++)
   {
      double spread_curr = 0.0;
      double spread_prev = 0.0;
      if(MR_UseLogRatio)
      {
         if(xau_close[i] <= 0.0 || eur_close[i] <= 0.0 ||
            xau_close[i + 1] <= 0.0 || eur_close[i + 1] <= 0.0)
         {
            changes[i] = 0.0;
            continue;
         }
         spread_curr = MathLog(xau_close[i]) - MathLog(eur_close[i]);
         spread_prev = MathLog(xau_close[i + 1]) - MathLog(eur_close[i + 1]);
      }
      else
      {
         spread_curr = xau_close[i] - beta * eur_close[i];
         spread_prev = xau_close[i + 1] - beta * eur_close[i + 1];
      }
      changes[i] = spread_curr - spread_prev;
   }
}

bool SignalsMR_CheckEntryConditions(
   const AppContext& ctx,
   const string symbol,
   double &confidence
)
{
   confidence = 0.0;
   const datetime now = ctx.current_server_time;

   if(!Config_GetEnableMR())
   {
      SignalsMR_LogGate(symbol, "disabled", "\"detail\":\"EnableMR=false\"", now);
      return false;
   }

   // Gate 1: News block
   string news_symbol = SymbolBridge_GetExecutionSymbol(symbol);
   if(news_symbol == "") news_symbol = symbol;
   if(News_IsEntryBlocked(news_symbol))
   {
      SignalsMR_LogGate(symbol, "news_blocked",
                        StringFormat("\"news_symbol\":\"%s\"", news_symbol), now);
      return false;
   }

   // Gate 2: EMRT rank must be favorable (fast reversion)
   string emrt_symbol = (symbol == "XAUUSD" ? "XAUEUR" : symbol);
   double emrt_rank = EMRT_GetRank(emrt_symbol);
   if(emrt_rank > EMRT_FastThresholdPct / 100.0)
   {
      SignalsMR_LogGate(symbol, "emrt_rank",
                        StringFormat("\"emrt_rank\":%.4f,\"threshold\":%.4f",
                                     emrt_rank, EMRT_FastThresholdPct / 100.0), now);
      return false;
   }

   // Gate 3: RL action must be ENTER
   double spread_changes[];
   SignalsMR_GetSpreadChanges(emrt_symbol, spread_changes, RL_NUM_PERIODS);
   int state = RL_StateFromSpread(spread_changes, RL_NUM_PERIODS);
   int action = RL_ActionForState(state);
   if(action != RL_ACTION_ENTER)
   {
      SignalsMR_LogGate(symbol, "rl_action",
                        StringFormat("\"state\":%d,\"action\":%d", state, action), now);
      return false;
   }

   // Confidence: weighted combination
   double emrt_fastness = 1.0 - emrt_rank;
   double q_advantage = RL_GetQAdvantage(state);
   double emrt_weight = MR_EMRTWeight;
   double q_weight = 1.0 - emrt_weight;
   confidence = emrt_weight * emrt_fastness + q_weight * q_advantage;

   return true;
}

void SignalsMR_CalculateSLTP(
   const string signal_symbol,
   int direction,
   int &slPoints,
   int &tpPoints
)
{
   if(direction == 0) { /* no-op */ }
   string exec_symbol = SymbolBridge_GetExecutionSymbol(signal_symbol);
   if(exec_symbol == "") exec_symbol = signal_symbol;

   double atr = M7_GetATR_D1(exec_symbol);
   double point = SymbolInfoDouble(exec_symbol, SYMBOL_POINT);

   if(point < 1e-9)
      point = SymbolInfoDouble("XAUUSD", SYMBOL_POINT);

   if(point < 1e-9 || atr <= 0.0 || !MathIsValidNumber(atr))
   {
      slPoints = 0;
      tpPoints = 0;
      return;
   }

   slPoints = (int)(atr * Config_GetSLmult() / point);

   double expected_R = 1.5;
   tpPoints = (int)(slPoints * expected_R);
}

void SignalsMR_Propose(const AppContext& ctx, const string symbol,
                       bool &hasSetup, string &setupType,
                       int &slPoints, int &tpPoints,
                       double &bias, double &confidence)
{
   hasSetup = false;
   setupType = "None";
   slPoints = 0;
   tpPoints = 0;
   bias = 0.0;
   confidence = 0.0;

   // Clear MR context
   g_last_mr_context.expected_R = 0.0;
   g_last_mr_context.expected_hold = 0.0;
   g_last_mr_context.worst_case_risk = 0.0;
   g_last_mr_context.entry_price = 0.0;
   g_last_mr_context.direction = 0;

   // Gate: Proxy must be enabled
   if(!UseXAUEURProxy)
   {
      if(!g_mr_proxy_warned)
      {
         Print("[SignalsMR] WARNING: UseXAUEURProxy=false, MR signals disabled");
         g_mr_proxy_warned = true;
      }
      return;
   }

   // Gate: MR only applies to gold symbols
   if(symbol != "XAUEUR" && symbol != "XAUUSD")
      return;

   string signal_symbol = (symbol == "XAUUSD" ? "XAUEUR" : symbol);
   if(!SignalsMR_CheckEntryConditions(ctx, signal_symbol, confidence))
      return;

   double spread_mean = M7_GetSpreadMean(signal_symbol, 60);
   double spread_current = M7_GetSpreadCurrent(signal_symbol);

   if(spread_current > spread_mean)
      bias = -1.0;  // Short: revert down
   else
      bias = 1.0;   // Long: revert up

   if(MR_LongOnly && bias < 0.0)
      return;

   int direction = (bias > 0.0) ? 1 : -1;
   SignalsMR_CalculateSLTP(signal_symbol, direction, slPoints, tpPoints);

   if(confidence < MR_ConfCut)
      return;

   hasSetup = true;
   setupType = "MR";

   // Populate MR context for allocator
   // CRITICAL: Use execution symbol for entry price, not signal symbol
   string exec_symbol = SymbolBridge_GetExecutionSymbol(signal_symbol);
   if(exec_symbol == "")
      exec_symbol = signal_symbol;

   double bid = 0.0;
   double ask = 0.0;
   if(!SymbolInfoDouble(exec_symbol, SYMBOL_BID, bid) ||
      !SymbolInfoDouble(exec_symbol, SYMBOL_ASK, ask) ||
      bid <= 0.0 || ask <= 0.0)
   {
      hasSetup = false;
      setupType = "None";
      return;
   }

   if(direction > 0)
      g_last_mr_context.entry_price = ask;
   else
      g_last_mr_context.entry_price = bid;

   g_last_mr_context.direction = direction;
   g_last_mr_context.expected_R = 1.5;
   g_last_mr_context.expected_hold = EMRT_GetP50(signal_symbol);
   g_last_mr_context.worst_case_risk = 0.0;
}

#endif // SIGNALS_MR_MQH
