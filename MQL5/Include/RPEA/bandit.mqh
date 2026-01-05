#ifndef RPEA_BANDIT_MQH
#define RPEA_BANDIT_MQH
// bandit.mqh - Contextual bandit stubs (M1)
// References: finalspec.md (Contextual Bandit Meta‑Policy)

struct AppContext;
enum BanditPolicy { Bandit_Skip=0, Bandit_BWISC=1, Bandit_MR=2 };

BanditPolicy Bandit_SelectPolicy(const AppContext& ctx, const string symbol)
{
   // TODO[M7]: Thompson/LinUCB with posterior persistence
   return Bandit_Skip;
}
#endif // RPEA_BANDIT_MQH
