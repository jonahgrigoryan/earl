#pragma once
// risk.mqh - Risk sizing helpers (M1 stubs)
// References: finalspec.md (Sizing by ATR distance)

double Risk_SizingByATRDistance(const double entry, const double stop,
                                const double equity, const double riskPct)
{
   // Placeholder: avoid divide-by-zero
   double dist = MathAbs(entry - stop);
   if(dist <= 0.0) return 0.0;
   double risk_money = equity * (riskPct/100.0);
   // Assume 1 currency unit per point for placeholder
   double value_per_point = 1.0;
   double points = dist / _Point;
   if(points <= 0.0) return 0.0;
   double raw_volume = risk_money / (points * value_per_point);
   if(raw_volume < 0.0) raw_volume = 0.0;
   return raw_volume;
   // TODO[M2]: full sizing and margin guard per spec
}
