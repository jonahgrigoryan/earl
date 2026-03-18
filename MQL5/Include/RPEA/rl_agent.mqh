#ifndef RPEA_RL_AGENT_MQH
#define RPEA_RL_AGENT_MQH
// rl_agent.mqh - Q-table infrastructure (M7 Phase 1, Task 2)
// References: finalspec.md (Q-Learning Training Parameters), docs/m7-final-workflow.md

#include <RPEA/config.mqh>
#include <RPEA/persistence.mqh>

// State space: 4 periods x 4 quantile bins = 256 states
#define RL_NUM_PERIODS    4
#define RL_NUM_QUANTILES  4
#define RL_NUM_STATES     256
#define RL_NUM_ACTIONS    3

// RL Actions enum (EXIT=0, HOLD=1, ENTER=2 per workflow)
enum RL_ACTION
{
   RL_ACTION_EXIT = 0,
   RL_ACTION_HOLD = 1,
   RL_ACTION_ENTER = 2
};

// Q-table storage
double g_qtable[RL_NUM_STATES][RL_NUM_ACTIONS];
bool   g_qtable_loaded = false;

// Quantile thresholds (default 3% if no calibration file)
double   g_quantile_thresholds[3] = {-0.03, 0.0, 0.03};
double   g_sigma_ref = 0.0;
datetime g_thresholds_calibrated_at = 0;
bool     g_thresholds_loaded = false;

void RL_ResetThresholdsToDefaults()
{
   g_quantile_thresholds[0] = -0.03;
   g_quantile_thresholds[1] = 0.0;
   g_quantile_thresholds[2] = 0.03;
   g_sigma_ref = 0.0;
   g_thresholds_calibrated_at = 0;
   g_thresholds_loaded = false;
}

void RL_InitQTable()
{
   ArrayInitialize(g_qtable, 0.0);
   g_qtable_loaded = false;
   RL_ResetThresholdsToDefaults();
}

bool RL_ParseCalibrationDate(const string date_text, datetime &out_time)
{
   if(date_text == "")
      return false;
   string normalized = date_text;
   StringReplace(normalized, "-", ".");
   if(StringLen(normalized) <= 10)
      normalized += " 00:00";
   datetime parsed = StringToTime(normalized);
   if(parsed <= 0)
      return false;
   out_time = parsed;
   return true;
}

// Load thresholds generated during pre-training.
// File: Files/RPEA/rl/thresholds.json
// Format: { "k_thresholds": [-0.02, 0.0, 0.02], "sigma_ref": 0.015, "calibrated_at": "2026-01-28" }
// Fallback: if missing or stale (>30 days), keep fixed 3% thresholds.
bool RL_LoadThresholdsFromPath(const string path)
{
   RL_ResetThresholdsToDefaults();
   if(path == "")
      return false;

   string json = Persistence_ReadWholeFile(path);
   if(json == "")
      return false;

   double thresholds[];
   if(!Persistence_ParseArrayOfDouble(json, "k_thresholds", thresholds))
      return false;
   if(ArraySize(thresholds) < 3)
      return false;
   if(thresholds[0] >= thresholds[1] || thresholds[1] >= thresholds[2])
      return false;

   double sigma = 0.0;
   Persistence_ParseNumberField(json, "sigma_ref", sigma);

   string calibrated_at = "";
   if(!Persistence_ParseStringField(json, "calibrated_at", calibrated_at))
      return false;

   datetime calibrated_time = 0;
   if(!RL_ParseCalibrationDate(calibrated_at, calibrated_time))
      return false;

   datetime now = TimeCurrent();
   if(now > 0 && calibrated_time > 0)
   {
      int age_days = (int)((now - calibrated_time) / 86400);
      if(age_days > 30)
         return false;
   }

   g_quantile_thresholds[0] = thresholds[0];
   g_quantile_thresholds[1] = thresholds[1];
   g_quantile_thresholds[2] = thresholds[2];
   g_sigma_ref = sigma;
   g_thresholds_calibrated_at = calibrated_time;
   g_thresholds_loaded = true;
   return true;
}

bool RL_LoadThresholds()
{
   return RL_LoadThresholdsFromPath(FILE_RL_THRESHOLDS);
}

int RL_OpenReadBinaryWithCommonFallback(const string path)
{
   int handle = FileOpen(path, FILE_READ|FILE_BIN);
   if(handle != INVALID_HANDLE)
      return handle;
   ResetLastError();
   return FileOpen(path, FILE_READ|FILE_BIN|FILE_COMMON);
}

int RL_QuantileBin(const double value)
{
   if(value < g_quantile_thresholds[0]) return 0;
   if(value < g_quantile_thresholds[1]) return 1;
   if(value < g_quantile_thresholds[2]) return 2;
   return 3;
}

