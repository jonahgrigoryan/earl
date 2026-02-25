#ifndef RPEA_ANOMALY_MQH
#define RPEA_ANOMALY_MQH
// anomaly.mqh - EWMA shock detector (returns/spread/tick-gap)
// References: finalspec.md (Anomaly/Shock Detector)

#include <RPEA/config.mqh>

#define ANOMALY_SYMBOL_CAP 32
#define ANOMALY_EPSILON    1e-9

enum AnomalyAction
{
   ANOMALY_ACTION_NONE = 0,
   ANOMALY_ACTION_WIDEN = 1,
   ANOMALY_ACTION_CANCEL = 2,
   ANOMALY_ACTION_FLATTEN = 3
};

struct AnomalySnapshot
{
   bool          valid_input;
   bool          shock;
   int           sample_count;
   double        threshold_sigma;
   double        score_sigma;
   double        return_z;
   double        spread_z;
   double        tick_gap_z;
   double        return_value;
   double        spread_points;
   double        tick_gap_seconds;
   AnomalyAction action;
   string        reason;
};

struct AnomalyState
{
   string symbol;
   bool   initialized;
   int    sample_count;
   double last_mid_price;
   long   last_tick_time_msc;

   double ewma_return_mean;
   double ewma_return_var;
   double ewma_spread_mean;
   double ewma_spread_var;
   double ewma_tick_gap_mean;
   double ewma_tick_gap_var;

   bool            has_snapshot;
   AnomalySnapshot last_snapshot;
};

AnomalyState g_anomaly_states[ANOMALY_SYMBOL_CAP];
bool g_anomaly_state_ready = false;

void Anomaly_ResetSnapshot(AnomalySnapshot &snapshot)
{
   snapshot.valid_input = false;
   snapshot.shock = false;
   snapshot.sample_count = 0;
   snapshot.threshold_sigma = Config_GetAnomalyShockSigmaThreshold();
   snapshot.score_sigma = 0.0;
   snapshot.return_z = 0.0;
   snapshot.spread_z = 0.0;
   snapshot.tick_gap_z = 0.0;
   snapshot.return_value = 0.0;
   snapshot.spread_points = 0.0;
   snapshot.tick_gap_seconds = 0.0;
   snapshot.action = ANOMALY_ACTION_NONE;
   snapshot.reason = "";
}

void Anomaly_ResetStateSlot(const int idx)
{
   g_anomaly_states[idx].symbol = "";
   g_anomaly_states[idx].initialized = false;
   g_anomaly_states[idx].sample_count = 0;
   g_anomaly_states[idx].last_mid_price = 0.0;
   g_anomaly_states[idx].last_tick_time_msc = 0;

   g_anomaly_states[idx].ewma_return_mean = 0.0;
   g_anomaly_states[idx].ewma_return_var = ANOMALY_EPSILON;
   g_anomaly_states[idx].ewma_spread_mean = 0.0;
   g_anomaly_states[idx].ewma_spread_var = ANOMALY_EPSILON;
   g_anomaly_states[idx].ewma_tick_gap_mean = 0.0;
   g_anomaly_states[idx].ewma_tick_gap_var = ANOMALY_EPSILON;

   g_anomaly_states[idx].has_snapshot = false;
   Anomaly_ResetSnapshot(g_anomaly_states[idx].last_snapshot);
}

void Anomaly_EnsureState()
{
   if(g_anomaly_state_ready)
      return;

   for(int i = 0; i < ANOMALY_SYMBOL_CAP; i++)
      Anomaly_ResetStateSlot(i);
   g_anomaly_state_ready = true;
}

int Anomaly_FindSlot(const string symbol, const bool create_if_missing)
{
   Anomaly_EnsureState();

   for(int i = 0; i < ANOMALY_SYMBOL_CAP; i++)
   {
      if(StringCompare(g_anomaly_states[i].symbol, symbol) == 0)
         return i;
   }

   if(!create_if_missing)
      return -1;

   for(int i = 0; i < ANOMALY_SYMBOL_CAP; i++)
   {
      if(StringLen(g_anomaly_states[i].symbol) == 0)
      {
         Anomaly_ResetStateSlot(i);
         g_anomaly_states[i].symbol = symbol;
         return i;
      }
   }
   return -1;
}

bool Anomaly_IsFinite(const double value)
{
   return MathIsValidNumber(value);
}

double Anomaly_ClampAlpha(const double alpha)
{
   double value = alpha;
   if(!Anomaly_IsFinite(value))
      value = DEFAULT_AnomalyEWMAAlpha;
   if(value < 0.01)
      value = 0.01;
   if(value > 1.0)
      value = 1.0;
   return value;
}

double Anomaly_AbsZScore(const double value, const double mean, const double variance)
{
   if(!Anomaly_IsFinite(value) ||
      !Anomaly_IsFinite(mean) ||
      !Anomaly_IsFinite(variance) ||
      variance < ANOMALY_EPSILON)
      return 0.0;

   double std_dev = MathSqrt(variance);
   if(!Anomaly_IsFinite(std_dev) || std_dev <= ANOMALY_EPSILON)
      return 0.0;

   double z = MathAbs(value - mean) / std_dev;
   if(!Anomaly_IsFinite(z))
      return 0.0;
   return z;
}

