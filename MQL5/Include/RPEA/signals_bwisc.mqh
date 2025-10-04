#ifndef SIGNALS_BWISC_MQH
#define SIGNALS_BWISC_MQH
// signals_bwisc.mqh - BWISC signal API (M1)
// References: finalspec.md (Original Strategy: BWISC)

#include <RPEA/logging.mqh>
#include <RPEA/indicators.mqh>
#include <RPEA/sessions.mqh>

// Helper: sign function (returns -1, 0, or +1)
int MathSign(double val)
{
   if(val > 0.0) return 1;
   if(val < 0.0) return -1;
   return 0;
}

struct AppContext;

struct BWISC_Context
{
   double expected_R;
   double expected_hold;
   double worst_case_risk;
   double entry_price;
   int    direction;  // 1 for long, -1 for short
};

BWISC_Context g_last_bwisc_context;

// Propose a BWISC setup for symbol (logging-only in M2)
void SignalsBWISC_Propose(const AppContext& ctx, const string symbol,
                          bool &hasSetup, string &setupType,
                          int &slPoints, int &tpPoints,
                          double &bias, double &confidence)
{
   hasSetup = false;
   setupType = "None";
   slPoints = 0;
   tpPoints = 0;
   bias = 0.0;
   confidence = 0.0;

   g_last_bwisc_context.expected_R = 0.0;
   g_last_bwisc_context.expected_hold = 0.0;
   g_last_bwisc_context.worst_case_risk = 0.0;
   g_last_bwisc_context.entry_price = 0.0;
   g_last_bwisc_context.direction = 0;

   if(symbol == "")
   {
      LogDecision("BWISC", "EVAL", "{\"symbol\":\"\",\"blocked_by\":\"invalid_symbol\"}");
      return;
   }

   IndicatorSnapshot ind_snap;
   Indicators_GetSnapshot(symbol, ind_snap);

   SessionORSnapshot lo_snap;
   SessionORSnapshot ny_snap;
   bool lo_ok = Sessions_GetORSnapshot(ctx, symbol, SESSION_LABEL_LONDON, lo_snap);
   bool ny_ok = Sessions_GetORSnapshot(ctx, symbol, SESSION_LABEL_NEWYORK, ny_snap);

   SessionORSnapshot session_snap;
   string session_label = "";
   bool session_selected = false;

   bool lo_active = lo_ok && lo_snap.session_active;
   bool ny_active = ny_ok && ny_snap.session_active;
   bool lo_enabled = lo_active && lo_snap.session_enabled;
   bool ny_enabled = ny_active && ny_snap.session_enabled;

   if(lo_enabled)
   {
      session_snap = lo_snap;
      session_label = SESSION_LABEL_LONDON;
      session_selected = true;
   }
   else if(ny_enabled)
   {
      session_snap = ny_snap;
      session_label = SESSION_LABEL_NEWYORK;
      session_selected = true;
   }

   if(!session_selected)
   {
      if(lo_active && !lo_snap.session_enabled)
      {
         string note = StringFormat("{\"symbol\":\"%s\",\"session\":\"%s\",\"blocked_by\":\"session_disabled\"}", symbol, SESSION_LABEL_LONDON);
         LogDecision("BWISC", "EVAL", note);
         return;
      }
      if(ny_active && !ny_snap.session_enabled)
      {
         string note = StringFormat("{\"symbol\":\"%s\",\"session\":\"%s\",\"blocked_by\":\"session_disabled\"}", symbol, SESSION_LABEL_NEWYORK);
         LogDecision("BWISC", "EVAL", note);
         return;
      }

      string note = StringFormat("{\"symbol\":\"%s\",\"blocked_by\":\"no_active_session\"}", symbol);
      LogDecision("BWISC", "EVAL", note);
      return;
   }

   bool data_ok = (ind_snap.has_atr && ind_snap.has_ma && ind_snap.has_rsi && ind_snap.has_ohlc &&
                   session_snap.has_or_values && MathIsValidNumber(ind_snap.atr_d1) && ind_snap.atr_d1 > 0.0);

   if(!data_ok)
   {
      string note = StringFormat("{\"symbol\":\"%s\",\"session\":\"%s\",\"blocked_by\":\"insufficient_data\",\"has_atr\":%s,\"has_ma\":%s,\"has_rsi\":%s,\"has_ohlc\":%s,\"has_or\":%s,\"atr_d1\":%.6f}",
                                 symbol,
                                 session_label,
                                 ind_snap.has_atr?"true":"false",
                                 ind_snap.has_ma?"true":"false",
                                 ind_snap.has_rsi?"true":"false",
                                 ind_snap.has_ohlc?"true":"false",
                                 session_snap.has_or_values?"true":"false",
                                 ind_snap.atr_d1);
      LogDecision("BWISC", "EVAL", note);
      return;
   }

   double body = MathAbs(ind_snap.close_d1_prev - ind_snap.open_d1_prev);
   double true_range = MathMax(ind_snap.high_d1_prev - ind_snap.low_d1_prev, _Point);
   double btr = (true_range > 0.0 ? body / true_range : 0.0);

   double atr_d1 = ind_snap.atr_d1;
   double open_lo_minus_ma = session_snap.session_open_price - ind_snap.ma20_h1;
   double sdr = MathAbs(open_lo_minus_ma) / atr_d1;
   double or_span = session_snap.or_high - session_snap.or_low;
   if(or_span < 0.0)
      or_span = 0.0;
   double ore = (atr_d1 > 0.0 ? or_span / atr_d1 : 0.0);

   double c1_minus_o1 = ind_snap.close_d1_prev - ind_snap.open_d1_prev;
   double bias_value = 0.45 * MathSign(c1_minus_o1) * btr +
                       0.35 * MathSign(open_lo_minus_ma) * MathMin(sdr, 1.0) +
                       0.20 * MathSign(c1_minus_o1) * MathMin(ore, 1.0);
   double abs_bias = MathAbs(bias_value);
   bias = bias_value;

   double r_target = 0.0;
   if(abs_bias >= 0.6)
   {
      setupType = "BC";
      r_target = RtargetBC;
   }
   else if(abs_bias >= 0.35 && sdr >= 0.35)
   {
      setupType = "MSC";
      r_target = RtargetMSC;
   }
   else
   {
      string note = StringFormat("{\"symbol\":\"%s\",\"session\":\"%s\",\"btr\":%.6f,\"sdr\":%.6f,\"ore\":%.6f,\"bias\":%.6f,\"setup\":\"None\",\"confidence\":0.0,\"reason\":\"bias_below_threshold\"}",
                                 symbol,
                                 session_label,
                                 btr,
                                 sdr,
                                 ore,
                                 bias_value);
      LogDecision("BWISC", "EVAL", note);
      return;
   }

   double rsi = ind_snap.rsi_h1;
   if((rsi < 35.0 || rsi > 70.0) && sdr < 0.8)
   {
      string note = StringFormat("{\"symbol\":\"%s\",\"session\":\"%s\",\"btr\":%.6f,\"sdr\":%.6f,\"ore\":%.6f,\"bias\":%.6f,\"setup\":\"None\",\"confidence\":0.0,\"blocked_by\":\"rsi_guard\",\"rsi\":%.2f}",
                                 symbol,
                                 session_label,
                                 btr,
                                 sdr,
                                 ore,
                                 bias_value,
                                 rsi);
      LogDecision("BWISC", "EVAL", note);
      return;
   }

   double sl_atr_distance = atr_d1 * SLmult;
   double tp_atr_distance = sl_atr_distance * r_target;

   double sl_points_raw = (sl_atr_distance > 0.0 ? sl_atr_distance / _Point : 0.0);
   double sl_points_clamped = MathMax(sl_points_raw, (double)MinStopPoints);
   slPoints = (int)MathRound(sl_points_clamped);
   if(slPoints < MinStopPoints)
      slPoints = MinStopPoints;
   tpPoints = (int)MathRound((double)slPoints * r_target);
   if(tpPoints < slPoints)
      tpPoints = slPoints;

   int direction = 0;
   double entry_price = session_snap.session_open_price;

   if(setupType == "BC")
   {
      direction = (bias_value >= 0.0 ? 1 : -1);
      if(direction == 0)
         direction = 1;
      if(direction > 0)
         entry_price = session_snap.or_high + (EntryBufferPoints * _Point);
      else
         entry_price = session_snap.or_low - (EntryBufferPoints * _Point);
   }
   else
   {
      int sdr_sign = (int)MathSign(open_lo_minus_ma);
      if(sdr_sign == 0)
         sdr_sign = (bias_value >= 0.0 ? 1 : -1);
      direction = -sdr_sign;
      if(direction == 0)
         direction = 1;
      if(direction > 0)
         entry_price = ind_snap.ma20_h1 + (EntryBufferPoints * _Point);
      else
         entry_price = ind_snap.ma20_h1 - (EntryBufferPoints * _Point);
   }

   double expected_R = r_target * MathMin(abs_bias, 1.0);
   double expected_hold = MathMax((double)ORMinutes, 45.0);
   double worst_case_risk = AccountInfoDouble(ACCOUNT_EQUITY) * (RiskPct / 100.0);

   g_last_bwisc_context.expected_R = expected_R;
   g_last_bwisc_context.expected_hold = expected_hold;
   g_last_bwisc_context.worst_case_risk = worst_case_risk;
   g_last_bwisc_context.entry_price = entry_price;
   g_last_bwisc_context.direction = direction;

   hasSetup = true;
   confidence = MathMin(abs_bias, 1.0);

   string final_note = StringFormat("{\"symbol\":\"%s\",\"session\":\"%s\",\"btr\":%.6f,\"sdr\":%.6f,\"ore\":%.6f,\"bias\":%.6f,\"setup\":\"%s\",\"confidence\":%.6f,\"rsi_h1\":%.2f,\"direction\":%d,\"entry_price\":%.5f,\"sl_atr_distance\":%.5f,\"tp_atr_distance\":%.5f,\"sl_points\":%d,\"tp_points\":%d,\"expected_R\":%.4f,\"expected_hold\":%.2f,\"worst_case_risk\":%.2f,\"atr_d1\":%.6f,\"ma20_h1\":%.6f,\"or_high\":%.5f,\"or_low\":%.5f}",
                                 symbol,
                                 session_label,
                                 btr,
                                 sdr,
                                 ore,
                                 bias_value,
                                 setupType,
                                 confidence,
                                 rsi,
                                 direction,
                                 entry_price,
                                 sl_atr_distance,
                                 tp_atr_distance,
                                 slPoints,
                                 tpPoints,
                                 expected_R,
                                 expected_hold,
                                 worst_case_risk,
                                 atr_d1,
                                 ind_snap.ma20_h1,
                                 session_snap.or_high,
                                 session_snap.or_low);
   LogDecision("BWISC", "EVAL", final_note);
}

#endif // SIGNALS_BWISC_MQH
