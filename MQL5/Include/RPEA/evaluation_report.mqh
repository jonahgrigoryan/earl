#ifndef RPEA_EVALUATION_REPORT_MQH
#define RPEA_EVALUATION_REPORT_MQH
// evaluation_report.mqh - FundingPips-style run summary + daily DD artifacts

#include <RPEA/app_context.mqh>
#include <RPEA/config.mqh>
#include <RPEA/persistence.mqh>
#include <RPEA/state.mqh>
#include <RPEA/timeutils.mqh>

#define FILE_EVALUATION_SUMMARY_REPORT (RPEA_REPORTS_DIR"/fundingpips_eval_summary.json")
#define FILE_EVALUATION_DAILY_REPORT   (RPEA_REPORTS_DIR"/fundingpips_eval_daily.csv")

struct EvaluationReportDay
{
   int      server_date;
   datetime server_midnight_ts;
   datetime baseline_capture_time;
   double   baseline_equity;
   double   baseline_balance;
   double   baseline_used;
   double   daily_floor;
   double   min_equity;
   double   end_equity;
   double   max_daily_dd_money;
   double   max_daily_dd_pct;
   bool     daily_breach;
};

struct EvaluationReportState
{
   bool     initialized;
   datetime run_started_at;
   datetime last_update_time;
   datetime last_artifact_write_time;
   double   initial_baseline;
   double   initial_equity;
   double   initial_balance;
   double   final_equity;
   double   final_balance;
   double   min_equity_seen;
   double   max_overall_dd_money;
   double   max_overall_dd_pct;
   double   min_margin_level;
   bool     any_daily_breach;
   bool     overall_breach;
   bool     target_hit;
   datetime target_hit_time;
   int      target_hit_days_traded;
   bool     pass_achieved;
   datetime pass_time;
   int      pass_days_traded;
};

static EvaluationReportState g_evaluation_report_state;
static EvaluationReportDay   g_evaluation_report_days[];

double EvaluationReport_ComputeLossPct(const double baseline, const double min_equity)
{
   if(!MathIsValidNumber(baseline) || baseline <= 0.0)
      return 0.0;

   if(!MathIsValidNumber(min_equity))
      return 0.0;

   double loss_money = baseline - min_equity;
   if(loss_money <= 0.0)
      return 0.0;

   return (loss_money / baseline) * 100.0;
}

bool EvaluationReport_PassCondition(const double current_equity,
                                    const double initial_baseline,
                                    const int days_traded,
                                    const int min_trade_days,
                                    const bool any_daily_breach,
                                    const bool overall_breach)
{
   if(any_daily_breach || overall_breach)
      return false;

   if(!MathIsValidNumber(initial_baseline) || initial_baseline <= 0.0)
      return false;

   if(!MathIsValidNumber(current_equity) || current_equity <= 0.0)
      return false;

   if(days_traded < min_trade_days)
      return false;

   double target_equity = initial_baseline * (1.0 + TargetProfitPct / 100.0);
   return (current_equity + 1e-6 >= target_equity);
}

void EvaluationReport_Reset()
{
   ZeroMemory(g_evaluation_report_state);
   ArrayResize(g_evaluation_report_days, 0);
}

double EvaluationReport_ResolveInitialBaseline(const AppContext &ctx, const ChallengeState &st, const double current_equity)
{
   double baseline = ctx.initial_baseline;
   if(!MathIsValidNumber(baseline) || baseline <= 0.0)
      baseline = st.initial_baseline;
   if(!MathIsValidNumber(baseline) || baseline <= 0.0)
      baseline = current_equity;
   return baseline;
}

double EvaluationReport_ResolveDailyBaseline(const ChallengeState &st,
                                             const double current_equity,
                                             const double current_balance)
{
   double baseline = st.baseline_today;
   if(!MathIsValidNumber(baseline) || baseline <= 0.0)
      baseline = (st.baseline_today_e0 > st.baseline_today_b0 ? st.baseline_today_e0 : st.baseline_today_b0);
   if(!MathIsValidNumber(baseline) || baseline <= 0.0)
      baseline = (current_equity > current_balance ? current_equity : current_balance);
   return baseline;
}

bool EvaluationReport_IsOverallBreachReason(const string hard_stop_reason)
{
   string normalized = hard_stop_reason;
   StringToUpper(normalized);
   return (StringFind(normalized, "OVERALL") >= 0);
}

