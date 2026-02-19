#ifndef RPEA_EMRT_MQH
#define RPEA_EMRT_MQH
// emrt.mqh - EMRT formation and cache IO (M7 Phase 1)
// References: docs/m7-final-workflow.md (Phase 1, Task 1)

#include <RPEA/config.mqh>
#include <RPEA/persistence.mqh>

struct EMRT_Cache
{
   double   beta_star;      // Optimal hedge ratio
   double   rank;           // Percentile vs lookback [0.0-1.0]
   double   p50_minutes;    // 50th percentile reversion time
   datetime last_refresh;
   string   symbol;
};

EMRT_Cache g_emrt_cache;
bool       g_emrt_loaded = false;

double EMRT_CalcMean(const double &values[])
{
   int size = ArraySize(values);
   if(size <= 0)
      return 0.0;
   double sum = 0.0;
   for(int i = 0; i < size; i++)
      sum += values[i];
   return sum / (double)size;
}

double EMRT_CalcVariance(const double &values[], const double mean)
{
   int size = ArraySize(values);
   if(size <= 1)
      return 0.0;
   double sum = 0.0;
   for(int i = 0; i < size; i++)
   {
      double diff = values[i] - mean;
      sum += diff * diff;
   }
   return sum / (double)size;
}

double EMRT_CalcStdDev(const double &values[], const double mean)
{
   double variance = EMRT_CalcVariance(values, mean);
   if(variance <= 0.0 || !MathIsValidNumber(variance))
      return 0.0;
   return MathSqrt(variance);
}

double EMRT_CalcMedian(const double &values[])
{
   int size = ArraySize(values);
   if(size <= 0)
      return 0.0;
   double sorted[];
   ArrayResize(sorted, size);
   ArrayCopy(sorted, values, 0, 0, size);
   ArraySort(sorted);
   int mid = size / 2;
   if((size % 2) == 1)
      return sorted[mid];
   return (sorted[mid - 1] + sorted[mid]) / 2.0;
}

double EMRT_CalcRank(const double &values[], const double p50)
{
   int size = ArraySize(values);
   if(size <= 0)
      return 0.5;

   // True percentile: count values <= p50 (Finding #4 patch)
   int count_below = 0;
   for(int i = 0; i < size; i++)
   {
      if(values[i] <= p50)
         count_below++;
   }

   double percentile = (double)count_below / (double)size;

   // Invert: lower EMRT = faster reversion = higher rank
   double rank = 1.0 - percentile;
   if(rank < 0.0) rank = 0.0;
   if(rank > 1.0) rank = 1.0;
   return rank;
}

bool EMRT_LoadCache(const string path)
{
   g_emrt_loaded = false;
   if(path == NULL || path == "")
      return false;
   if(!FileIsExist(path))
      return false;
   string contents = Persistence_ReadWholeFile(path);
   if(StringLen(contents) == 0)
      return false;

   EMRT_Cache cache;
   ZeroMemory(cache);
   double num_value = 0.0;
   string str_value = "";
   bool ok = true;

   if(Persistence_ParseNumberField(contents, "beta_star", num_value))
      cache.beta_star = num_value;
   else
      ok = false;

   if(Persistence_ParseNumberField(contents, "rank", num_value))
      cache.rank = num_value;
   else
      ok = false;

   if(Persistence_ParseNumberField(contents, "p50_minutes", num_value))
      cache.p50_minutes = num_value;
   else
      ok = false;

   if(Persistence_ParseStringField(contents, "last_refresh", str_value))
      cache.last_refresh = Persistence_ParseIso8601(str_value);
   else
      ok = false;

   if(Persistence_ParseStringField(contents, "symbol", str_value))
      cache.symbol = str_value;
   else
      ok = false;

   if(!ok)
      return false;

   g_emrt_cache = cache;
   g_emrt_loaded = true;
   return true;
}

bool EMRT_SaveCache(const string path)
{
   if(path == NULL || path == "")
      return false;

   FolderCreate(RPEA_DIR);
   FolderCreate(RPEA_EMRT_DIR);

   string json = "{";
   json += "\"beta_star\":" + DoubleToString(g_emrt_cache.beta_star, 6) + ",";
   json += "\"rank\":" + DoubleToString(g_emrt_cache.rank, 6) + ",";
   json += "\"p50_minutes\":" + DoubleToString(g_emrt_cache.p50_minutes, 2) + ",";
   string refresh = Persistence_FormatIso8601(g_emrt_cache.last_refresh);
   json += "\"last_refresh\":\"" + Persistence_EscapeJson(refresh) + "\",";
   json += "\"symbol\":\"" + Persistence_EscapeJson(g_emrt_cache.symbol) + "\"";
   json += "}";

   if(!Persistence_WriteWholeFile(path, json))
      return false;

   return true;
}