void Anomaly_UpdateEWMA(const double value, const double alpha, double &mean, double &variance)
{
   double delta = value - mean;
   mean = (alpha * value) + ((1.0 - alpha) * mean);
   variance = (alpha * delta * delta) + ((1.0 - alpha) * variance);

   if(!Anomaly_IsFinite(variance) || variance < ANOMALY_EPSILON)
      variance = ANOMALY_EPSILON;
}

AnomalyAction Anomaly_SelectAction(const double score_sigma, const double threshold_sigma)
{
   if(!Anomaly_IsFinite(score_sigma) || !Anomaly_IsFinite(threshold_sigma))
      return ANOMALY_ACTION_NONE;

   if(score_sigma < threshold_sigma)
      return ANOMALY_ACTION_NONE;
   if(score_sigma >= (threshold_sigma + 1.0))
      return ANOMALY_ACTION_FLATTEN;
   if(score_sigma >= (threshold_sigma + 0.5))
      return ANOMALY_ACTION_CANCEL;
   return ANOMALY_ACTION_WIDEN;
}

string Anomaly_ActionToString(const AnomalyAction action)
{
   switch(action)
   {
      case ANOMALY_ACTION_WIDEN:   return "widen";
      case ANOMALY_ACTION_CANCEL:  return "cancel";
      case ANOMALY_ACTION_FLATTEN: return "flatten";
      default:                     return "none";
   }
}

bool Anomaly_EvaluateSample(const string symbol,
                            const double mid_price,
                            const double spread_points,
                            const double tick_gap_seconds,
                            AnomalySnapshot &snapshot)
{
   Anomaly_ResetSnapshot(snapshot);

   if(StringLen(symbol) == 0)
   {
      snapshot.reason = "invalid_symbol";
      return false;
   }

   if(!Config_GetEnableAnomalyDetector())
   {
      snapshot.reason = "detector_disabled";
      snapshot.valid_input = true;
      return true;
   }

   if(!Anomaly_IsFinite(mid_price) ||
      !Anomaly_IsFinite(spread_points) ||
      !Anomaly_IsFinite(tick_gap_seconds) ||
      mid_price <= 0.0 ||
      spread_points < 0.0 ||
      tick_gap_seconds < 0.0)
   {
      snapshot.reason = "invalid_sample";
      return false;
   }

   int idx = Anomaly_FindSlot(symbol, true);
   if(idx < 0)
   {
      snapshot.reason = "state_capacity_reached";
      return false;
   }

   int min_samples = Config_GetAnomalyMinSamples();
   if(min_samples < 1)
      min_samples = 1;
   double alpha = Anomaly_ClampAlpha(Config_GetAnomalyEWMAAlpha());

   double return_value = 0.0;
   if(g_anomaly_states[idx].initialized && g_anomaly_states[idx].last_mid_price > ANOMALY_EPSILON)
      return_value = (mid_price - g_anomaly_states[idx].last_mid_price) / g_anomaly_states[idx].last_mid_price;

   snapshot.valid_input = true;
   snapshot.return_value = return_value;
   snapshot.spread_points = spread_points;
   snapshot.tick_gap_seconds = tick_gap_seconds;

   if(!g_anomaly_states[idx].initialized)
   {
      g_anomaly_states[idx].initialized = true;
      g_anomaly_states[idx].sample_count = 1;
      g_anomaly_states[idx].last_mid_price = mid_price;
      g_anomaly_states[idx].ewma_return_mean = return_value;
      g_anomaly_states[idx].ewma_return_var = ANOMALY_EPSILON;
      g_anomaly_states[idx].ewma_spread_mean = spread_points;
      g_anomaly_states[idx].ewma_spread_var = ANOMALY_EPSILON;
      g_anomaly_states[idx].ewma_tick_gap_mean = tick_gap_seconds;
      g_anomaly_states[idx].ewma_tick_gap_var = ANOMALY_EPSILON;

      snapshot.sample_count = g_anomaly_states[idx].sample_count;
      snapshot.reason = "insufficient_samples";
      snapshot.action = ANOMALY_ACTION_NONE;
      g_anomaly_states[idx].last_snapshot = snapshot;
      g_anomaly_states[idx].has_snapshot = true;
      return true;
   }

   snapshot.return_z = Anomaly_AbsZScore(return_value,
                                         g_anomaly_states[idx].ewma_return_mean,
                                         g_anomaly_states[idx].ewma_return_var);
   snapshot.spread_z = Anomaly_AbsZScore(spread_points,
                                         g_anomaly_states[idx].ewma_spread_mean,
                                         g_anomaly_states[idx].ewma_spread_var);
   snapshot.tick_gap_z = Anomaly_AbsZScore(tick_gap_seconds,
                                           g_anomaly_states[idx].ewma_tick_gap_mean,
                                           g_anomaly_states[idx].ewma_tick_gap_var);
   snapshot.score_sigma = MathMax(snapshot.return_z, MathMax(snapshot.spread_z, snapshot.tick_gap_z));

   g_anomaly_states[idx].sample_count++;
   snapshot.sample_count = g_anomaly_states[idx].sample_count;

   if(g_anomaly_states[idx].sample_count < min_samples)
   {
      snapshot.shock = false;
      snapshot.action = ANOMALY_ACTION_NONE;
      snapshot.reason = "insufficient_samples";
   }
   else
   {
      snapshot.shock = (snapshot.score_sigma >= snapshot.threshold_sigma);
      snapshot.action = Anomaly_SelectAction(snapshot.score_sigma, snapshot.threshold_sigma);
      snapshot.reason = snapshot.shock ? "shock" : "no_shock";
   }

   Anomaly_UpdateEWMA(return_value,
                      alpha,
                      g_anomaly_states[idx].ewma_return_mean,
                      g_anomaly_states[idx].ewma_return_var);
   Anomaly_UpdateEWMA(spread_points,
                      alpha,
                      g_anomaly_states[idx].ewma_spread_mean,
                      g_anomaly_states[idx].ewma_spread_var);
   Anomaly_UpdateEWMA(tick_gap_seconds,
                      alpha,
                      g_anomaly_states[idx].ewma_tick_gap_mean,
                      g_anomaly_states[idx].ewma_tick_gap_var);
   g_anomaly_states[idx].last_mid_price = mid_price;

   g_anomaly_states[idx].last_snapshot = snapshot;
   g_anomaly_states[idx].has_snapshot = true;
   return true;
}

