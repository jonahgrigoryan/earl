// test_risk_sizing.mqh
// Unit tests for dynamic risk sizing by confidence (Task 21)

#include <RPEA/risk.mqh>
#include <RPEA/test_reporter.mqh>

bool Test_Risk_Confidence_1_0()
{
   string symbol = "EURUSD";
   if(!SymbolSelect(symbol, true))
   {
      Print(StringFormat("Test_Risk_Confidence_1_0: Failed to select symbol %s", symbol));
      return false;
   }
   double entry = 1.10000;
   double stop = 1.09900; // 100 points distance
   double equity = 100000.0;
   double riskPct = 1.0;
   double confidence = 1.0;

   double volume = Risk_SizingByATRDistanceForSymbol(symbol, entry, stop, equity, riskPct, -1.0, confidence);

   if (volume <= 0.0)
   {
      Print("Test_Risk_Confidence_1_0: Volume is zero");
      return false;
   }

   return true;
}

bool Test_Risk_Confidence_0_5()
{
   string symbol = "EURUSD";
   if(!SymbolSelect(symbol, true))
   {
      Print(StringFormat("Test_Risk_Confidence_0_5: Failed to select symbol %s", symbol));
      return false;
   }
   double entry = 1.10000;
   double stop = 1.09900;
   double equity = 100000.0;
   double riskPct = 1.0;
   double confidence = 0.5;

   double vol_full = Risk_SizingByATRDistanceForSymbol(symbol, entry, stop, equity, riskPct, -1.0, 1.0);
   double vol_half = Risk_SizingByATRDistanceForSymbol(symbol, entry, stop, equity, riskPct, -1.0, confidence);

   if (vol_full <= 0.0) return false;

   double ratio = vol_half / vol_full;
   if (ratio < 0.45 || ratio > 0.55)
   {
      Print(StringFormat("Test_Risk_Confidence_0_5: Ratio %.2f not close to 0.5", ratio));
      return false;
   }

   return true;
}

bool Test_Risk_Confidence_0_0()
{
   string symbol = "EURUSD";
   if(!SymbolSelect(symbol, true))
   {
      Print(StringFormat("Test_Risk_Confidence_0_0: Failed to select symbol %s", symbol));
      return false;
   }
   double entry = 1.10000;
   double stop = 1.09900;
   double equity = 100000.0;
   double riskPct = 1.0;
   double confidence = 0.0;

   double volume = Risk_SizingByATRDistanceForSymbol(symbol, entry, stop, equity, riskPct, -1.0, confidence);

   if (volume > 0.0)
   {
      Print(StringFormat("Test_Risk_Confidence_0_0: Expected 0 volume, got %.2f", volume));
      return false;
   }

   return true;
}

bool Test_Risk_Confidence_NaN()
{
   string symbol = "EURUSD";
   if(!SymbolSelect(symbol, true))
   {
      Print(StringFormat("Test_Risk_Confidence_NaN: Failed to select symbol %s", symbol));
      return false;
   }
   double entry = 1.10000;
   double stop = 1.09900;
   double equity = 100000.0;
   double riskPct = 1.0;
   double zero = 0.0;
   double confidence = 0.0 / zero; // Runtime NaN to avoid constant expression error

   double volume = Risk_SizingByATRDistanceForSymbol(symbol, entry, stop, equity, riskPct, -1.0, confidence);

   if (volume > 0.0)
   {
      Print(StringFormat("Test_Risk_Confidence_NaN: Expected 0 volume, got %.2f", volume));
      return false;
   }

   return true;
}

bool Test_Risk_Confidence_Clamp_High()
{
   string symbol = "EURUSD";
   if(!SymbolSelect(symbol, true))
   {
      Print(StringFormat("Test_Risk_Confidence_Clamp_High: Failed to select symbol %s", symbol));
      return false;
   }
   double entry = 1.10000;
   double stop = 1.09900;
   double equity = 100000.0;
   double riskPct = 1.0;
   double confidence = 1.5;

   double vol_full = Risk_SizingByATRDistanceForSymbol(symbol, entry, stop, equity, riskPct, -1.0, 1.0);
   double vol_high = Risk_SizingByATRDistanceForSymbol(symbol, entry, stop, equity, riskPct, -1.0, confidence);

   if (MathAbs(vol_full - vol_high) > 0.00001)
   {
      Print(StringFormat("Test_Risk_Confidence_Clamp_High: Volume %.2f != Full %.2f", vol_high, vol_full));
      return false;
   }

   return true;
}

bool Test_Risk_Confidence_Clamp_Low()
{
   string symbol = "EURUSD";
   if(!SymbolSelect(symbol, true))
   {
      Print(StringFormat("Test_Risk_Confidence_Clamp_Low: Failed to select symbol %s", symbol));
      return false;
   }
   double entry = 1.10000;
   double stop = 1.09900;
   double equity = 100000.0;
   double riskPct = 1.0;
   double confidence = -0.5;

   double volume = Risk_SizingByATRDistanceForSymbol(symbol, entry, stop, equity, riskPct, -1.0, confidence);

   if (volume > 0.0)
   {
      Print(StringFormat("Test_Risk_Confidence_Clamp_Low: Expected 0 volume, got %.2f", volume));
      return false;
   }

   return true;
}

bool Test_Risk_Default()
{
   string symbol = "EURUSD";
   if(!SymbolSelect(symbol, true))
   {
      Print(StringFormat("Test_Risk_Default: Failed to select symbol %s", symbol));
      return false;
   }
   double entry = 1.10000;
   double stop = 1.09900;
   double equity = 100000.0;
   double riskPct = 1.0;

   double vol_def = Risk_SizingByATRDistanceForSymbol(symbol, entry, stop, equity, riskPct);
   double vol_expl = Risk_SizingByATRDistanceForSymbol(symbol, entry, stop, equity, riskPct, -1.0, 1.0);

   if (MathAbs(vol_def - vol_expl) > 0.00001)
   {
      Print("Test_Risk_Default: Default param behavior mismatch");
      return false;
   }

   return true;
}

bool TestRiskSizing_RunAll()
{
   bool res = true;
   res &= Test_Risk_Confidence_1_0();
   res &= Test_Risk_Confidence_0_5();
   res &= Test_Risk_Confidence_0_0();
   res &= Test_Risk_Confidence_NaN();
   res &= Test_Risk_Confidence_Clamp_High();
   res &= Test_Risk_Confidence_Clamp_Low();
   res &= Test_Risk_Default();
   return res;
}
