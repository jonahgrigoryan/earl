#ifndef RPEA_REGIME_MQH
#define RPEA_REGIME_MQH
// regime.mqh - Regime detection API (M1 stubs)
// References: finalspec.md (Market Regime Detection)

string Regime_Label(const string symbol)
{
   // TODO[M6]: implement ATR/σ bands, ADX, Hurst/ACF, ORE
   return "unknown";
}

void Regime_Features(const string symbol)
{
   // TODO[M6]: populate features for meta-policy
}
#endif // RPEA_REGIME_MQH