void EMRT_BuildSyntheticSpread(
   const double &xauusd_close[],
   const double &eurusd_close[],
   double beta,
   double &spread[]
)
{
   int len = MathMin(ArraySize(xauusd_close), ArraySize(eurusd_close));
   if(len <= 0)
   {
      ArrayResize(spread, 0);
      return;
   }
   ArrayResize(spread, len);
   for(int i = 0; i < len; i++)
   {
      if(MR_UseLogRatio)
      {
         if(xauusd_close[i] <= 0.0 || eurusd_close[i] <= 0.0)
         {
            spread[i] = 0.0;
            continue;
         }
         spread[i] = MathLog(xauusd_close[i]) - MathLog(eurusd_close[i]);
      }
      else
      {
         spread[i] = xauusd_close[i] - beta * eurusd_close[i];
      }
   }
}

// Helper: compute rolling mean at position idx using window of size win
double EMRT_RollingMean(const double &arr[], int idx, int win)
{
   int start = idx - win;
   if(start < 0) start = 0;
   int count = idx - start;
   if(count <= 0) return arr[idx];
   double sum = 0.0;
   for(int k = start; k < idx; k++)
      sum += arr[k];
   return sum / (double)count;
}

void EMRT_FindCrossingTimes(
   const double &spread[],
   double threshold_mult,
   double &crossing_times[]
)
{
   ArrayResize(crossing_times, 0);
   int size = ArraySize(spread);
   if(size < 5)
      return;

   // Rolling mean window: 60 M1 bars (1 hour) per spec "rolling mean Ȳ_t" (Finding #1)
   const int ROLLING_WINDOW = 60;

   // Use global sigma for threshold (spec: C = threshold_mult · σ_Y)
   double global_mean = EMRT_CalcMean(spread);
   double sigma = EMRT_CalcStdDev(spread, global_mean);
   if(sigma <= 0.0 || !MathIsValidNumber(sigma))
      return;

   double threshold = threshold_mult * sigma;
   if(threshold <= 0.0)
      return;

   // Precompute rolling means for efficiency
   double rolling_means[];
   ArrayResize(rolling_means, size);
   for(int k = 0; k < size; k++)
      rolling_means[k] = EMRT_RollingMean(spread, k, ROLLING_WINDOW);

   // Start after enough data for meaningful rolling mean
   int start_idx = MathMin(ROLLING_WINDOW, size / 4);
   int i = MathMax(1, start_idx);

   while(i < size - 1)
   {
      double rolling_mean_i = rolling_means[i];
      double delta = spread[i] - rolling_mean_i;
      if(MathAbs(delta) <= threshold)
      {
         i++;
         continue;
      }

      bool is_peak = (spread[i] > spread[i - 1] && spread[i] > spread[i + 1]);
      bool is_trough = (spread[i] < spread[i - 1] && spread[i] < spread[i + 1]);
      if(!is_peak && !is_trough)
      {
         i++;
         continue;
      }

      bool above_mean = (delta > 0.0);
      int j = i + 1;
      bool crossed = false;
      while(j < size)
      {
         double rolling_mean_j = rolling_means[j];
         double current_delta = spread[j] - rolling_mean_j;
         if((above_mean && current_delta <= 0.0) || (!above_mean && current_delta >= 0.0))
         {
            int idx = ArraySize(crossing_times);
            ArrayResize(crossing_times, idx + 1);
            crossing_times[idx] = (double)(j - i);
            i = j;
            crossed = true;
            break;
         }
         j++;
      }
      if(!crossed)
         break;
      i++;
   }
}