bool Anomaly_EvaluateSymbol(const string symbol, AnomalySnapshot &snapshot)
{
   Anomaly_ResetSnapshot(snapshot);

   if(StringLen(symbol) == 0)
   {
      snapshot.reason = "invalid_symbol";
      return false;
   }

   if(!Config_GetEnableAnomalyDetector())
   {
      snapshot.reason = "detector_disabled";
      snapshot.valid_input = true;
      return true;
   }

   int idx = Anomaly_FindSlot(symbol, true);
   if(idx < 0)
   {
      snapshot.reason = "state_capacity_reached";
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      snapshot.reason = "tick_unavailable";
      return false;
   }

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(!Anomaly_IsFinite(point) || point <= 0.0)
   {
      snapshot.reason = "invalid_point";
      return false;
   }

   double bid = tick.bid;
   double ask = tick.ask;
   if(!Anomaly_IsFinite(bid) || !Anomaly_IsFinite(ask) || bid <= 0.0 || ask <= 0.0 || ask < bid)
   {
      snapshot.reason = "invalid_tick";
      return false;
   }

   double mid_price = 0.5 * (bid + ask);
   double spread_points = (ask - bid) / point;
   double gap_seconds = 0.0;

   long tick_time_msc = (long)tick.time_msc;
   long previous_tick_msc = g_anomaly_states[idx].last_tick_time_msc;
   if(previous_tick_msc > 0 && tick_time_msc > previous_tick_msc)
      gap_seconds = (double)(tick_time_msc - previous_tick_msc) / 1000.0;

   bool ok = Anomaly_EvaluateSample(symbol, mid_price, spread_points, gap_seconds, snapshot);
   if(ok)
      g_anomaly_states[idx].last_tick_time_msc = tick_time_msc;
   return ok;
}

bool Anomaly_GetLastSnapshot(const string symbol, AnomalySnapshot &snapshot)
{
   Anomaly_ResetSnapshot(snapshot);
   int idx = Anomaly_FindSlot(symbol, false);
   if(idx < 0 || !g_anomaly_states[idx].has_snapshot)
      return false;
   snapshot = g_anomaly_states[idx].last_snapshot;
   return true;
}

bool Anomaly_IsShockNow(const string symbol)
{
   AnomalySnapshot snapshot;
   bool ok = Anomaly_EvaluateSymbol(symbol, snapshot);
   if(!ok)
      return false;
   return snapshot.shock;
}

bool Anomaly_ShouldRunActiveMode()
{
   if(!Config_GetEnableAnomalyDetector())
      return false;
   return !Config_GetAnomalyShadowMode();
}

#ifdef RPEA_TEST_RUNNER
void Anomaly_TestResetState()
{
   g_anomaly_state_ready = false;
   Anomaly_EnsureState();
}

bool Anomaly_TestEvaluateSample(const string symbol,
                                const double mid_price,
                                const double spread_points,
                                const double tick_gap_seconds,
                                AnomalySnapshot &snapshot)
{
   return Anomaly_EvaluateSample(symbol, mid_price, spread_points, tick_gap_seconds, snapshot);
}

AnomalyAction Anomaly_TestSelectAction(const double score_sigma, const double threshold_sigma)
{
   return Anomaly_SelectAction(score_sigma, threshold_sigma);
}
#endif

#endif // RPEA_ANOMALY_MQH
