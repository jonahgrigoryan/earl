#ifndef RPEA_META_POLICY_MQH
#define RPEA_META_POLICY_MQH
// meta_policy.mqh - Meta-Policy chooser (M7 Phase 0)
// References: finalspec.md (Meta-Policy (BWISC + MR Ensemble))

struct AppContext;

// Full signature for Phase 4 implementation
// ctx: application context with session/equity state
// symbol: trading symbol
// bw_has/bw_conf: BWISC signal availability and confidence
// mr_has/mr_conf: MR signal availability and confidence
string MetaPolicy_Choose(const AppContext &ctx, const string symbol,
                         const bool bw_has, const double bw_conf,
                         const bool mr_has, const double mr_conf)
{
   // TODO[M7-Phase4]: implement full tie-breakers and replacement rules
   // TODO[M7-Phase4]: implement bandit choice with UseBanditMetaPolicy flag
   // TODO[M7-Phase4]: implement hysteresis and session cap

   // Suppress unused parameter warnings
   if(ctx.symbols_count < 0) { /* no-op */ }
   if(symbol == "") { /* no-op */ }

   // Safe default: prefer BWISC, then MR, then Skip
   if(bw_has) return "BWISC";
   if(mr_has) return "MR";
   return "Skip";
}

#endif // RPEA_META_POLICY_MQH
