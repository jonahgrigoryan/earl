#ifndef RPEA_REGIME_MQH
#define RPEA_REGIME_MQH
// regime.mqh - Regime detection API (M7 Phase 5, Task 06)
// References: docs/m7-final-workflow.md (Phase 5, Task 6)

#include <RPEA/indicators.mqh>
#include <RPEA/m7_helpers.mqh>
#include <RPEA/app_context.mqh>

enum REGIME_LABEL
{
   REGIME_UNKNOWN  = 0,
   REGIME_TRENDING = 1,
   REGIME_RANGING  = 2,
   REGIME_VOLATILE = 3
};

int    g_adx_handle = INVALID_HANDLE;
string g_adx_symbol = "";

bool Regime_Init(const string symbol)
{
   if(symbol == "")
      return false;

   if(g_adx_symbol != symbol)
   {
      if(g_adx_handle != INVALID_HANDLE)
         IndicatorRelease(g_adx_handle);
      g_adx_handle = INVALID_HANDLE;
      g_adx_symbol = symbol;
   }

   if(g_adx_handle == INVALID_HANDLE)
      g_adx_handle = iADX(symbol, PERIOD_D1, 14);

   return (g_adx_handle != INVALID_HANDLE);
}

double Regime_GetADX(const string symbol)
{
   if(symbol == "")
      return 0.0;

   if(!Regime_Init(symbol))
      return 0.0;

   double adx_buffer[];
   ArraySetAsSeries(adx_buffer, true);
   if(CopyBuffer(g_adx_handle, 0, 0, 1, adx_buffer) < 1)
      return 0.0;
   if(!MathIsValidNumber(adx_buffer[0]))
      return 0.0;

   return adx_buffer[0];
}

REGIME_LABEL Regime_Detect(const AppContext &ctx, const string symbol)
{
   if(symbol == "")
      return REGIME_UNKNOWN;

   double atr_pct = M7_GetATR_D1_Percentile(ctx, symbol);
   double adx = Regime_GetADX(symbol);

   if(atr_pct > 0.75)
      return REGIME_VOLATILE;

   if(adx > 25.0)
      return REGIME_TRENDING;

   return REGIME_RANGING;
}

string Regime_LabelCtx(const AppContext &ctx, const string symbol)
{
   REGIME_LABEL label = Regime_Detect(ctx, symbol);
   switch(label)
   {
      case REGIME_TRENDING: return "trending";
      case REGIME_RANGING:  return "ranging";
      case REGIME_VOLATILE: return "volatile";
      default: break;
   }
   return "unknown";
}

string Regime_Label(const string symbol)
{
   if(symbol == "")
      return "unknown";
   return Regime_LabelCtx(g_ctx, symbol);
}

void Regime_Features(const string symbol)
{
   if(symbol == "")
      return;
}
#endif // RPEA_REGIME_MQH