bool EvaluationReport_IsSuccessReason(const string hard_stop_reason)
{
   string normalized = hard_stop_reason;
   StringToUpper(normalized);
   return (StringFind(normalized, "CHALLENGE COMPLETE") >= 0 ||
           StringFind(normalized, "COMPLETED SUCCESSFULLY") >= 0);
}

void EvaluationReport_EnsureCurrentDay(const datetime server_time,
                                       const double current_equity,
                                       const double current_balance,
                                       const ChallengeState &st)
{
   int server_date = TimeUtils_ServerDateInt(server_time);
   int day_count = ArraySize(g_evaluation_report_days);
   if(day_count > 0 && g_evaluation_report_days[day_count - 1].server_date == server_date)
      return;

   if(ArrayResize(g_evaluation_report_days, day_count + 1) < 0)
      return;

   EvaluationReportDay day;
   ZeroMemory(day);
   day.server_date = server_date;
   datetime expected_midnight = TimeUtils_ServerMidnight(server_time);
   bool stale_rollover_state = (st.server_midnight_ts > 0 && st.server_midnight_ts != expected_midnight);
   day.server_midnight_ts = expected_midnight;
   day.baseline_capture_time = server_time;
   if(stale_rollover_state)
   {
      day.baseline_equity = current_equity;
      day.baseline_balance = current_balance;
      day.baseline_used = (current_equity > current_balance ? current_equity : current_balance);
   }
   else
   {
      day.baseline_equity = (st.baseline_today_e0 > 0.0 ? st.baseline_today_e0 : current_equity);
      day.baseline_balance = (st.baseline_today_b0 > 0.0 ? st.baseline_today_b0 : current_balance);
      day.baseline_used = EvaluationReport_ResolveDailyBaseline(st, current_equity, current_balance);
   }
   double daily_cap_pct = Config_GetEffectiveDailyLossCapPct();
   day.daily_floor = day.baseline_used * (1.0 - daily_cap_pct / 100.0);
   day.min_equity = current_equity;
   day.end_equity = current_equity;
   day.max_daily_dd_money = MathMax(0.0, day.baseline_used - current_equity);
   day.max_daily_dd_pct = EvaluationReport_ComputeLossPct(day.baseline_used, current_equity);
   day.daily_breach = st.daily_floor_breached || (current_equity <= day.daily_floor + 1e-6);
   g_evaluation_report_days[day_count] = day;

   if(day.daily_breach)
      g_evaluation_report_state.any_daily_breach = true;
}

