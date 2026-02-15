#ifndef RPEA_LEARNING_MQH
#define RPEA_LEARNING_MQH
// learning.mqh - Calibration & learning runtime (Post-M7 Phase 4)
// References: finalspec.md (Online Learning & Calibration)

#include <RPEA/config.mqh>
#include <RPEA/slo_monitor.mqh>
#include <RPEA/telemetry.mqh>

#define LEARNING_CALIBRATION_SCHEMA_VERSION 1
#define LEARNING_DEFAULT_BWISC_BIAS         0.50
#define LEARNING_DEFAULT_MR_BIAS            0.50
#define LEARNING_UPDATE_ALPHA               0.20

struct LearningCalibrationState
{
   bool     initialized;
   bool     loaded_from_file;
   int      schema_version;
   double   bwisc_bias;
   double   mr_bias;
   int      sample_count;
   datetime updated_at;
};

LearningCalibrationState g_learning_calibration;
int  g_learning_persist_writes = 0;
bool g_learning_last_update_frozen = false;
bool g_learning_last_update_persisted = false;

void Learning_ResetCalibrationState(LearningCalibrationState &state)
{
   state.initialized = true;
   state.loaded_from_file = false;
   state.schema_version = LEARNING_CALIBRATION_SCHEMA_VERSION;
   state.bwisc_bias = LEARNING_DEFAULT_BWISC_BIAS;
   state.mr_bias = LEARNING_DEFAULT_MR_BIAS;
   state.sample_count = 0;
   state.updated_at = 0;
}

double Learning_ClampUnitValue(const double value, const double fallback)
{
   if(!MathIsValidNumber(value))
      return fallback;
   if(value < 0.0 || value > 1.0)
      return fallback;
   return value;
}

bool Learning_ParseKeyValueLine(const string line, string &out_key, string &out_value)
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

bool Learning_LoadCalibrationFile(LearningCalibrationState &state)
{
   int handle = FileOpen(FILE_CALIBRATION, FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   bool has_schema = false;
   bool has_bwisc = false;
   bool has_mr = false;

   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      string key = "";
      string value = "";
      if(!Learning_ParseKeyValueLine(line, key, value))
         continue;

      if(key == "schema_version")
      {
         int schema = (int)StringToInteger(value);
         if(schema != LEARNING_CALIBRATION_SCHEMA_VERSION)
         {
            FileClose(handle);
            return false;
         }
         state.schema_version = schema;
         has_schema = true;
      }
      else if(key == "bwisc_bias")
      {
         double parsed = StringToDouble(value);
         double validated = Learning_ClampUnitValue(parsed, -1.0);
         if(validated < 0.0)
         {
            FileClose(handle);
            return false;
         }
         state.bwisc_bias = validated;
         has_bwisc = true;
      }
      else if(key == "mr_bias")
      {
         double parsed = StringToDouble(value);
         double validated = Learning_ClampUnitValue(parsed, -1.0);
         if(validated < 0.0)
         {
            FileClose(handle);
            return false;
         }
         state.mr_bias = validated;
         has_mr = true;
      }
      else if(key == "sample_count")
      {
         int samples = (int)StringToInteger(value);
         if(samples < 0)
         {
            FileClose(handle);
            return false;
         }
         state.sample_count = samples;
      }
      else if(key == "updated_at")
      {
         datetime ts = (datetime)StringToInteger(value);
         if(ts >= 0)
            state.updated_at = ts;
      }
   }

   FileClose(handle);

   if(!has_schema || !has_bwisc || !has_mr)
      return false;

   double sum_bias = state.bwisc_bias + state.mr_bias;
   if(!MathIsValidNumber(sum_bias) || sum_bias <= 1e-9)
      return false;

   state.bwisc_bias = state.bwisc_bias / sum_bias;
   state.mr_bias = state.mr_bias / sum_bias;
   return true;
}

void Learning_NormalizeBiases(LearningCalibrationState &state)
{
   double sum_bias = state.bwisc_bias + state.mr_bias;
   if(!MathIsValidNumber(sum_bias) || sum_bias <= 1e-9)
   {
      state.bwisc_bias = LEARNING_DEFAULT_BWISC_BIAS;
      state.mr_bias = LEARNING_DEFAULT_MR_BIAS;
      return;
   }

   state.bwisc_bias = Learning_ClampUnitValue(state.bwisc_bias / sum_bias,
                                              LEARNING_DEFAULT_BWISC_BIAS);
   state.mr_bias = Learning_ClampUnitValue(state.mr_bias / sum_bias,
                                           LEARNING_DEFAULT_MR_BIAS);
}

