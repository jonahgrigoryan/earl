#property script_show_inputs

#include <RPEA/rl_pretrain_inputs.mqh>
#include <RPEA/emrt.mqh>
#include <RPEA/persistence.mqh>
#include <RPEA/config.mqh>

void OnStart()
{
   Print("=== EMRT Refresh Started ===");

   // Ensure Files/RPEA folders exist before writing cache.
   Persistence_EnsureFolders();

   EMRT_RefreshWeekly();

   if(EMRT_LoadCache(FILE_EMRT_CACHE))
      Print("[EMRT] Cache loaded: ", FILE_EMRT_CACHE);
   else
      Print("[EMRT] Cache not loaded (using defaults): ", FILE_EMRT_CACHE);

   Print("=== EMRT Refresh Finished ===");
}
