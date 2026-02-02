#property script_show_inputs
#property strict

#include <RPEA/rl_pretrain_inputs.mqh>
#include <RPEA/rl_agent.mqh>

// Training hyperparameters
input int    TrainingEpisodes     = 10000;  // Number of training episodes
input double LearningRate         = 0.10;   // Alpha for Bellman update
input double DiscountFactor       = 0.99;   // Gamma for future rewards
input double EpsilonStart         = 1.0;    // Initial exploration rate
input double EpsilonEnd           = 0.1;    // Final exploration rate
input string QTableOutputPath     = "RPEA/qtable/mr_qtable.bin";
input string ThresholdsOutputPath = "RPEA/rl/thresholds.json";

// OU process parameters for spread simulation
input double OU_Theta       = 0.1;  // Mean reversion speed
input double OU_Sigma       = 0.02; // Volatility
input int    EpisodeLength  = 100;  // Timesteps per episode

// Reward function parameters
input double CostPerStep    = 0.001; // Cost for holding position
input double NewsPenalty    = 0.005; // Penalty for trades in news windows
input double BarrierPenalty = 0.01;  // Penalty for breaching floor/target

bool   EnsureOutputFolders();
double RunEpisode(double epsilon, double alpha, double gamma);
int    BuildStateFromIndex(const double &changes[], const int index);
double ExecuteAction(int action, int &position, double spread_level,
                     double cost_per_step, bool news_blocked, bool barrier_breached);
void   GenerateSpreadTrajectory(double &changes[], int length);
double MathRandomNormal(double mean, double stddev);
bool   SimulateNewsWindow(int timestep, int episode_length);
bool   SimulateBarrierBreach(double spread_level, int position);
bool   RL_SaveThresholds(const string path);

void OnStart()
{
   Print("=== RL Pre-Training Started ===");
   Print("Episodes: ", TrainingEpisodes);
   Print("Learning Rate: ", LearningRate);
   Print("Discount Factor: ", DiscountFactor);

   if(TrainingEpisodes <= 0)
   {
      Print("ERROR: TrainingEpisodes must be > 0");
      return;
   }
   if(EpisodeLength < 2)
   {
      Print("ERROR: EpisodeLength must be >= 2");
      return;
   }

   MathSrand((int)TimeLocal());

   if(!EnsureOutputFolders())
   {
      Print("ERROR: Failed to prepare output folders");
      return;
   }

   RL_InitQTable();
   g_qtable_loaded = true; // Allow greedy selection during training
   Print("Q-table initialized");

   double best_reward = -1e308;
   double cumulative_reward = 0.0;

   for(int ep = 0; ep < TrainingEpisodes; ep++)
   {
      double epsilon = EpsilonStart - (EpsilonStart - EpsilonEnd) * ((double)ep / (double)TrainingEpisodes);
      if(epsilon < EpsilonEnd) epsilon = EpsilonEnd;
      if(epsilon > EpsilonStart) epsilon = EpsilonStart;

      double ep_reward = RunEpisode(epsilon, LearningRate, DiscountFactor);
      cumulative_reward += ep_reward;
      if(ep_reward > best_reward)
         best_reward = ep_reward;

      if(ep % 1000 == 0)
      {
         double avg_reward = cumulative_reward / (ep + 1);
         PrintFormat("Episode %d/%d | Epsilon: %.3f | Avg Reward: %.4f | Best: %.4f",
                     ep, TrainingEpisodes, epsilon, avg_reward, best_reward);
      }
   }

   Print("=== Training Complete ===");
   Print("Final Average Reward: ", cumulative_reward / TrainingEpisodes);

   if(RL_SaveQTable(QTableOutputPath))
      Print("Q-table saved to: ", QTableOutputPath);
   else
      Print("ERROR: Failed to save Q-table");

   if(RL_SaveThresholds(ThresholdsOutputPath))
      Print("Thresholds saved to: ", ThresholdsOutputPath);
   else
      Print("WARNING: Failed to save thresholds (using defaults)");

   Print("=== RL Pre-Training Finished ===");
}

double RunEpisode(double epsilon, double alpha, double gamma)
{
   double spread_changes[];
   GenerateSpreadTrajectory(spread_changes, EpisodeLength);

   int state = BuildStateFromIndex(spread_changes, 0);
   int position = 0; // -1=short, 0=flat, 1=long
   double spread_level = 0.0;
   double cumulative_reward = 0.0;

   for(int t = 0; t < EpisodeLength - 1; t++)
   {
      spread_level += spread_changes[t];

      int action;
      if((MathRand() / 32768.0) < epsilon)
         action = MathRand() % RL_NUM_ACTIONS;
      else
         action = RL_ActionForState(state);

      bool news_blocked = SimulateNewsWindow(t, EpisodeLength);
      bool barrier_breached = SimulateBarrierBreach(spread_level, position);

      double reward = ExecuteAction(action, position, spread_level, CostPerStep,
                                    news_blocked, barrier_breached);

      int next_state = BuildStateFromIndex(spread_changes, t + 1);
      RL_BellmanUpdate(state, action, reward, next_state, alpha, gamma);

      state = next_state;
      cumulative_reward += reward;
   }

   return cumulative_reward;
}