// Discretize spread trajectory into state_id (0-255)
// changes: array of percentage changes for recent periods
// periods: number of periods to consider (typically 4)
int RL_StateFromSpread(double &changes[], const int periods)
{
   if(periods <= 0)
      return 0;
   int available = ArraySize(changes);
   if(available <= 0)
      return 0;
   int count = periods;
   if(count > RL_NUM_PERIODS) count = RL_NUM_PERIODS;
   if(available < count)
      return 0;

   int state = 0;
   for(int i = 0; i < count; i++)
   {
      int quantile = RL_QuantileBin(changes[i]);
      state = state * RL_NUM_QUANTILES + quantile;
   }
   return state;
}

// Get action for state (exploitation mode - highest Q-value)
int RL_ActionForState(const int state_id)
{
   if(!g_qtable_loaded || state_id < 0 || state_id >= RL_NUM_STATES)
      return (int)RL_ACTION_HOLD;

   int best_action = 0;
   double best_q = g_qtable[state_id][0];
   for(int a = 1; a < RL_NUM_ACTIONS; a++)
   {
      if(g_qtable[state_id][a] > best_q)
      {
         best_q = g_qtable[state_id][a];
         best_action = a;
      }
   }
   return best_action;
}

int RL_RuntimeActionForState(const int state_id)
{
   if(!Config_IsQLModeEnabled())
      return (int)RL_ACTION_HOLD;
   return RL_ActionForState(state_id);
}

// Get Q-advantage for a state: (max(Q) - mean(Q)) normalized to [0,1]
double RL_GetQAdvantage(const int state_id)
{
   if(!g_qtable_loaded || state_id < 0 || state_id >= RL_NUM_STATES)
      return 0.5;

   double q_max = g_qtable[state_id][0];
   double q_min = q_max;
   double q_sum = q_max;
   for(int a = 1; a < RL_NUM_ACTIONS; a++)
   {
      double q = g_qtable[state_id][a];
      q_sum += q;
      if(q > q_max) q_max = q;
      if(q < q_min) q_min = q;
   }

   double q_mean = q_sum / RL_NUM_ACTIONS;
   double range = q_max - q_min;
   if(range < 1e-9)
      return 0.5;

   double advantage = (q_max - q_mean) / range;
   if(advantage < 0.0) return 0.0;
   if(advantage > 1.0) return 1.0;
   return advantage;
}

double RL_RuntimeQAdvantage(const int state_id)
{
   if(!Config_IsQLModeEnabled())
      return 0.5;
   return RL_GetQAdvantage(state_id);
}

// Load Q-table from binary file
bool RL_LoadQTable(const string path)
{
   if(path == "")
   {
      RL_InitQTable();
      return false;
   }

   int handle = RL_OpenReadBinaryWithCommonFallback(path);
   if(handle == INVALID_HANDLE)
   {
      RL_InitQTable();
      return false;
   }

   int expected_bytes = RL_NUM_STATES * RL_NUM_ACTIONS * 8;
   if(FileSize(handle) < expected_bytes)
   {
      FileClose(handle);
      RL_InitQTable();
      return false;
   }

   for(int s = 0; s < RL_NUM_STATES; s++)
   {
      for(int a = 0; a < RL_NUM_ACTIONS; a++)
         g_qtable[s][a] = FileReadDouble(handle);
   }
   FileClose(handle);
   g_qtable_loaded = true;
   return true;
}

// Save Q-table to binary file
bool RL_SaveQTable(const string path)
{
   if(path == "")
      return false;

   int handle = FileOpen(path, FILE_WRITE|FILE_BIN);
   if(handle == INVALID_HANDLE)
      return false;

   for(int s = 0; s < RL_NUM_STATES; s++)
   {
      for(int a = 0; a < RL_NUM_ACTIONS; a++)
         FileWriteDouble(handle, g_qtable[s][a]);
   }
   FileClose(handle);
   return true;
}

// Bellman update for Q-learning (used by pre-training script)
void RL_BellmanUpdate(int state, int action, double reward, int next_state, double alpha, double gamma)
{
   if(state < 0 || state >= RL_NUM_STATES) return;
   if(action < 0 || action >= RL_NUM_ACTIONS) return;
   if(next_state < 0 || next_state >= RL_NUM_STATES) return;

   double q_current = g_qtable[state][action];
   double q_max_next = g_qtable[next_state][0];
   for(int a = 1; a < RL_NUM_ACTIONS; a++)
   {
      if(g_qtable[next_state][a] > q_max_next)
         q_max_next = g_qtable[next_state][a];
   }

   double td_target = reward + gamma * q_max_next;
   g_qtable[state][action] = q_current + alpha * (td_target - q_current);
}

#endif // RPEA_RL_AGENT_MQH