void EMRT_RefreshWeekly()
{
   if(!UseXAUEURProxy)
   {
      Print("[EMRT] WARNING: UseXAUEURProxy=false, EMRT refresh skipped (proxy-only in M7)");
      return;
   }

   const string xau_symbol = "XAUUSD";
   const string eur_symbol = "EURUSD";
   int lookback_days = 90;
   int bars_to_copy = lookback_days * 24 * 60;

   double xau_close[];
   double eur_close[];
   ArraySetAsSeries(xau_close, false);
   ArraySetAsSeries(eur_close, false);

   int copied_xau = CopyClose(xau_symbol, PERIOD_M1, 0, bars_to_copy, xau_close);
   int copied_eur = CopyClose(eur_symbol, PERIOD_M1, 0, bars_to_copy, eur_close);
   if(copied_xau <= 0 || copied_eur <= 0)
   {
      PrintFormat("[EMRT] ERROR: CopyClose failed (XAU=%d, EUR=%d)", copied_xau, copied_eur);
      return;
   }

   int len = MathMin(copied_xau, copied_eur);
   if(len < 120)
   {
      PrintFormat("[EMRT] WARNING: insufficient history for EMRT (%d bars)", len);
      return;
   }
   ArrayResize(xau_close, len);
   ArrayResize(eur_close, len);

   // Compute reference spread variance at beta=1.0 for variance cap baseline (Finding #2)
   // Spec: "S²(Y) ≤ EMRT_VarCapMult · Var(Y)" - use beta=1.0 spread as reference
   double ref_spread[];
   EMRT_BuildSyntheticSpread(xau_close, eur_close, 1.0, ref_spread);
   double ref_spread_mean = EMRT_CalcMean(ref_spread);
   double ref_var = EMRT_CalcVariance(ref_spread, ref_spread_mean);
   if(ref_var <= 0.0 || !MathIsValidNumber(ref_var))
      ref_var = 1.0;

   bool found = false;
   double best_beta = 0.0;
   double best_p50 = 0.0;
   double best_rank = 0.5;
   double best_emrt_mean = 0.0;  // Finding #3: track mean EMRT for beta selection

   if(MR_UseLogRatio)
   {
      // In log-ratio mode, ref_spread is already the log-ratio spread
      double crossing_times[];
      EMRT_FindCrossingTimes(ref_spread, EMRT_ExtremeThresholdMult, crossing_times);
      if(ArraySize(crossing_times) == 0)
      {
         Print("[EMRT] WARNING: no extrema found in log-ratio mode");
         return;
      }
      // Finding #3: calculate both mean (for EMRT definition) and median (for hold time)
      best_emrt_mean = EMRT_CalcMean(crossing_times);
      best_p50 = EMRT_CalcMedian(crossing_times);
      best_rank = EMRT_CalcRank(crossing_times, best_p50);
      best_beta = 1.0;
      found = true;
   }
   else
   {
      for(double beta = EMRT_BetaGridMin; beta <= EMRT_BetaGridMax + 1e-9; beta += 0.1)
      {
         double spread[];
         EMRT_BuildSyntheticSpread(xau_close, eur_close, beta, spread);
         double spread_mean = EMRT_CalcMean(spread);
         double spread_var = EMRT_CalcVariance(spread, spread_mean);
         // Variance cap on spread Y: S²(Y) ≤ EMRT_VarCapMult · Var(Y_ref) (Finding #2)
         // Reference variance is from beta=1.0 spread computed above
         if(spread_var > EMRT_VarCapMult * ref_var)
            continue;

         double crossing_times[];
         EMRT_FindCrossingTimes(spread, EMRT_ExtremeThresholdMult, crossing_times);
         if(ArraySize(crossing_times) == 0)
            continue;

         // Finding #3: select beta by minimizing mean EMRT (spec: "EMRT = mean(Δt)")
         double emrt_mean = EMRT_CalcMean(crossing_times);
         double p50 = EMRT_CalcMedian(crossing_times);
         if(!found || emrt_mean < best_emrt_mean)
         {
            best_emrt_mean = emrt_mean;
            best_p50 = p50;
            best_rank = EMRT_CalcRank(crossing_times, p50);
            best_beta = beta;
            found = true;
         }
      }
   }

   if(!found)
   {
      Print("[EMRT] WARNING: no valid beta candidate found");
      return;
   }

   g_emrt_cache.beta_star = best_beta;
   g_emrt_cache.rank = best_rank;
   g_emrt_cache.p50_minutes = best_p50;
   g_emrt_cache.last_refresh = TimeCurrent();
   g_emrt_cache.symbol = "XAUEUR";
   g_emrt_loaded = true;

   if(!EMRT_SaveCache(FILE_EMRT_CACHE))
      Print("[EMRT] WARNING: failed to save EMRT cache");
}

double EMRT_GetRank(string sym)
{
   if(sym == "") {/* no-op */}
   if(!g_emrt_loaded)
      return 0.5;
   return g_emrt_cache.rank;
}

double EMRT_GetP50(string sym)
{
   if(sym == "") {/* no-op */}
   if(!g_emrt_loaded)
      return 75.0;
   return g_emrt_cache.p50_minutes;
}

double EMRT_GetBeta(string sym)
{
   if(sym == "") {/* no-op */}
   if(!g_emrt_loaded)
   {
      if(MR_UseLogRatio)
         return 1.0;
      return 0.0;
   }
   return g_emrt_cache.beta_star;
}

#endif // RPEA_EMRT_MQH
