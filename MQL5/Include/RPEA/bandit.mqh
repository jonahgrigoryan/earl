#ifndef RPEA_BANDIT_MQH
#define RPEA_BANDIT_MQH
// bandit.mqh - Contextual bandit runtime (Post-M7 Phase 4)
// References: finalspec.md (Contextual Bandit Meta-Policy)

#include <RPEA/app_context.mqh>
#include <RPEA/config.mqh>
#include <RPEA/liquidity.mqh>
#include <RPEA/regime.mqh>
#include <RPEA/telemetry.mqh>

enum BanditPolicy { Bandit_Skip=0, Bandit_BWISC=1, Bandit_MR=2 };

#define BANDIT_POSTERIOR_SCHEMA_VERSION  1
#define BANDIT_POSTERIOR_MIN_UPDATES     6
#define BANDIT_PRIOR_MEAN                0.50
#define BANDIT_PRIOR_WEIGHT              2.0
#define BANDIT_MIN_ACTION_SCORE          0.40

struct BanditPosteriorState
{
   bool     initialized;
   bool     loaded_from_file;
   bool     ready;
   int      schema_version;
   int      total_updates;
   int      bwisc_pulls;
   int      mr_pulls;
   double   bwisc_reward_sum;
   double   mr_reward_sum;
   datetime updated_at;
};

BanditPosteriorState g_bandit_posterior;

#ifdef RPEA_TEST_RUNNER
bool         g_bandit_test_force_policy_active = false;
BanditPolicy g_bandit_test_force_policy = Bandit_Skip;
#endif

void Bandit_ResetPosteriorDefaults(BanditPosteriorState &state)
{
   state.initialized = true;
   state.loaded_from_file = false;
   state.ready = false;
   state.schema_version = BANDIT_POSTERIOR_SCHEMA_VERSION;
   state.total_updates = 0;
   state.bwisc_pulls = 0;
   state.mr_pulls = 0;
   state.bwisc_reward_sum = 0.0;
   state.mr_reward_sum = 0.0;
   state.updated_at = 0;
}

string Bandit_NormalizeStrategy(const string strategy)
{
   string normalized = strategy;
   StringTrimLeft(normalized);
   StringTrimRight(normalized);
   StringToUpper(normalized);
   return normalized;
}

bool Bandit_IsSupportedStrategy(const string strategy)
{
   string normalized = Bandit_NormalizeStrategy(strategy);
   return (normalized == "BWISC" || normalized == "MR");
}

double Bandit_ClampReward(const double reward)
{
   if(!MathIsValidNumber(reward))
      return BANDIT_PRIOR_MEAN;
   if(reward < 0.0)
      return 0.0;
   if(reward > 1.0)
      return 1.0;
   return reward;
}

double Bandit_RewardFromOutcome(const double net_outcome)
{
   if(!MathIsValidNumber(net_outcome))
      return BANDIT_PRIOR_MEAN;
   if(net_outcome > 0.0)
      return 1.0;
   if(net_outcome < 0.0)
      return 0.0;
   return BANDIT_PRIOR_MEAN;
}

bool Bandit_ParseKeyValueLine(const string line, string &out_key, string &out_value)
{
   out_key = "";
   out_value = "";

   string trimmed = line;
   StringTrimLeft(trimmed);
   StringTrimRight(trimmed);
   if(trimmed == "" || StringFind(trimmed, "#") == 0)
      return false;

   int sep = StringFind(trimmed, "=");
   if(sep <= 0)
      return false;

   out_key = StringSubstr(trimmed, 0, sep);
   out_value = StringSubstr(trimmed, sep + 1);
   StringTrimLeft(out_key);
   StringTrimRight(out_key);
   StringTrimLeft(out_value);
   StringTrimRight(out_value);
   return (out_key != "");
}