void EvaluationReport_UpdateSnapshot(const datetime server_time,
                                     const double current_equity,
                                     const double current_balance,
                                     const double initial_baseline,
                                     const ChallengeState &st)
{
   if(!g_evaluation_report_state.initialized)
   {
      g_evaluation_report_state.initialized = true;
      g_evaluation_report_state.run_started_at = server_time;
      g_evaluation_report_state.initial_baseline = initial_baseline;
      g_evaluation_report_state.initial_equity = current_equity;
      g_evaluation_report_state.initial_balance = current_balance;
      g_evaluation_report_state.final_equity = current_equity;
      g_evaluation_report_state.final_balance = current_balance;
      g_evaluation_report_state.min_equity_seen = current_equity;
      g_evaluation_report_state.min_margin_level = 0.0;
   }

   EvaluationReport_EnsureCurrentDay(server_time, current_equity, current_balance, st);

   g_evaluation_report_state.last_update_time = server_time;
   g_evaluation_report_state.final_equity = current_equity;
   g_evaluation_report_state.final_balance = current_balance;

   if(current_equity < g_evaluation_report_state.min_equity_seen)
      g_evaluation_report_state.min_equity_seen = current_equity;

   double overall_dd_money = MathMax(0.0, g_evaluation_report_state.initial_baseline - current_equity);
   double overall_dd_pct = EvaluationReport_ComputeLossPct(g_evaluation_report_state.initial_baseline, current_equity);
   if(overall_dd_money > g_evaluation_report_state.max_overall_dd_money)
      g_evaluation_report_state.max_overall_dd_money = overall_dd_money;
   if(overall_dd_pct > g_evaluation_report_state.max_overall_dd_pct)
      g_evaluation_report_state.max_overall_dd_pct = overall_dd_pct;

   double overall_floor = g_evaluation_report_state.initial_baseline * (1.0 - OverallLossCapPct / 100.0);
   if(current_equity <= overall_floor + 1e-6 || EvaluationReport_IsOverallBreachReason(st.hard_stop_reason))
      g_evaluation_report_state.overall_breach = true;

   int day_index = ArraySize(g_evaluation_report_days) - 1;
   if(day_index >= 0)
   {
      EvaluationReportDay day = g_evaluation_report_days[day_index];
      if(current_equity < day.min_equity)
         day.min_equity = current_equity;
      day.end_equity = current_equity;
      double day_dd_money = MathMax(0.0, day.baseline_used - day.min_equity);
      double day_dd_pct = EvaluationReport_ComputeLossPct(day.baseline_used, day.min_equity);
      if(day_dd_money > day.max_daily_dd_money)
         day.max_daily_dd_money = day_dd_money;
      if(day_dd_pct > day.max_daily_dd_pct)
         day.max_daily_dd_pct = day_dd_pct;
      if(st.daily_floor_breached || current_equity <= day.daily_floor + 1e-6)
         day.daily_breach = true;
      g_evaluation_report_days[day_index] = day;

      if(day.daily_breach)
         g_evaluation_report_state.any_daily_breach = true;
   }

   double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(MathIsValidNumber(margin_level) && margin_level > 0.0)
   {
      if(g_evaluation_report_state.min_margin_level <= 0.0 ||
         margin_level < g_evaluation_report_state.min_margin_level)
      {
         g_evaluation_report_state.min_margin_level = margin_level;
      }
   }

   double target_equity = g_evaluation_report_state.initial_baseline * (1.0 + TargetProfitPct / 100.0);
   if(!g_evaluation_report_state.target_hit && current_equity + 1e-6 >= target_equity)
   {
      g_evaluation_report_state.target_hit = true;
      g_evaluation_report_state.target_hit_time = server_time;
      g_evaluation_report_state.target_hit_days_traded = st.gDaysTraded;
   }

   if(!g_evaluation_report_state.pass_achieved &&
      EvaluationReport_PassCondition(current_equity,
                                     g_evaluation_report_state.initial_baseline,
                                     st.gDaysTraded,
                                     Config_GetMinTradeDaysRequired(),
                                     g_evaluation_report_state.any_daily_breach,
                                     g_evaluation_report_state.overall_breach))
   {
      g_evaluation_report_state.pass_achieved = true;
      g_evaluation_report_state.pass_time = server_time;
      g_evaluation_report_state.pass_days_traded = st.gDaysTraded;
   }
   else if(!g_evaluation_report_state.pass_achieved &&
           EvaluationReport_IsSuccessReason(st.hard_stop_reason) &&
           !g_evaluation_report_state.any_daily_breach &&
           !g_evaluation_report_state.overall_breach)
   {
      g_evaluation_report_state.pass_achieved = true;
      g_evaluation_report_state.pass_time = (st.hard_stop_time > 0 ? st.hard_stop_time : server_time);
      g_evaluation_report_state.pass_days_traded = st.gDaysTraded;
   }
}

void EvaluationReport_Init(const AppContext &ctx)
{
   EvaluationReport_Reset();

   ChallengeState st = State_Get();
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   datetime server_time = TimeCurrent();
   if(server_time <= 0 && ctx.current_server_time > 0)
      server_time = ctx.current_server_time;
   double initial_baseline = EvaluationReport_ResolveInitialBaseline(ctx, st, current_equity);

   EvaluationReport_UpdateSnapshot(server_time,
                                   current_equity,
                                   current_balance,
                                   initial_baseline,
                                   st);
}

void EvaluationReport_Update(const AppContext &ctx)
{
   ChallengeState st = State_Get();
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   datetime server_time = TimeCurrent();
   if(server_time <= 0 && ctx.current_server_time > 0)
      server_time = ctx.current_server_time;
   double initial_baseline = EvaluationReport_ResolveInitialBaseline(ctx, st, current_equity);

   EvaluationReport_UpdateSnapshot(server_time,
                                   current_equity,
                                   current_balance,
                                   initial_baseline,
                                   st);
}

string EvaluationReport_BoolToJson(const bool value)
{
   return (value ? "true" : "false");
}