int BuildStateFromIndex(const double &changes[], const int index)
{
   double window[];
   ArrayResize(window, RL_NUM_PERIODS);
   int total = ArraySize(changes);

   for(int i = 0; i < RL_NUM_PERIODS; i++)
   {
      int src = index - i;
      if(src >= 0 && src < total)
         window[i] = changes[src];
      else
         window[i] = 0.0;
   }

   return RL_StateFromSpread(window, RL_NUM_PERIODS);
}

double ExecuteAction(int action, int &position, double spread_level,
                     double cost_per_step, bool news_blocked, bool barrier_breached)
{
   double reward = 0.0;

   switch(action)
   {
      case RL_ACTION_ENTER:
         if(position == 0)
            position = (spread_level > 0.0) ? -1 : 1;
         break;
      case RL_ACTION_HOLD:
         break;
      case RL_ACTION_EXIT:
         if(position != 0)
            position = 0;
         break;
   }

   reward += position * (0.0 - spread_level);
   reward -= cost_per_step * MathAbs((double)position);

   if(news_blocked)
      reward -= NewsPenalty;
   if(barrier_breached)
      reward -= BarrierPenalty;

   return reward;
}

void GenerateSpreadTrajectory(double &changes[], int length)
{
   if(length <= 0)
   {
      ArrayResize(changes, 0);
      return;
   }

   ArrayResize(changes, length);

   double spread = 0.0;
   double dt = 1.0;

   for(int i = 0; i < length; i++)
   {
      double dW = MathRandomNormal(0.0, 1.0) * MathSqrt(dt);
      double d_spread = -OU_Theta * spread * dt + OU_Sigma * dW;
      changes[i] = d_spread;
      spread += d_spread;
   }
}

double MathRandomNormal(double mean, double stddev)
{
   double u1 = (MathRand() + 1) / 32768.0;
   double u2 = MathRand() / 32768.0;
   const double pi = 3.14159265358979323846;

   double z = MathSqrt(-2.0 * MathLog(u1)) * MathCos(2.0 * pi * u2);
   return mean + stddev * z;
}

bool SimulateNewsWindow(int timestep, int episode_length)
{
   if(episode_length <= 0)
      return false;
   int sample = (timestep + MathRand()) % 100;
   return sample < 10;
}

bool SimulateBarrierBreach(double spread_level, int position)
{
   if(position == 0)
      return false;

   double barrier_threshold = 2.0 * OU_Sigma;
   return MathAbs(spread_level) > barrier_threshold;
}

bool RL_SaveThresholds(const string path)
{
   int sample_episodes = (TrainingEpisodes < 100) ? TrainingEpisodes : 100;
   int total_samples = sample_episodes * EpisodeLength;
   if(total_samples <= 0)
      return false;

   double all_changes[];
   ArrayResize(all_changes, total_samples);

   int idx = 0;
   for(int ep = 0; ep < sample_episodes; ep++)
   {
      double trajectory[];
      GenerateSpreadTrajectory(trajectory, EpisodeLength);
      for(int t = 0; t < EpisodeLength && idx < total_samples; t++)
      {
         all_changes[idx] = trajectory[t];
         idx++;
      }
   }

   if(idx < 4)
      return false;

   ArrayResize(all_changes, idx);
   ArraySort(all_changes);
   int n = ArraySize(all_changes);

   double k0 = all_changes[n / 4];
   double k1 = all_changes[n / 2];
   double k2 = all_changes[(3 * n) / 4];

   double sum = 0.0;
   for(int i = 0; i < n; i++)
      sum += all_changes[i];
   double mean = sum / n;

   double variance_sum = 0.0;
   for(int j = 0; j < n; j++)
   {
      double diff = all_changes[j] - mean;
      variance_sum += diff * diff;
   }
   double sigma_ref = MathSqrt(variance_sum / n);

   string calibrated_at = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);

   int handle = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create thresholds file: ", path);
      return false;
   }

   string json = StringFormat(
      "{\n"
      "  \"k_thresholds\": [%.6f, %.6f, %.6f],\n"
      "  \"sigma_ref\": %.6f,\n"
      "  \"calibrated_at\": \"%s\",\n"
      "  \"training_episodes\": %d,\n"
      "  \"ou_theta\": %.3f,\n"
      "  \"ou_sigma\": %.3f\n"
      "}",
      k0, k1, k2,
      sigma_ref,
      calibrated_at,
      TrainingEpisodes,
      OU_Theta,
      OU_Sigma
   );

   FileWriteString(handle, json);
   FileClose(handle);

   PrintFormat("Thresholds calibrated: k=[%.6f, %.6f, %.6f], sigma_ref=%.6f",
               k0, k1, k2, sigma_ref);

   return true;
}

bool EnsureOutputFolders()
{
   Persistence_EnsureFolders();

   ResetLastError();
   if(!FolderCreate(RPEA_DIR"/rl"))
   {
      int err = GetLastError();
      if(err != 0)
      {
         Print("ERROR: Failed to create RPEA/rl folder, err=", err);
         return false;
      }
   }
   return true;
}
