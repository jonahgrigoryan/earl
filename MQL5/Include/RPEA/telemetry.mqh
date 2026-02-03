#ifndef RPEA_TELEMETRY_MQH
#define RPEA_TELEMETRY_MQH
// telemetry.mqh - Telemetry stubs (M1)
// References: finalspec.md (Telemetry & SLOs)

#include <RPEA/logging.mqh>
#include <RPEA/regime.mqh>

void Telemetry_UpdateKpis()
{
   // TODO[M7]: compute rolling KPIs
}

void Telemetry_AutoThrottle()
{
   // TODO[M7]: SLO thresholds and auto-risk reduction
}

void LogMetaPolicyDecision(const string symbol,
                           const string choice,
                           const string gating_reason,
                           const string news_state,
                           const double confidence,
                           const double efficiency,
                           const double bwisc_conf,
                           const double mr_conf,
                           const double bwisc_eff,
                           const double mr_eff,
                           const double emrt_rank,
                           const double rho_est,
                           const double spread_q,
                           const double slippage_q,
                           const int hold_minutes_est,
                           const REGIME_LABEL regime)
{
   string regime_str;
   switch(regime)
   {
      case REGIME_TRENDING: regime_str = "TRENDING"; break;
      case REGIME_RANGING:  regime_str = "RANGING";  break;
      case REGIME_VOLATILE: regime_str = "VOLATILE"; break;
      default:              regime_str = "UNKNOWN";  break;
   }

   string fields = StringFormat(
      "{\"symbol\":\"%s\",\"choice\":\"%s\",\"confidence\":%.2f,\"efficiency\":%.2f,"
      "\"rho_est\":%.2f,\"gating_reason\":\"%s\",\"news_window_state\":\"%s\","
      "\"bwisc_conf\":%.2f,\"mr_conf\":%.2f,\"bwisc_eff\":%.2f,\"mr_eff\":%.2f,"
      "\"emrt\":%.2f,\"spread_q\":%.2f,\"slippage_q\":%.2f,\"hold_time_min\":%d,"
      "\"regime\":\"%s\"}",
      symbol,
      choice,
      confidence,
      efficiency,
      rho_est,
      gating_reason,
      news_state,
      bwisc_conf,
      mr_conf,
      bwisc_eff,
      mr_eff,
      emrt_rank,
      spread_q,
      slippage_q,
      hold_minutes_est,
      regime_str);

   LogDecision("MetaPolicy", "EVAL", fields);
}
#endif // RPEA_TELEMETRY_MQH