double EvaluationReport_GetMaxDailyDdMoney()
{
   double result = 0.0;
   int count = ArraySize(g_evaluation_report_days);
   for(int i = 0; i < count; i++)
   {
      if(g_evaluation_report_days[i].max_daily_dd_money > result)
         result = g_evaluation_report_days[i].max_daily_dd_money;
   }
   return result;
}

double EvaluationReport_GetMaxDailyDdPct()
{
   double result = 0.0;
   int count = ArraySize(g_evaluation_report_days);
   for(int i = 0; i < count; i++)
   {
      if(g_evaluation_report_days[i].max_daily_dd_pct > result)
         result = g_evaluation_report_days[i].max_daily_dd_pct;
   }
   return result;
}

void EvaluationReport_CollectTradeCounts(int &entries_total,
                                         int &entries_xauusd,
                                         int &entries_eurusd,
                                         int &entries_other)
{
   entries_total = 0;
   entries_xauusd = 0;
   entries_eurusd = 0;
   entries_other = 0;

   if(!HistorySelect(0, TimeCurrent()))
      return;

   int deals_total = HistoryDealsTotal();
   for(int i = 0; i < deals_total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN)
         continue;

      ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
      if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL)
         continue;

      entries_total++;
      string symbol = HistoryDealGetString(deal, DEAL_SYMBOL);
      if(symbol == "XAUUSD" || symbol == "XAUEUR")
         entries_xauusd++;
      else if(symbol == "EURUSD")
         entries_eurusd++;
      else
         entries_other++;
   }
}

string EvaluationReport_FormatServerDate(const int server_date)
{
   int year = server_date / 10000;
   int month = (server_date / 100) % 100;
   int day = server_date % 100;
   return StringFormat("%04d-%02d-%02d", year, month, day);
}

string EvaluationReport_BuildDailyCsv()
{
   string csv = "server_date,server_midnight_ts,baseline_capture_time,baseline_equity,baseline_balance,baseline_used,daily_floor,min_equity,end_equity,max_daily_dd_money,max_daily_dd_pct,daily_breach\n";
   int count = ArraySize(g_evaluation_report_days);
   for(int i = 0; i < count; i++)
   {
      EvaluationReportDay day = g_evaluation_report_days[i];
      csv += StringFormat("%s,%s,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.6f,%s\n",
                          EvaluationReport_FormatServerDate(day.server_date),
                          Persistence_FormatIso8601(day.server_midnight_ts),
                          Persistence_FormatIso8601(day.baseline_capture_time),
                          day.baseline_equity,
                          day.baseline_balance,
                          day.baseline_used,
                          day.daily_floor,
                          day.min_equity,
                          day.end_equity,
                          day.max_daily_dd_money,
                          day.max_daily_dd_pct,
                          (day.daily_breach ? "true" : "false"));
   }
   return csv;
}