bool Bandit_ComputePosteriorReady(const BanditPosteriorState &state)
{
   if(state.schema_version != BANDIT_POSTERIOR_SCHEMA_VERSION)
      return false;
   if(state.total_updates < BANDIT_POSTERIOR_MIN_UPDATES)
      return false;
   if(state.bwisc_pulls <= 0 || state.mr_pulls <= 0)
      return false;
   return true;
}

bool Bandit_LoadPosteriorFromFile(BanditPosteriorState &state)
{
   int handle = FileOpen(FILE_BANDIT_POSTERIOR, FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   bool has_schema = false;
   bool has_updates = false;
   bool has_bwisc_pulls = false;
   bool has_mr_pulls = false;
   bool has_bwisc_sum = false;
   bool has_mr_sum = false;

   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      string key = "";
      string value = "";
      if(!Bandit_ParseKeyValueLine(line, key, value))
         continue;

      if(key == "schema_version")
      {
         int schema = (int)StringToInteger(value);
         if(schema != BANDIT_POSTERIOR_SCHEMA_VERSION)
         {
            FileClose(handle);
            return false;
         }
         state.schema_version = schema;
         has_schema = true;
      }
      else if(key == "total_updates")
      {
         int updates = (int)StringToInteger(value);
         if(updates < 0)
         {
            FileClose(handle);
            return false;
         }
         state.total_updates = updates;
         has_updates = true;
      }
      else if(key == "bwisc_pulls")
      {
         int pulls = (int)StringToInteger(value);
         if(pulls < 0)
         {
            FileClose(handle);
            return false;
         }
         state.bwisc_pulls = pulls;
         has_bwisc_pulls = true;
      }
      else if(key == "mr_pulls")
      {
         int pulls = (int)StringToInteger(value);
         if(pulls < 0)
         {
            FileClose(handle);
            return false;
         }
         state.mr_pulls = pulls;
         has_mr_pulls = true;
      }
      else if(key == "bwisc_reward_sum")
      {
         double reward_sum = StringToDouble(value);
         if(!MathIsValidNumber(reward_sum) || reward_sum < 0.0)
         {
            FileClose(handle);
            return false;
         }
         state.bwisc_reward_sum = reward_sum;
         has_bwisc_sum = true;
      }
      else if(key == "mr_reward_sum")
      {
         double reward_sum = StringToDouble(value);
         if(!MathIsValidNumber(reward_sum) || reward_sum < 0.0)
         {
            FileClose(handle);
            return false;
         }
         state.mr_reward_sum = reward_sum;
         has_mr_sum = true;
      }
      else if(key == "updated_at")
      {
         datetime ts = (datetime)StringToInteger(value);
         if(ts >= 0)
            state.updated_at = ts;
      }
   }

   FileClose(handle);

   if(!has_schema || !has_updates || !has_bwisc_pulls || !has_mr_pulls || !has_bwisc_sum || !has_mr_sum)
      return false;
   if(state.bwisc_reward_sum > (double)state.bwisc_pulls + 1e-9)
      return false;
   if(state.mr_reward_sum > (double)state.mr_pulls + 1e-9)
      return false;

   state.ready = Bandit_ComputePosteriorReady(state);
   return true;
}

