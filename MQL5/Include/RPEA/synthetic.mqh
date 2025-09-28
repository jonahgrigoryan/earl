#ifndef RPEA_SYNTHETIC_MQH
#define RPEA_SYNTHETIC_MQH
// synthetic.mqh - Synthetic XAUEUR stubs (M1)
// References: finalspec.md (Synthetic Cross Support)

double Synthetic_XAUEUR_Prices()
{
   // TODO[M3]: compute synthetic price from synchronized XAUUSD/EURUSD legs
   return 0.0;
}

double Synthetic_MapRiskProxy(const double sl_synth_points, const double eurusd_rate)
{
   // TODO[M3]: proxy mapping for SL distance when downgrading to XAUUSD
   return sl_synth_points * eurusd_rate;
}

double Synthetic_ReplicationSizing()
{
   // TODO[M3]: replication sizing math for two-leg exposure
   return 0.0;
}
#endif // RPEA_SYNTHETIC_MQH
