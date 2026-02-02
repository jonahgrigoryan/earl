#ifndef RPEA_META_POLICY_MQH
#define RPEA_META_POLICY_MQH
// meta_policy.mqh - Meta-Policy chooser (M7 Phase 4, Task 05)
// Deterministic strategy selection between BWISC and MR with optional bandit.
// References: docs/m7-final-workflow.md (Phase 4, Task 5, Steps 5.1-5.4)

#include <RPEA/app_context.mqh>
#include <RPEA/bandit.mqh>
#include <RPEA/config.mqh>
#include <RPEA/emrt.mqh>
#include <RPEA/logging.mqh>
#include <RPEA/m7_helpers.mqh>
#include <RPEA/news.mqh>
#include <RPEA/rl_agent.mqh>

// Decision-only gate: 1 = log decisions without executing (Phase 4)
// Set to 0 in Phase 5 Task 7 to enable actual trade execution.
#define M7_DECISION_ONLY 1

//+------------------------------------------------------------------+
//| Step 5.1: Context structure                                       |
//+------------------------------------------------------------------+
struct MetaPolicyContext
{
   // BWISC inputs
   bool   bwisc_has_setup;
   double bwisc_confidence;
   double bwisc_ore;
   double bwisc_efficiency;

   // MR inputs
   bool   mr_has_setup;
   double mr_confidence;
   double emrt_rank;
   double q_advantage;
   double mr_efficiency;

   // Market context
   double atr_d1_percentile;
   int    session_age_minutes;
   bool   news_within_15m;

   // Liquidity / news gating
   bool   entry_blocked;
   double spread_quantile;
   double slippage_quantile;

   // Regime context (Phase 5)
   int    regime_label;

   // Session state
   int    entries_this_session;
   bool   locked_to_mr;
};

//+------------------------------------------------------------------+
//| Step 5.2: Deterministic rules (priority-ordered)                  |
//+------------------------------------------------------------------+
string MetaPolicy_DeterministicChoice(const MetaPolicyContext &mpc)
{
   // Rule 0: Entry blocked (news window or stabilization)
   if(mpc.entry_blocked)
      return "Skip";

   // Rule 0b: Liquidity quantile gate
   if(mpc.spread_quantile >= 0.90 || mpc.slippage_quantile >= 0.90)
      return "Skip";

   // Rule 1: Session cap
   if(mpc.entries_this_session >= 2)
      return "Skip";

   // Rule 2: MR lock hysteresis
   if(mpc.locked_to_mr && mpc.mr_has_setup)
      return "MR";

   // Rule 3: Confidence tie-breaker
   if(mpc.bwisc_confidence < Config_GetBWISCConfCut() &&
      mpc.mr_confidence > Config_GetMRConfCut() &&
      mpc.mr_efficiency >= mpc.bwisc_efficiency &&
      mpc.mr_has_setup)
      return "MR";

   // Rule 4: Conditional BWISC replacement
   if(mpc.bwisc_ore < 0.40 &&
      mpc.atr_d1_percentile < 0.50 &&
      mpc.emrt_rank <= Config_GetEMRTFastThresholdPct() / 100.0 &&
      mpc.session_age_minutes < 120 &&
      !mpc.news_within_15m &&
      mpc.mr_has_setup)
      return "MR";

   // Rule 5: BWISC if qualified
   if(mpc.bwisc_has_setup && mpc.bwisc_confidence >= Config_GetBWISCConfCut())
      return "BWISC";

   // Rule 6: MR fallback
   if(!mpc.bwisc_has_setup && mpc.mr_has_setup)
      return "MR";

   // Default: Skip
   return "Skip";
}

//+------------------------------------------------------------------+
//| Step 5.3: Bandit integration (optional, Phase 4 = deterministic)  |
//+------------------------------------------------------------------+
bool MetaPolicy_BanditIsReady()
{
   // TODO[M7-Phase5]: Check if Files/RPEA/bandit/posterior.json exists
   // For Phase 4, always use deterministic rules.
   return false;
}

