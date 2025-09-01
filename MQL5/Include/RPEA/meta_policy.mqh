#pragma once
// meta_policy.mqh - Meta-Policy chooser (M1 stubs)
// References: finalspec.md (Meta-Policy (BWISC + MR Ensemble))

string MetaPolicy_Choose(const bool bw_has, const double bw_conf,
                         const bool mr_has, const double mr_conf)
{
   // TODO[M7]: implement full tie-breakers and replacement rules
   if(bw_has) return "BWISC";
   if(mr_has) return "MR";
   return "Skip";
}