string EvaluationReport_BuildSummaryJson(const int deinit_reason)
{
   ChallengeState st = State_Get();

   int trades_total = 0;
   int trades_xauusd = 0;
   int trades_eurusd = 0;
   int trades_other = 0;
   EvaluationReport_CollectTradeCounts(trades_total, trades_xauusd, trades_eurusd, trades_other);

   double target_equity = g_evaluation_report_state.initial_baseline * (1.0 + TargetProfitPct / 100.0);
   double final_return_pct = 0.0;
   if(g_evaluation_report_state.initial_baseline > 0.0)
      final_return_pct = ((g_evaluation_report_state.final_equity / g_evaluation_report_state.initial_baseline) - 1.0) * 100.0;

   int observed_days = ArraySize(g_evaluation_report_days);
   double trades_per_observed_day = 0.0;
   if(observed_days > 0)
      trades_per_observed_day = (double)trades_total / (double)observed_days;

   string json = "{\n";
   json += "  \"schema_version\": 1,\n";
   json += "  \"generated_at\": \"" + Persistence_EscapeJson(Persistence_FormatIso8601(TimeCurrent())) + "\",\n";
   json += "  \"deinit_reason\": " + IntegerToString(deinit_reason) + ",\n";
   json += "  \"run_started_at\": \"" + Persistence_EscapeJson(Persistence_FormatIso8601(g_evaluation_report_state.run_started_at)) + "\",\n";
   json += "  \"last_update_time\": \"" + Persistence_EscapeJson(Persistence_FormatIso8601(g_evaluation_report_state.last_update_time)) + "\",\n";
   json += "  \"initial_baseline\": " + DoubleToString(g_evaluation_report_state.initial_baseline, 2) + ",\n";
   json += "  \"initial_equity\": " + DoubleToString(g_evaluation_report_state.initial_equity, 2) + ",\n";
   json += "  \"initial_balance\": " + DoubleToString(g_evaluation_report_state.initial_balance, 2) + ",\n";
   json += "  \"final_equity\": " + DoubleToString(g_evaluation_report_state.final_equity, 2) + ",\n";
   json += "  \"final_balance\": " + DoubleToString(g_evaluation_report_state.final_balance, 2) + ",\n";
   json += "  \"final_return_pct\": " + DoubleToString(final_return_pct, 6) + ",\n";
   json += "  \"target_profit_pct\": " + DoubleToString(TargetProfitPct, 2) + ",\n";
   json += "  \"target_equity\": " + DoubleToString(target_equity, 2) + ",\n";
   json += "  \"min_trade_days_required\": " + IntegerToString(Config_GetMinTradeDaysRequired()) + ",\n";
   json += "  \"days_traded\": " + IntegerToString(st.gDaysTraded) + ",\n";
   json += "  \"min_trade_days_met\": " + EvaluationReport_BoolToJson(st.gDaysTraded >= Config_GetMinTradeDaysRequired()) + ",\n";
   json += "  \"target_hit\": " + EvaluationReport_BoolToJson(g_evaluation_report_state.target_hit) + ",\n";
   json += "  \"target_hit_time\": \"" + Persistence_EscapeJson(Persistence_FormatIso8601(g_evaluation_report_state.target_hit_time)) + "\",\n";
   json += "  \"target_hit_days_traded\": " + IntegerToString(g_evaluation_report_state.target_hit_days_traded) + ",\n";
   json += "  \"pass\": " + EvaluationReport_BoolToJson(g_evaluation_report_state.pass_achieved) + ",\n";
   json += "  \"pass_time\": \"" + Persistence_EscapeJson(Persistence_FormatIso8601(g_evaluation_report_state.pass_time)) + "\",\n";
   json += "  \"pass_days_traded\": " + IntegerToString(g_evaluation_report_state.pass_days_traded) + ",\n";
   json += "  \"max_daily_dd_money\": " + DoubleToString(EvaluationReport_GetMaxDailyDdMoney(), 2) + ",\n";
   json += "  \"max_daily_dd_pct\": " + DoubleToString(EvaluationReport_GetMaxDailyDdPct(), 6) + ",\n";
   json += "  \"max_overall_dd_money\": " + DoubleToString(g_evaluation_report_state.max_overall_dd_money, 2) + ",\n";
   json += "  \"max_overall_dd_pct\": " + DoubleToString(g_evaluation_report_state.max_overall_dd_pct, 6) + ",\n";
   json += "  \"any_daily_breach\": " + EvaluationReport_BoolToJson(g_evaluation_report_state.any_daily_breach) + ",\n";
   json += "  \"overall_breach\": " + EvaluationReport_BoolToJson(g_evaluation_report_state.overall_breach) + ",\n";
   json += "  \"hard_stop_reason\": \"" + Persistence_EscapeJson(st.hard_stop_reason) + "\",\n";
   json += "  \"hard_stop_time\": \"" + Persistence_EscapeJson(Persistence_FormatIso8601(st.hard_stop_time)) + "\",\n";
   json += "  \"hard_stop_equity\": " + DoubleToString(st.hard_stop_equity, 2) + ",\n";
   json += "  \"micro_mode_active\": " + EvaluationReport_BoolToJson(st.micro_mode) + ",\n";
   json += "  \"min_margin_level\": " + DoubleToString(g_evaluation_report_state.min_margin_level, 6) + ",\n";
   json += "  \"observed_server_days\": " + IntegerToString(observed_days) + ",\n";
   json += "  \"trades_total\": " + IntegerToString(trades_total) + ",\n";
   json += "  \"trades_xauusd\": " + IntegerToString(trades_xauusd) + ",\n";
   json += "  \"trades_eurusd\": " + IntegerToString(trades_eurusd) + ",\n";
   json += "  \"trades_other\": " + IntegerToString(trades_other) + ",\n";
   json += "  \"trades_per_observed_day\": " + DoubleToString(trades_per_observed_day, 6) + "\n";
   json += "}\n";
   return json;
}

