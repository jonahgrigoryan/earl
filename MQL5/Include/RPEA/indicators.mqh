#ifndef INDICATORS_MQH
#define INDICATORS_MQH
// indicators.mqh - Indicator handles and init (M1 stubs)
// References: finalspec.md (Session Statistics)

struct AppContext;

struct IndicatorsContext
{
   int handle_ATR_D1;
   int handle_MA20_H1;
   int handle_RSI_H1;
};

// Initialize indicator handles (placeholders)
void Indicators_Init(const AppContext& ctx)
{
   // TODO[M2]: create real handles, error handling
}

// Refresh per-symbol derived stats (placeholders)
void Indicators_Refresh(const AppContext& ctx, const string symbol)
{
   // TODO[M2]: compute OR, ATR, RSI; handle errors
}

#endif // INDICATORS_MQH