string MetaPolicy_BanditChoice(const AppContext &ctx, const string symbol,
                               const MetaPolicyContext &mpc)
{
   if(!Config_GetUseBanditMetaPolicy() || !MetaPolicy_BanditIsReady())
      return MetaPolicy_DeterministicChoice(mpc);

   // Call existing bandit API
   BanditPolicy bandit_result = Bandit_SelectPolicy(ctx, symbol);

   string bandit_str;
   switch(bandit_result)
   {
      case Bandit_BWISC: bandit_str = "BWISC"; break;
      case Bandit_MR:    bandit_str = "MR";    break;
      default:           bandit_str = "Skip";  break;
   }

   // Shadow mode: log bandit vs deterministic, use deterministic
   if(Config_GetBanditShadowMode())
   {
      string det_str = MetaPolicy_DeterministicChoice(mpc);
      LogDecision("MetaPolicy", "SHADOW",
         StringFormat("{\"bandit\":\"%s\",\"deterministic\":\"%s\"}",
            bandit_str, det_str));
      return det_str;
   }

   return bandit_str;
}

//+------------------------------------------------------------------+
//| Step 5.4: Main entry point                                        |
//+------------------------------------------------------------------+
string MetaPolicy_Choose(const AppContext &ctx, const string symbol,
                         const bool bw_has, const double bw_conf,
                         const bool mr_has, const double mr_conf)
{
   // Build context from inputs and helpers
   MetaPolicyContext mpc;
   mpc.bwisc_has_setup      = bw_has;
   mpc.bwisc_confidence     = bw_conf;
   mpc.mr_has_setup         = mr_has;
   mpc.mr_confidence        = mr_conf;
   mpc.bwisc_efficiency     = 0.0;   // TODO[M7-Phase5]: rolling efficiency
   mpc.mr_efficiency        = 0.0;   // TODO[M7-Phase5]: rolling efficiency

   // Fill from helpers
   mpc.emrt_rank            = EMRT_GetRank("XAUEUR");
   mpc.q_advantage          = RL_GetQAdvantage(0);
   mpc.bwisc_ore            = M7_GetCurrentORE(ctx, symbol);
   mpc.atr_d1_percentile    = M7_GetATR_D1_Percentile(ctx, symbol);
   mpc.session_age_minutes  = M7_GetSessionAgeMinutes(ctx, symbol);
   mpc.news_within_15m      = M7_NewsIsWithin15Minutes(symbol);
   mpc.entry_blocked        = News_IsEntryBlocked(symbol);
   mpc.spread_quantile      = 0.5;   // TODO[M7-Phase5]: from liquidity stats
   mpc.slippage_quantile    = 0.5;   // TODO[M7-Phase5]: from liquidity stats
   mpc.regime_label         = 0;     // TODO[M7-Phase5]: from Regime_Detect()
   mpc.entries_this_session = M7_GetEntriesThisSession(ctx, symbol);
   mpc.locked_to_mr         = M7_IsLockedToMR();

   // Hard gates must be enforced before bandit choice (Rules 0, 0b, 1)
   bool hard_blocked = (mpc.entry_blocked ||
                        mpc.spread_quantile >= 0.90 ||
                        mpc.slippage_quantile >= 0.90 ||
                        mpc.entries_this_session >= 2);
   string choice = "Skip";
   if(!hard_blocked)
      choice = MetaPolicy_BanditChoice(ctx, symbol, mpc);

   // Decision-only gate (Phase 4)
   if(M7_DECISION_ONLY)
   {
   LogDecision("MetaPolicy", "DECISION_ONLY",
      StringFormat("{\"choice\":\"%s\",\"bw_has\":%s,\"bw_conf\":%.2f,"
                   "\"mr_has\":%s,\"mr_conf\":%.2f,"
                   "\"emrt_rank\":%.3f,\"q_adv\":%.3f,"
                   "\"ore\":%.3f,\"atr_pct\":%.3f,"
                   "\"sess_age\":%d,\"news15\":%s,"
                   "\"entries\":%d,\"locked_mr\":%s}",
         choice,
         bw_has ? "true" : "false", bw_conf,
         mr_has ? "true" : "false", mr_conf,
         mpc.emrt_rank, mpc.q_advantage,
         mpc.bwisc_ore, mpc.atr_d1_percentile,
         mpc.session_age_minutes,
         mpc.news_within_15m ? "true" : "false",
         mpc.entries_this_session,
         mpc.locked_to_mr ? "true" : "false"));
   return "Skip";   // Phase 4: disable all execution
   }

   // Phase 5+: update session state and return actual choice
   if(choice == "MR")
   {
      M7_SetLockedToMR(true);
   }
   return choice;
}

#endif // RPEA_META_POLICY_MQH