bool EvaluationReport_WriteTextFile(const string path, const string contents)
{
   int handle = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   FileWriteString(handle, contents);
   FileClose(handle);
   return true;
}

bool EvaluationReport_WriteArtifacts(const AppContext &ctx,
                                     const int deinit_reason,
                                     const bool emit_log = true)
{
   if(!g_evaluation_report_state.initialized)
      EvaluationReport_Init(ctx);
   else
      EvaluationReport_Update(ctx);

   Persistence_EnsureFolders();

   string summary_json = EvaluationReport_BuildSummaryJson(deinit_reason);
   string daily_csv = EvaluationReport_BuildDailyCsv();

   bool summary_ok = EvaluationReport_WriteTextFile(FILE_EVALUATION_SUMMARY_REPORT, summary_json);
   bool daily_ok = EvaluationReport_WriteTextFile(FILE_EVALUATION_DAILY_REPORT, daily_csv);

   if(summary_ok && daily_ok)
      g_evaluation_report_state.last_artifact_write_time = TimeCurrent();

   if(emit_log)
   {
      PrintFormat("[EvaluationReport] summary=%s daily=%s",
                  summary_ok ? FILE_EVALUATION_SUMMARY_REPORT : "write_failed",
                  daily_ok ? FILE_EVALUATION_DAILY_REPORT : "write_failed");
   }

   return (summary_ok && daily_ok);
}

void EvaluationReport_MaybeWriteTesterSnapshot(const AppContext &ctx)
{
   if(!MQLInfoInteger(MQL_TESTER))
      return;

   datetime server_time = TimeCurrent();
   if(server_time <= 0 && ctx.current_server_time > 0)
      server_time = ctx.current_server_time;

   if(g_evaluation_report_state.last_artifact_write_time > 0 &&
      server_time - g_evaluation_report_state.last_artifact_write_time < 3600)
   {
      return;
   }

   EvaluationReport_WriteArtifacts(ctx, 0, false);
}

#ifdef RPEA_TEST_RUNNER
void EvaluationReport_TestReset()
{
   EvaluationReport_Reset();
}

void EvaluationReport_TestInitSnapshot(const datetime server_time,
                                       const double current_equity,
                                       const double current_balance,
                                       const double initial_baseline,
                                       const ChallengeState &st)
{
   EvaluationReport_Reset();
   EvaluationReport_UpdateSnapshot(server_time,
                                   current_equity,
                                   current_balance,
                                   initial_baseline,
                                   st);
}

void EvaluationReport_TestUpdateSnapshot(const datetime server_time,
                                         const double current_equity,
                                         const double current_balance,
                                         const ChallengeState &st)
{
   double initial_baseline = g_evaluation_report_state.initial_baseline;
   if(initial_baseline <= 0.0)
      initial_baseline = st.initial_baseline;
   EvaluationReport_UpdateSnapshot(server_time,
                                   current_equity,
                                   current_balance,
                                   initial_baseline,
                                   st);
}

int EvaluationReport_TestGetDayCount()
{
   return ArraySize(g_evaluation_report_days);
}

bool EvaluationReport_TestGetDayRecord(const int index, EvaluationReportDay &out_day)
{
   int count = ArraySize(g_evaluation_report_days);
   if(index < 0 || index >= count)
      return false;
   out_day = g_evaluation_report_days[index];
   return true;
}

double EvaluationReport_TestGetMaxOverallDdPct()
{
   return g_evaluation_report_state.max_overall_dd_pct;
}

bool EvaluationReport_TestGetAnyDailyBreach()
{
   return g_evaluation_report_state.any_daily_breach;
}

bool EvaluationReport_TestGetOverallBreach()
{
   return g_evaluation_report_state.overall_breach;
}

bool EvaluationReport_TestGetTargetHit()
{
   return g_evaluation_report_state.target_hit;
}

int EvaluationReport_TestGetTargetHitDays()
{
   return g_evaluation_report_state.target_hit_days_traded;
}

bool EvaluationReport_TestGetPassAchieved()
{
   return g_evaluation_report_state.pass_achieved;
}

int EvaluationReport_TestGetPassDays()
{
   return g_evaluation_report_state.pass_days_traded;
}
#endif

#endif // RPEA_EVALUATION_REPORT_MQH
