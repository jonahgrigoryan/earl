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

bool Test_Risk_Diagnostics_BelowMinAfterStep()
{
   string symbol = "EURUSD";
   if(!SymbolSelect(symbol, true))
   {
      Print(StringFormat("Test_Risk_Diagnostics_BelowMinAfterStep: Failed to select symbol %s", symbol));
      return false;
   }

   Risk_ResetLastSizingDiagnostics();

   double entry = 1.10000;
   double stop = 1.00000;
   double equity = 1000.0;
   double riskPct = 0.0001;
   double confidence = 1.0;

   double volume = Risk_SizingByATRDistanceForSymbol(symbol, entry, stop, equity, riskPct, -1.0, confidence);

   if(volume > 0.0)
   {
      Print(StringFormat("Test_Risk_Diagnostics_BelowMinAfterStep: Expected zero volume, got %.8f", volume));
      return false;
   }
   if(!g_last_risk_sizing_diagnostics.initialized)
   {
      Print("Test_Risk_Diagnostics_BelowMinAfterStep: Diagnostics not initialized");
      return false;
   }
   if(g_last_risk_sizing_diagnostics.volume_min <= 0.0)
   {
      Print("Test_Risk_Diagnostics_BelowMinAfterStep: volume_min missing");
      return false;
   }
   if(g_last_risk_sizing_diagnostics.raw_volume <= 0.0)
   {
      Print("Test_Risk_Diagnostics_BelowMinAfterStep: raw_volume missing");
      return false;
   }
   if(g_last_risk_sizing_diagnostics.raw_volume >= g_last_risk_sizing_diagnostics.volume_min)
   {
      Print(StringFormat(
         "Test_Risk_Diagnostics_BelowMinAfterStep: raw_volume %.8f not below volume_min %.8f",
         g_last_risk_sizing_diagnostics.raw_volume,
         g_last_risk_sizing_diagnostics.volume_min));
      return false;
   }
   if(g_last_risk_sizing_diagnostics.volume_zero_subcause != "below_min_after_step")
   {
      Print(StringFormat(
         "Test_Risk_Diagnostics_BelowMinAfterStep: Expected below_min_after_step, got %s",
         g_last_risk_sizing_diagnostics.volume_zero_subcause));
      return false;
   }
   if(g_last_risk_sizing_diagnostics.volume_zero_gap_to_min_lot_frac <= 0.0)
   {
      Print("Test_Risk_Diagnostics_BelowMinAfterStep: gap_to_min_lot_frac not positive");
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
    res &= Test_Risk_Diagnostics_BelowMinAfterStep();
   return res;
}