bool Learning_WriteCalibrationAtomically(const LearningCalibrationState &state)
{
   string tmp_path = FILE_CALIBRATION + ".tmp";
   int handle = FileOpen(tmp_path, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   FileWrite(handle, StringFormat("schema_version=%d", state.schema_version));
   FileWrite(handle, StringFormat("bwisc_bias=%.8f", state.bwisc_bias));
   FileWrite(handle, StringFormat("mr_bias=%.8f", state.mr_bias));
   FileWrite(handle, StringFormat("sample_count=%d", state.sample_count));
   FileWrite(handle, StringFormat("updated_at=%I64d", (long)state.updated_at));
   FileClose(handle);

   if(FileIsExist(FILE_CALIBRATION))
      FileDelete(FILE_CALIBRATION);

   if(!FileMove(tmp_path, 0, FILE_CALIBRATION, 0))
   {
      FileDelete(tmp_path);
      return false;
   }

   return true;
}

void Learning_EnsureCalibrationLoaded()
{
   if(g_learning_calibration.initialized)
      return;
   Learning_LoadCalibration();
}

double Learning_GetBWISCBias()
{
   Learning_EnsureCalibrationLoaded();
   return g_learning_calibration.bwisc_bias;
}

double Learning_GetMRBias()
{
   Learning_EnsureCalibrationLoaded();
   return g_learning_calibration.mr_bias;
}

int Learning_GetSampleCount()
{
   Learning_EnsureCalibrationLoaded();
   return g_learning_calibration.sample_count;
}

void Learning_LoadCalibration()
{
   LearningCalibrationState loaded;
   Learning_ResetCalibrationState(loaded);
   loaded.loaded_from_file = Learning_LoadCalibrationFile(loaded);
   g_learning_calibration = loaded;
   g_learning_last_update_frozen = false;
   g_learning_last_update_persisted = false;
}

void Learning_Update()
{
   Learning_EnsureCalibrationLoaded();
   g_learning_last_update_frozen = false;
   g_learning_last_update_persisted = false;

   if(SLO_IsMRThrottled())
   {
      g_learning_last_update_frozen = true;
      return;
   }

   int bwisc_samples = Telemetry_GetBWISCSamples();
   int mr_samples = Telemetry_GetMRSamples();
   int total_samples = bwisc_samples + mr_samples;
   if(total_samples <= 0)
      return;

   double bwisc_eff = Learning_ClampUnitValue(Telemetry_GetBWISCEfficiency(), 0.0);
   double mr_eff = Learning_ClampUnitValue(Telemetry_GetMREfficiency(), 0.0);

   double target_bwisc = LEARNING_DEFAULT_BWISC_BIAS;
   double target_mr = LEARNING_DEFAULT_MR_BIAS;
   double eff_sum = bwisc_eff + mr_eff;
   if(MathIsValidNumber(eff_sum) && eff_sum > 1e-9)
   {
      target_bwisc = bwisc_eff / eff_sum;
      target_mr = mr_eff / eff_sum;
   }

   double alpha = LEARNING_UPDATE_ALPHA;
   if(alpha < 0.0)
      alpha = 0.0;
   if(alpha > 1.0)
      alpha = 1.0;

   g_learning_calibration.bwisc_bias =
      ((1.0 - alpha) * g_learning_calibration.bwisc_bias) + (alpha * target_bwisc);
   g_learning_calibration.mr_bias =
      ((1.0 - alpha) * g_learning_calibration.mr_bias) + (alpha * target_mr);
   Learning_NormalizeBiases(g_learning_calibration);

   g_learning_calibration.sample_count =
      (int)MathMax((double)g_learning_calibration.sample_count, (double)total_samples);
   g_learning_calibration.updated_at = TimeCurrent();

   if(Learning_WriteCalibrationAtomically(g_learning_calibration))
   {
      g_learning_calibration.loaded_from_file = true;
      g_learning_persist_writes++;
      g_learning_last_update_persisted = true;
   }
}

#ifdef RPEA_TEST_RUNNER
void Learning_TestResetState()
{
   ZeroMemory(g_learning_calibration);
   g_learning_persist_writes = 0;
   g_learning_last_update_frozen = false;
   g_learning_last_update_persisted = false;
}

bool Learning_TestLoadedFromFile()
{
   Learning_EnsureCalibrationLoaded();
   return g_learning_calibration.loaded_from_file;
}

double Learning_TestGetBWISCBias()
{
   return Learning_GetBWISCBias();
}

double Learning_TestGetMRBias()
{
   return Learning_GetMRBias();
}

int Learning_TestGetSampleCount()
{
   return Learning_GetSampleCount();
}

int Learning_TestGetPersistWriteCount()
{
   return g_learning_persist_writes;
}

bool Learning_TestLastUpdateFrozen()
{
   return g_learning_last_update_frozen;
}

bool Learning_TestLastUpdatePersisted()
{
   return g_learning_last_update_persisted;
}
#endif // RPEA_TEST_RUNNER
#endif // RPEA_LEARNING_MQH
