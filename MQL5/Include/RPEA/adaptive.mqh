#ifndef RPEA_ADAPTIVE_MQH
#define RPEA_ADAPTIVE_MQH
// adaptive.mqh - Adaptive risk multiplier
// References: finalspec.md (Adaptive Risk Allocator)

#include <RPEA/config.mqh>

string Adaptive_NormalizeRegimeLabel(const string regime_label)
{
   string label = regime_label;
   StringTrimLeft(label);
   StringTrimRight(label);
   StringToUpper(label);
   return label;
}

double Adaptive_RegimeBaseMultiplier(const string regime_label)
{
   string label = Adaptive_NormalizeRegimeLabel(regime_label);
   if(label == "TRENDING")
      return 1.05;
   if(label == "RANGING")
      return 0.97;
   if(label == "VOLATILE")
      return 0.90;
   return 1.00;
}

double Adaptive_EfficiencyAdjustment(const double efficiency)
{
   if(!MathIsValidNumber(efficiency) || efficiency < 0.0 || efficiency > 1.0)
      return 0.0;

   if(efficiency >= 0.80)
      return 0.10;
   if(efficiency >= 0.65)
      return 0.05;
   if(efficiency <= 0.25)
      return -0.15;
   if(efficiency <= 0.40)
      return -0.08;

   return 0.0;
}

double Adaptive_ClampMultiplier(const double value,
                                const double min_multiplier,
                                const double max_multiplier)
{
   double min_mult = min_multiplier;
   if(!MathIsValidNumber(min_mult) || min_mult <= 0.0)
      min_mult = DEFAULT_AdaptiveRiskMinMult;

   double max_mult = max_multiplier;
   if(!MathIsValidNumber(max_mult) || max_mult <= 0.0)
      max_mult = DEFAULT_AdaptiveRiskMaxMult;

   if(max_mult < min_mult)
   {
      double swap_value = min_mult;
      min_mult = max_mult;
      max_mult = swap_value;
   }

   double clamped = value;
   if(!MathIsValidNumber(clamped))
      clamped = 1.0;
   if(clamped < min_mult)
      clamped = min_mult;
   if(clamped > max_mult)
      clamped = max_mult;

   return clamped;
}

double Adaptive_RiskMultiplierWithBounds(const string regime_label,
                                         const double efficiency,
                                         const double min_multiplier,
                                         const double max_multiplier)
{
   double multiplier = 1.0;
   if(MathIsValidNumber(efficiency) && efficiency >= 0.0 && efficiency <= 1.0)
   {
      multiplier = Adaptive_RegimeBaseMultiplier(regime_label) + Adaptive_EfficiencyAdjustment(efficiency);
   }
   return Adaptive_ClampMultiplier(multiplier, min_multiplier, max_multiplier);
}

double Adaptive_RiskMultiplier(const string regime_label, const double efficiency)
{
   return Adaptive_RiskMultiplierWithBounds(regime_label,
                                            efficiency,
                                            Config_GetAdaptiveRiskMinMult(),
                                            Config_GetAdaptiveRiskMaxMult());
}
#endif // RPEA_ADAPTIVE_MQH
