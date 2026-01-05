#ifndef RPEA_SYMBOL_BRIDGE_MQH
#define RPEA_SYMBOL_BRIDGE_MQH
// symbol_bridge.mqh - XAUEUR proxy helpers (Task 15)
// Provides lightweight mapping utilities used by allocator/order engine

#include <RPEA/logging.mqh>

// Performance: EURUSD rate cache with 500ms TTL
struct SymbolRateCache
{
   double rate;
   ulong timestamp_ms;
};
static SymbolRateCache g_eurusd_cache = {0.0, 0};
const ulong CACHE_TTL_MS = 500;

// Normalize: Uppercase/trim for robust symbol comparisons
string SymbolBridge_Normalize(const string symbol)
  {
   string value = symbol;
   StringToUpper(value);
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
  }

string SymbolBridge_GetExecutionSymbol(const string signal_symbol)
  {
   const string normalized = SymbolBridge_Normalize(signal_symbol);
   if(normalized == "XAUEUR")
      return "XAUUSD";
   return signal_symbol;
  }

// MapDistance: Returns false (and sets out_distance_exec < 0) if EURUSD quote is unavailable
bool SymbolBridge_MapDistance(const string signal_symbol,
                              const string exec_symbol,
                              const double distance_signal,
                              double &out_distance_exec,
                              double &out_eurusd_rate)
  {
   out_distance_exec = distance_signal;
   out_eurusd_rate = 1.0;

   if(distance_signal <= 0.0)
      return true;

   const string normalized = SymbolBridge_Normalize(signal_symbol);
   if(normalized != "XAUEUR")
      return true;

   double bid = 0.0;
   
   // Performance: Use cached EURUSD rate with TTL
   ulong now = GetTickCount64();
   if(now - g_eurusd_cache.timestamp_ms < CACHE_TTL_MS && g_eurusd_cache.rate > 0.0)
   {
      bid = g_eurusd_cache.rate; // Use cached rate
   }
   else
   {
      // Fetch fresh rate and cache it
      if(!SymbolInfoDouble("EURUSD", SYMBOL_BID, bid) ||
         !MathIsValidNumber(bid) ||
         bid <= 0.0)
      {
         out_distance_exec = -1.0;
         out_eurusd_rate = 0.0;
         LogDecision("SymbolBridge",
                     "XAUEUR_MAP_FAIL",
                     StringFormat("{\"signal\":\"%s\",\"exec\":\"%s\",\"reason\":\"eurusd_quote\"}",
                                  signal_symbol,
                                  exec_symbol));
         return false;
      }
      
      // Update cache
      g_eurusd_cache.rate = bid;
      g_eurusd_cache.timestamp_ms = now;
   }

   out_eurusd_rate = bid;
   out_distance_exec = distance_signal * bid;

   LogDecision("SymbolBridge",
               "XAUEUR_MAP",
               StringFormat("{\"signal\":\"%s\",\"exec\":\"%s\",\"distance_signal\":%.4f,\"distance_exec\":%.4f,\"eurusd\":%.5f}",
                            signal_symbol,
                            exec_symbol,
                            distance_signal,
                            out_distance_exec,
                            bid));
   return true;
  }

#endif // RPEA_SYMBOL_BRIDGE_MQH