bool Bandit_WritePosteriorAtomically(const BanditPosteriorState &state)
{
   string tmp_path = FILE_BANDIT_POSTERIOR + ".tmp";
   int handle = FileOpen(tmp_path, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   FileWrite(handle, StringFormat("schema_version=%d", state.schema_version));
   FileWrite(handle, StringFormat("total_updates=%d", state.total_updates));
   FileWrite(handle, StringFormat("bwisc_pulls=%d", state.bwisc_pulls));
   FileWrite(handle, StringFormat("mr_pulls=%d", state.mr_pulls));
   FileWrite(handle, StringFormat("bwisc_reward_sum=%.8f", state.bwisc_reward_sum));
   FileWrite(handle, StringFormat("mr_reward_sum=%.8f", state.mr_reward_sum));
   FileWrite(handle, StringFormat("updated_at=%I64d", (long)state.updated_at));
   FileClose(handle);

   if(FileIsExist(FILE_BANDIT_POSTERIOR))
      FileDelete(FILE_BANDIT_POSTERIOR);

   if(!FileMove(tmp_path, 0, FILE_BANDIT_POSTERIOR, 0))
   {
      FileDelete(tmp_path);
      return false;
   }
   return true;
}

void Bandit_EnsurePosteriorLoaded()
{
   if(g_bandit_posterior.initialized)
      return;

   BanditPosteriorState loaded;
   Bandit_ResetPosteriorDefaults(loaded);
   loaded.loaded_from_file = Bandit_LoadPosteriorFromFile(loaded);
   loaded.ready = Bandit_ComputePosteriorReady(loaded);
   g_bandit_posterior = loaded;
}

bool Bandit_IsPosteriorReady()
{
   Bandit_EnsurePosteriorLoaded();
   return g_bandit_posterior.ready;
}

double Bandit_ComputePosteriorMean(const int pulls, const double reward_sum)
{
   double safe_sum = reward_sum;
   if(!MathIsValidNumber(safe_sum) || safe_sum < 0.0)
      safe_sum = 0.0;
   double safe_pulls = (double)pulls;
   if(!MathIsValidNumber(safe_pulls) || safe_pulls < 0.0)
      safe_pulls = 0.0;

   return (safe_sum + (BANDIT_PRIOR_MEAN * BANDIT_PRIOR_WEIGHT)) /
          (safe_pulls + BANDIT_PRIOR_WEIGHT);
}

double Bandit_RegimeAdjustment(const REGIME_LABEL regime, const bool for_bwisc)
{
   switch(regime)
   {
      case REGIME_TRENDING:
         return (for_bwisc ? 0.05 : -0.02);
      case REGIME_RANGING:
         return (for_bwisc ? -0.02 : 0.05);
      case REGIME_VOLATILE:
         return -0.03;
      default:
         return 0.0;
   }
}

double Bandit_EfficiencyAdjustment(const double efficiency)
{
   double clamped = Bandit_ClampReward(efficiency);
   return (clamped - 0.5) * 0.10;
}

bool Bandit_RecordReward(const string strategy, const double reward)
{
   string normalized = Bandit_NormalizeStrategy(strategy);
   if(!Bandit_IsSupportedStrategy(normalized))
      return false;

   Bandit_EnsurePosteriorLoaded();

   double clamped_reward = Bandit_ClampReward(reward);
   if(normalized == "BWISC")
   {
      g_bandit_posterior.bwisc_pulls++;
      g_bandit_posterior.bwisc_reward_sum += clamped_reward;
   }
   else
   {
      g_bandit_posterior.mr_pulls++;
      g_bandit_posterior.mr_reward_sum += clamped_reward;
   }

   g_bandit_posterior.total_updates++;
   g_bandit_posterior.updated_at = TimeCurrent();
   g_bandit_posterior.ready = Bandit_ComputePosteriorReady(g_bandit_posterior);
   bool persisted = Bandit_WritePosteriorAtomically(g_bandit_posterior);
   if(persisted)
      g_bandit_posterior.loaded_from_file = true;
   return persisted;
}

bool Bandit_RecordTradeOutcome(const string strategy, const double net_outcome)
{
   return Bandit_RecordReward(strategy, Bandit_RewardFromOutcome(net_outcome));
}

BanditPolicy Bandit_SelectPolicy(const AppContext& ctx, const string symbol)
{
   Bandit_EnsurePosteriorLoaded();

#ifdef RPEA_TEST_RUNNER
   if(g_bandit_test_force_policy_active)
      return g_bandit_test_force_policy;
#endif

   if(symbol == "")
      return Bandit_Skip;

   double spread_q = Liquidity_GetSpreadQuantile(symbol);
   double slippage_q = Liquidity_GetSlippageQuantile(symbol);
   if(spread_q >= 0.95 || slippage_q >= 0.95)
      return Bandit_Skip;

   double bwisc_mean = Bandit_ComputePosteriorMean(g_bandit_posterior.bwisc_pulls,
                                                   g_bandit_posterior.bwisc_reward_sum);
   double mr_mean = Bandit_ComputePosteriorMean(g_bandit_posterior.mr_pulls,
                                                g_bandit_posterior.mr_reward_sum);

   REGIME_LABEL regime = Regime_Detect(ctx, symbol);
   double bwisc_score = bwisc_mean +
                        Bandit_RegimeAdjustment(regime, true) +
                        Bandit_EfficiencyAdjustment(Telemetry_GetBWISCEfficiency());
   double mr_score = mr_mean +
                     Bandit_RegimeAdjustment(regime, false) +
                     Bandit_EfficiencyAdjustment(Telemetry_GetMREfficiency());

   if(bwisc_score < BANDIT_MIN_ACTION_SCORE && mr_score < BANDIT_MIN_ACTION_SCORE)
      return Bandit_Skip;

   if(bwisc_score > mr_score + 1e-9)
      return Bandit_BWISC;
   if(mr_score > bwisc_score + 1e-9)
      return Bandit_MR;

   if(g_bandit_posterior.bwisc_pulls < g_bandit_posterior.mr_pulls)
      return Bandit_BWISC;
   if(g_bandit_posterior.mr_pulls < g_bandit_posterior.bwisc_pulls)
      return Bandit_MR;

   return Bandit_BWISC;
}

#ifdef RPEA_TEST_RUNNER
void Bandit_TestResetState()
{
   ZeroMemory(g_bandit_posterior);
   g_bandit_test_force_policy_active = false;
   g_bandit_test_force_policy = Bandit_Skip;
}

void Bandit_TestSetPosterior(const int bwisc_pulls,
                             const double bwisc_reward_sum,
                             const int mr_pulls,
                             const double mr_reward_sum,
                             const int total_updates)
{
   Bandit_ResetPosteriorDefaults(g_bandit_posterior);
   g_bandit_posterior.bwisc_pulls = (bwisc_pulls > 0 ? bwisc_pulls : 0);
   g_bandit_posterior.bwisc_reward_sum = (bwisc_reward_sum > 0.0 ? bwisc_reward_sum : 0.0);
   g_bandit_posterior.mr_pulls = (mr_pulls > 0 ? mr_pulls : 0);
   g_bandit_posterior.mr_reward_sum = (mr_reward_sum > 0.0 ? mr_reward_sum : 0.0);
   g_bandit_posterior.total_updates = (total_updates > 0 ? total_updates : 0);
   g_bandit_posterior.ready = Bandit_ComputePosteriorReady(g_bandit_posterior);
   g_bandit_posterior.updated_at = TimeCurrent();
}

bool Bandit_TestLoadPosterior()
{
   BanditPosteriorState loaded;
   Bandit_ResetPosteriorDefaults(loaded);
   bool ok = Bandit_LoadPosteriorFromFile(loaded);
   if(ok)
   {
      loaded.loaded_from_file = true;
      g_bandit_posterior = loaded;
   }
   return ok;
}

bool Bandit_TestSavePosterior()
{
   Bandit_EnsurePosteriorLoaded();
   return Bandit_WritePosteriorAtomically(g_bandit_posterior);
}

void Bandit_TestSetForcedPolicy(const bool active, const BanditPolicy policy)
{
   g_bandit_test_force_policy_active = active;
   g_bandit_test_force_policy = policy;
}

int Bandit_TestGetTotalUpdates()
{
   Bandit_EnsurePosteriorLoaded();
   return g_bandit_posterior.total_updates;
}

bool Bandit_TestIsReady()
{
   return Bandit_IsPosteriorReady();
}
#endif // RPEA_TEST_RUNNER

#endif // RPEA_BANDIT_MQH
