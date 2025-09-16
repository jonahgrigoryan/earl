#ifndef RPEA_ALLOCATOR_MQH
#define RPEA_ALLOCATOR_MQH
// allocator.mqh - Risk allocator stubs (M1)
// References: finalspec.md (Allocator Enhancements)

struct AppContext;
struct OrderPlan { bool hasPlan; double volume; double price; };

OrderPlan Allocator_BuildOrderPlan(const AppContext& ctx,
                                   const string strategy,
                                   const string symbol,
                                   const int slPoints,
                                   const int tpPoints,
                                   const double confidence)
{
   // TODO[M2]: budget gate math and second-trade rule
   OrderPlan p; p.hasPlan=false; p.volume=0.0; p.price=0.0;
   return p;
}
#endif // RPEA_ALLOCATOR_MQH
