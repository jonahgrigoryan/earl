#!/usr/bin/env python3
"""FundingPips Phase A artifact-first research pipeline."""

from __future__ import annotations

import argparse
import csv
import dataclasses
import html
import json
import math
import shutil
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Iterable

try:
   from tools import fundingpips_hpo as hpo
except ModuleNotFoundError:  # pragma: no cover - script execution fallback
   sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
   from tools import fundingpips_hpo as hpo


DEFAULT_RESEARCH_ROOT = Path(".tmp") / "fundingpips_phase_a_research"
DEFAULT_RESEARCH_NAME = "master_d0e5558_phase_a"
DEFAULT_HOLDOUT_DIR = (
   Path(".tmp")
   / "fundingpips_official_validation"
   / "master_phase5_holdout_rule3_20251101_20260228__19a3b91f4d7f9f7c"
)
DEFAULT_CORROBORATION_DIR = (
   Path(".tmp")
   / "fundingpips_official_validation"
   / "master_phase5_champion_contiguous_public_rule3_20250603_20251031__e2ac77d835c79480"
)

PRIMARY_ROLE = "holdout_primary_truth"
SECONDARY_ROLE = "contiguous_public_rule3_secondary_corroboration"
PHASE_SOURCE = "Phase A"
ACCOUNT_BASELINE_MONEY = 10000.0
PCT_CONVERSION = 100.0 / ACCOUNT_BASELINE_MONEY
TIME_FORMAT_LOG = "%Y-%m-%d %H:%M:%S"
TIME_FORMAT_REPORT = "%Y.%m.%d %H:%M:%S"
REQUIRED_TRADE_FIELDS = (
   "candidate_id",
   "intent_id",
   "entry_ticket",
   "symbol",
   "strategy",
   "entry_time",
   "exit_time",
   "entry_price",
   "exit_price",
   "volume",
   "realized_pnl",
   "hold_minutes",
   "theoretical_r",
   "realized_r",
   "friction_r",
   "exit_reason_class",
   "exit_reason_exact",
   "close_source",
)
DAILY_SOURCE_FIELDS = (
   "server_date",
   "server_midnight_ts",
   "baseline_capture_time",
   "baseline_equity",
   "baseline_balance",
   "baseline_used",
   "daily_floor",
   "min_equity",
   "end_equity",
   "max_daily_dd_money",
   "max_daily_dd_pct",
   "daily_breach",
)
DECISION_ROWS_RELEVANT = frozenset(
   {
      ("MetaPolicy", "EVAL"),
      ("Risk", "SIZING"),
      ("Allocator", "ORDER_PLAN"),
      ("OrderEngine", "INTENT_ACCEPT"),
      ("OrderEngine", "EXECUTE_ORDER_SUCCESS"),
      ("Scheduler", "PLACE_OK"),
      ("Scheduler", "PLACE_FAIL"),
      ("Scheduler", "MR_TIMESTOP"),
   }
)
DECISION_ROWS_CONTEXT_ONLY = frozenset(
   {
      ("Scheduler", "ANOMALY_EVAL"),
      ("Indicators", "SNAPSHOT"),
      ("BWISC", "EVAL"),
   }
)
EVENT_ROWS_RELEVANT = frozenset({"ORDER_INTENT_EXECUTED"})
GATE_ROWS_RELEVANT = frozenset(
   {
      ("Liquidity", "GATED"),
      ("Scheduler", "GATED"),
      ("MetaPolicy", "EVAL"),
      ("Allocator", "ORDER_PLAN"),
   }
)


class PhaseABlocked(RuntimeError):
   """Raised when the pinned Phase A contracts cannot be satisfied safely."""


@dataclasses.dataclass(frozen=True)
class PhaseARunInput:
   id: str
   baseline_role: str
   root: Path
   manifest_path: Path
   summary_path: Path
   daily_path: Path
   report_path: Path
   decision_log_paths: tuple[Path, ...]
   event_log_paths: tuple[Path, ...]


@dataclasses.dataclass(frozen=True)
class DecisionRow:
   run_id: str
   baseline_role: str
   source_path: Path
   source_row: int
   ts: datetime
   ts_text: str
   component: str
   message: str
   level: int
   fields: dict[str, Any]
   symbol: str | None


@dataclasses.dataclass(frozen=True)
class EventRow:
   run_id: str
   baseline_role: str
   source_path: Path
   source_row: int
   ts: datetime
   ts_text: str
   event: str
   component: str
   level: int
   fields: dict[str, Any]


@dataclasses.dataclass(frozen=True)
class ReportOrderRow:
   row_index: int
   open_time: datetime
   open_time_text: str
   order_id: int
   symbol: str
   order_type: str
   requested_volume: float | None
   filled_volume: float | None
   price: float | None
   sl: float | None
   tp: float | None
   fill_time: datetime | None
   fill_time_text: str | None
   state: str
   comment: str


@dataclasses.dataclass(frozen=True)
class ReportDealRow:
   row_index: int
   time: datetime
   time_text: str
   deal_id: int
   symbol: str
   deal_type: str
   direction: str
   volume: float | None
   price: float | None
   order_id: int | None
   commission: float | None
   swap: float | None
   profit: float | None
   balance: float | None
   comment: str


class HtmlTableParser(HTMLParser):
   """Minimal HTML table parser for MT5 report exports."""

   def __init__(self) -> None:
      super().__init__()
      self.tables: list[list[list[str]]] = []
      self._table_stack = 0
      self._in_row = False
      self._in_cell = False
      self._current_table: list[list[str]] | None = None
      self._current_row: list[str] | None = None
      self._current_cell_parts: list[str] = []

   def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
      del attrs
      normalized = tag.lower()
      if normalized == "table":
         self._table_stack += 1
         if self._table_stack == 1:
            self._current_table = []
      elif normalized == "tr" and self._table_stack == 1:
         self._in_row = True
         self._current_row = []
      elif normalized in ("td", "th") and self._table_stack == 1 and self._in_row:
         self._in_cell = True
         self._current_cell_parts = []
      elif normalized == "br" and self._table_stack == 1 and self._in_cell:
         self._current_cell_parts.append("\n")

   def handle_endtag(self, tag: str) -> None:
      normalized = tag.lower()
      if normalized in ("td", "th") and self._table_stack == 1 and self._in_row and self._current_row is not None:
         cell_text = html.unescape("".join(self._current_cell_parts)).replace("\xa0", " ").strip()
         self._current_row.append(cell_text)
         self._in_cell = False
         self._current_cell_parts = []
      elif normalized == "tr" and self._table_stack == 1:
         if self._current_table is not None and self._current_row is not None and self._current_row:
            self._current_table.append(self._current_row)
         self._in_row = False
         self._current_row = None
      elif normalized == "table":
         if self._table_stack == 1 and self._current_table is not None:
            self.tables.append(self._current_table)
            self._current_table = None
         self._table_stack = max(self._table_stack - 1, 0)

   def handle_data(self, data: str) -> None:
      if self._table_stack == 1 and self._in_cell:
         self._current_cell_parts.append(data)


def repo_root() -> Path:
   return Path(__file__).resolve().parents[1]


def utc_now_iso() -> str:
   return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def stable_json(data: Any) -> str:
   return json.dumps(data, sort_keys=True, indent=2)


def safe_relative(path: Path) -> str:
   try:
      return str(path.resolve().relative_to(repo_root()))
   except ValueError:
      return str(path.resolve())


def format_ts(value: datetime) -> str:
   return value.strftime("%Y-%m-%dT%H:%M:%S")


def parse_log_timestamp(date_value: str, time_value: str) -> datetime:
   return datetime.strptime(f"{date_value} {time_value}", TIME_FORMAT_LOG)


def parse_report_timestamp(value: str) -> datetime:
   return datetime.strptime(value, TIME_FORMAT_REPORT)


def parse_json_fields(value: str, source_path: Path, source_row: int) -> dict[str, Any]:
   try:
      parsed = json.loads(value or "{}")
   except json.JSONDecodeError as exc:  # pragma: no cover - defensive
      raise PhaseABlocked(f"Malformed fields_json in {source_path} line {source_row}: {exc}") from exc
   if not isinstance(parsed, dict):
      raise PhaseABlocked(f"Expected JSON object in {source_path} line {source_row}")
   return parsed


def extract_json_string(raw_json: str, key: str) -> str | None:
   marker = f'"{key}":'
   start = raw_json.find(marker)
   if start < 0:
      return None
   index = start + len(marker)
   if index >= len(raw_json) or raw_json[index] != '"':
      return None
   index += 1
   end = raw_json.find('"', index)
   if end < 0:
      return None
   return raw_json[index:end]


def extract_json_bool(raw_json: str, key: str) -> bool | None:
   marker = f'"{key}":'
   start = raw_json.find(marker)
   if start < 0:
      return None
   index = start + len(marker)
   if raw_json.startswith("true", index):
      return True
   if raw_json.startswith("false", index):
      return False
   return None


def coerce_bool(value: Any) -> bool | None:
   if isinstance(value, bool):
      return value
   if isinstance(value, str):
      normalized = value.strip().lower()
      if normalized in ("true", "1"):
         return True
      if normalized in ("false", "0"):
         return False
   return None


def coerce_int(value: Any) -> int | None:
   if isinstance(value, bool):
      return None
   if isinstance(value, int):
      return value
   if isinstance(value, float) and value.is_integer():
      return int(value)
   if isinstance(value, str):
      stripped = value.strip().replace(",", "")
      if not stripped:
         return None
      try:
         return int(stripped)
      except ValueError:
         return None
   return None


def coerce_float(value: Any) -> float | None:
   if isinstance(value, bool):
      return None
   if isinstance(value, (int, float)):
      return float(value)
   if isinstance(value, str):
      stripped = value.strip().replace(",", "").replace(" ", "")
      if not stripped:
         return None
      try:
         return float(stripped)
      except ValueError:
         return None
   return None


def bool_text(value: bool | None) -> str:
   if value is None:
      return ""
   return "true" if value else "false"


def maybe_number_text(value: float | int | None, places: int = 6) -> str:
   if value is None:
      return ""
   if isinstance(value, int):
      return str(value)
   return f"{float(value):.{places}f}"


def normalize_candidate_text(value: Any) -> str:
   if value is None:
      return ""
   return " ".join(str(value).strip().split())


def normalize_price_component(value: Any) -> str:
   number = coerce_float(value)
   if number is None:
      return ""
   return f"{number:.5f}"


def build_candidate_id(
   decision_ts: str,
   symbol: str,
   strategy: str,
   setup_type: str,
   entry_price: Any,
   sl: Any,
   tp: Any,
   comment: str,
) -> str:
   return "|".join(
      (
         normalize_candidate_text(decision_ts),
         normalize_candidate_text(symbol),
         normalize_candidate_text(strategy),
         normalize_candidate_text(setup_type),
         normalize_price_component(entry_price),
         normalize_price_component(sl),
         normalize_price_component(tp),
         normalize_candidate_text(comment),
      )
   )


def safe_mean(values: Iterable[float]) -> float | None:
   items = [float(value) for value in values]
   if not items:
      return None
   return statistics.fmean(items)


def safe_median(values: Iterable[float]) -> float | None:
   items = [float(value) for value in values]
   if not items:
      return None
   return statistics.median(items)


def resolve_manifest_path(path_value: Any, run_root: Path) -> Path:
   if not isinstance(path_value, str) or not path_value.strip():
      raise PhaseABlocked(f"Missing artifact path in manifest under {run_root}")
   candidate = Path(path_value)
   if candidate.is_absolute():
      return candidate
   return (run_root / candidate).resolve()


def load_phase_a_run_input(*, root: Path, run_id: str, baseline_role: str) -> PhaseARunInput:
   manifest_path = root / "run_manifest.json"
   if not manifest_path.exists():
      raise PhaseABlocked(f"Run manifest missing: {manifest_path}")
   manifest = hpo.load_json_file(manifest_path)

   summary_path = resolve_manifest_path(manifest.get("collected_summary"), root)
   daily_path = resolve_manifest_path(manifest.get("collected_daily"), root)
   report_value = manifest.get("collected_report")
   report_path = resolve_manifest_path(report_value, root) if report_value else next(
      iter(sorted((root / "collected").glob("*.xml*"))),
      None,
   )
   if report_path is None:
      raise PhaseABlocked(f"Collected MT5 report missing under {root}")

   decision_log_paths = tuple(
      resolve_manifest_path(path_value, root)
      for path_value in manifest.get("collected_decision_logs", [])
   )
   event_log_paths = tuple(
      resolve_manifest_path(path_value, root)
      for path_value in manifest.get("collected_event_logs", [])
   )
   if not decision_log_paths:
      raise PhaseABlocked(f"No decision logs listed in {manifest_path}")
   if not event_log_paths:
      raise PhaseABlocked(f"No event logs listed in {manifest_path}")

   return PhaseARunInput(
      id=run_id,
      baseline_role=baseline_role,
      root=root.resolve(),
      manifest_path=manifest_path.resolve(),
      summary_path=summary_path.resolve(),
      daily_path=daily_path.resolve(),
      report_path=report_path.resolve(),
      decision_log_paths=tuple(path.resolve() for path in decision_log_paths),
      event_log_paths=tuple(path.resolve() for path in event_log_paths),
   )


def build_default_runs() -> tuple[PhaseARunInput, ...]:
   return (
      load_phase_a_run_input(
         root=(repo_root() / DEFAULT_HOLDOUT_DIR),
         run_id="holdout",
         baseline_role=PRIMARY_ROLE,
      ),
      load_phase_a_run_input(
         root=(repo_root() / DEFAULT_CORROBORATION_DIR),
         run_id="contiguous_public_rule3",
         baseline_role=SECONDARY_ROLE,
      ),
   )


def iter_log_lines(path: Path, *, expected_header: str) -> Iterable[tuple[int, list[str]]]:
   with path.open("r", encoding="utf-8", newline="") as handle:
      for line_number, raw_line in enumerate(handle, start=1):
         line = raw_line.rstrip("\r\n")
         if line_number == 1:
            if line != expected_header:
               raise PhaseABlocked(f"Unexpected log header in {path}: {line}")
            continue
         if not line:
            continue
         parts = line.split(",", 6)
         if len(parts) != 7:
            raise PhaseABlocked(f"Malformed log row in {path} line {line_number}: {line}")
         yield line_number, parts


def iter_rg_log_lines(search_root: Path, *, glob_pattern: str, patterns: tuple[str, ...]) -> Iterable[tuple[Path, int, list[str]]]:
   command = [
      "rg",
      "--json",
      "-n",
      "-F",
      "-g",
      glob_pattern,
   ]
   for pattern in patterns:
      command.extend(["-e", pattern])
   command.append(str(search_root))

   try:
      process = subprocess.Popen(
         command,
         cwd=str(repo_root()),
         stdout=subprocess.PIPE,
         stderr=subprocess.PIPE,
         text=True,
         encoding="utf-8",
         errors="replace",
      )
   except FileNotFoundError:
      return

   assert process.stdout is not None
   for raw_line in process.stdout:
      payload = json.loads(raw_line)
      if payload.get("type") != "match":
         continue
      data = payload["data"]
      text = data["lines"]["text"].rstrip("\r\n")
      parts = text.split(",", 6)
      if len(parts) != 7:
         raise PhaseABlocked(f"Malformed rg-filtered row under {search_root}: {text}")
      path_text = data["path"]["text"]
      source_path = Path(path_text)
      if not source_path.is_absolute():
         source_path = (repo_root() / source_path).resolve()
      yield source_path, int(data["line_number"]), parts

   stderr_text = process.stderr.read() if process.stderr is not None else ""
   return_code = process.wait()
   if return_code not in (0, 1):
      raise PhaseABlocked(f"rg failed while scanning {search_root}: {stderr_text.strip()}")


def parse_decision_logs(run_input: PhaseARunInput) -> list[DecisionRow]:
   rows: list[DecisionRow] = []
   last_symbol_context: str | None = None

   for source_path in sorted(run_input.decision_log_paths):
      for source_row, parts in iter_log_lines(
         source_path,
         expected_header="date,time,event,component,level,message,fields_json",
      ):
            date_value, time_value, event_value, component_value, level_value, message_value, fields_value = parts
            if event_value != "DECISION":
               raise PhaseABlocked(f"Unexpected event type in decision log {source_path} line {source_row}: {event_value}")
            row_kind = (component_value, message_value)
            if row_kind not in DECISION_ROWS_RELEVANT and row_kind not in DECISION_ROWS_CONTEXT_ONLY:
               continue
            fields = parse_json_fields(fields_value, source_path, source_row)
            explicit_symbol = normalize_candidate_text(
               fields.get("symbol") or fields.get("exec_symbol") or fields.get("signal_symbol")
            )
            symbol = explicit_symbol or None
            if symbol is None and component_value == "Scheduler" and message_value == "GATED":
               symbol = last_symbol_context
            if explicit_symbol:
               last_symbol_context = explicit_symbol
            if row_kind not in DECISION_ROWS_RELEVANT:
               continue
            if row_kind == ("MetaPolicy", "EVAL") and normalize_candidate_text(fields.get("choice")) == "Skip":
               continue

            ts = parse_log_timestamp(date_value, time_value)
            rows.append(
               DecisionRow(
                  run_id=run_input.id,
                  baseline_role=run_input.baseline_role,
                  source_path=source_path,
                  source_row=source_row,
                  ts=ts,
                  ts_text=format_ts(ts),
                  component=component_value,
                  message=message_value,
                  level=int(level_value),
                  fields=fields,
                  symbol=symbol,
               )
            )

   rows.sort(key=lambda item: (item.ts, str(item.source_path), item.source_row))

   unresolved_scheduler = [
      item
      for item in rows
      if item.component == "Scheduler" and item.message == "GATED" and item.symbol is None
   ]
   if unresolved_scheduler:
      first = unresolved_scheduler[0]
      raise PhaseABlocked(
         f"Scheduler.GATED row missing symbol context in {first.source_path} line {first.source_row}"
      )
   return rows


def parse_event_logs(run_input: PhaseARunInput) -> list[EventRow]:
   rows: list[EventRow] = []
   for source_path in sorted(run_input.event_log_paths):
      for source_row, parts in iter_log_lines(
         source_path,
         expected_header="date,time,event,component,level,message,fields_json",
      ):
            date_value, time_value, event_value, component_value, level_value, message_value, fields_value = parts
            if event_value not in EVENT_ROWS_RELEVANT:
               continue
            fields = parse_json_fields(fields_value, source_path, source_row)
            ts = parse_log_timestamp(date_value, time_value)
            rows.append(
               EventRow(
                  run_id=run_input.id,
                  baseline_role=run_input.baseline_role,
                  source_path=source_path,
                  source_row=source_row,
                  ts=ts,
                  ts_text=format_ts(ts),
                  event=event_value,
                  component=component_value,
                  level=int(level_value),
                  fields=fields,
               )
            )
   rows.sort(key=lambda item: (item.ts, str(item.source_path), item.source_row))
   return rows


def parse_report_number(value: str) -> float | None:
   cleaned = value.replace("\xa0", " ").replace(",", "").replace(" ", "").strip()
   if not cleaned:
      return None
   try:
      return float(cleaned)
   except ValueError:
      return None


def parse_order_volume_cell(value: str) -> tuple[float | None, float | None]:
   if "/" not in value:
      amount = parse_report_number(value)
      return amount, amount
   requested, filled = value.split("/", 1)
   return parse_report_number(requested), parse_report_number(filled)


def extract_section_rows(tables: list[list[list[str]]], section_name: str) -> tuple[list[str], list[list[str]]]:
   for table in tables:
      for index, row in enumerate(table):
         if any(cell == section_name for cell in row):
            if index + 1 >= len(table):
               break
            header = table[index + 1]
            data_rows: list[list[str]] = []
            for data_row in table[index + 2 :]:
               if any(cell in ("Orders", "Deals") for cell in data_row):
                  break
               if not any(cell.strip() for cell in data_row):
                  continue
               if len(data_row) != len(header):
                  continue
               data_rows.append(data_row)
            return header, data_rows
   raise PhaseABlocked(f"MT5 report section missing: {section_name}")


def parse_report_tables(report_path: Path) -> tuple[list[ReportOrderRow], list[ReportDealRow]]:
   parser = HtmlTableParser()
   parser.feed(hpo.read_text_with_encodings(report_path))

   orders_header, order_rows_raw = extract_section_rows(parser.tables, "Orders")
   deals_header, deal_rows_raw = extract_section_rows(parser.tables, "Deals")

   normalized_orders = [cell.strip() for cell in orders_header]
   normalized_deals = [cell.strip() for cell in deals_header]

   if normalized_orders != [
      "Open Time",
      "Order",
      "Symbol",
      "Type",
      "Volume",
      "Price",
      "S / L",
      "T / P",
      "Time",
      "State",
      "Comment",
   ]:
      raise PhaseABlocked(f"Unexpected Orders header in {report_path}: {normalized_orders}")
   if normalized_deals != [
      "Time",
      "Deal",
      "Symbol",
      "Type",
      "Direction",
      "Volume",
      "Price",
      "Order",
      "Commission",
      "Swap",
      "Profit",
      "Balance",
      "Comment",
   ]:
      raise PhaseABlocked(f"Unexpected Deals header in {report_path}: {normalized_deals}")

   orders: list[ReportOrderRow] = []
   for row_index, row in enumerate(order_rows_raw, start=1):
      requested_volume, filled_volume = parse_order_volume_cell(row[4])
      fill_time = parse_report_timestamp(row[8]) if row[8] else None
      orders.append(
         ReportOrderRow(
            row_index=row_index,
            open_time=parse_report_timestamp(row[0]),
            open_time_text=row[0],
            order_id=int(row[1]),
            symbol=row[2],
            order_type=row[3],
            requested_volume=requested_volume,
            filled_volume=filled_volume,
            price=parse_report_number(row[5]),
            sl=parse_report_number(row[6]),
            tp=parse_report_number(row[7]),
            fill_time=fill_time,
            fill_time_text=row[8] or None,
            state=row[9],
            comment=row[10],
         )
      )

   deals: list[ReportDealRow] = []
   for row_index, row in enumerate(deal_rows_raw, start=1):
      symbol = row[2]
      if row[3].lower() == "balance":
         symbol = ""
      deals.append(
         ReportDealRow(
            row_index=row_index,
            time=parse_report_timestamp(row[0]),
            time_text=row[0],
            deal_id=int(row[1]),
            symbol=symbol,
            deal_type=row[3],
            direction=row[4],
            volume=parse_report_number(row[5]),
            price=parse_report_number(row[6]),
            order_id=coerce_int(row[7]),
            commission=parse_report_number(row[8]),
            swap=parse_report_number(row[9]),
            profit=parse_report_number(row[10]),
            balance=parse_report_number(row[11]),
            comment=row[12],
         )
      )
   return orders, deals


def row_matches_candidate(
   candidate: dict[str, Any],
   *,
   symbol: str | None,
   price: Any = None,
   sl: Any = None,
   tp: Any = None,
   comment: str | None = None,
) -> bool:
   if symbol and candidate.get("symbol") != symbol:
      return False
   if price is not None and normalize_price_component(candidate.get("requested_entry_price")) != normalize_price_component(price):
      return False
   if sl is not None and normalize_price_component(candidate.get("sl")) != normalize_price_component(sl):
      return False
   if tp is not None and normalize_price_component(candidate.get("tp")) != normalize_price_component(tp):
      return False
   if comment is not None and normalize_candidate_text(candidate.get("comment")) != normalize_candidate_text(comment):
      return False
   return True


def attach_source_reference(candidate: dict[str, Any], prefix: str, row: DecisionRow) -> None:
   candidate[f"{prefix}_source_file"] = safe_relative(row.source_path)
   candidate[f"{prefix}_source_row"] = row.source_row


def build_candidates(decision_rows: list[DecisionRow], event_rows: list[EventRow]) -> list[dict[str, Any]]:
   candidates: list[dict[str, Any]] = []
   candidates_by_id: dict[str, dict[str, Any]] = {}
   pending_by_symbol: dict[str, list[dict[str, Any]]] = {}
   ticket_to_candidate_id: dict[int, str] = {}
   last_meta_by_symbol: dict[str, DecisionRow] = {}
   last_risk_by_symbol: dict[str, DecisionRow] = {}

   for row in decision_rows:
      if row.symbol and row.component == "MetaPolicy" and row.message == "EVAL":
         last_meta_by_symbol[row.symbol] = row
      if row.symbol and row.component == "Risk" and row.message == "SIZING":
         last_risk_by_symbol[row.symbol] = row

      if row.component == "Allocator" and row.message == "ORDER_PLAN":
         symbol = normalize_candidate_text(row.fields.get("exec_symbol") or row.symbol)
         strategy = normalize_candidate_text(row.fields.get("strategy"))
         setup_type = normalize_candidate_text(row.fields.get("setup_type"))
         comment = normalize_candidate_text(row.fields.get("comment"))
         candidate_id = build_candidate_id(
            row.ts_text,
            symbol,
            strategy,
            setup_type,
            row.fields.get("entry_price"),
            row.fields.get("sl"),
            row.fields.get("tp"),
            comment,
         )
         if candidate_id in candidates_by_id:
            raise PhaseABlocked(f"Duplicate candidate_id encountered in {row.source_path} line {row.source_row}")

         meta_row = last_meta_by_symbol.get(symbol)
         risk_row = last_risk_by_symbol.get(symbol)

         candidate = {
            "run_id": row.run_id,
            "baseline_role": row.baseline_role,
            "candidate_id": candidate_id,
            "decision_ts": row.ts_text,
            "symbol": symbol,
            "signal_symbol": normalize_candidate_text(row.fields.get("signal_symbol")),
            "strategy": strategy,
            "setup_type": setup_type,
            "requested_entry_price": normalize_price_component(row.fields.get("entry_price")),
            "sl": normalize_price_component(row.fields.get("sl")),
            "tp": normalize_price_component(row.fields.get("tp")),
            "volume": maybe_number_text(coerce_float(row.fields.get("volume")), places=4),
            "comment": comment,
            "plan_valid": bool_text(coerce_bool(row.fields.get("valid"))),
            "rejection_reason": normalize_candidate_text(row.fields.get("rejection_reason")),
            "intent_id": "",
            "entry_ticket": "",
            "ticket_source": "",
            "order_sent": "",
            "place_ok": "",
            "place_retcode": "",
            "logged_worst_case_risk_money": "",
            "effective_risk_pct": "",
            "risk_raw_volume": "",
            "risk_floored_volume": "",
            "risk_final_volume": "",
            "volume_min": "",
            "volume_step": "",
            "risk_raw_gap_to_min_lot_frac": "",
            "risk_floored_gap_to_min_lot_frac": "",
            "risk_volume_zero_subcause": "",
            "risk_volume_zero_reference_volume": "",
            "risk_volume_zero_gap_to_min_lot_frac": "",
            "volume_zero_subcause": normalize_candidate_text(row.fields.get("volume_zero_subcause")),
            "volume_zero_reference_volume": maybe_number_text(
               coerce_float(row.fields.get("volume_zero_reference_volume")),
               places=8,
            ),
            "volume_zero_gap_to_min_lot_frac": maybe_number_text(
               coerce_float(row.fields.get("volume_zero_gap_to_min_lot_frac")),
               places=8,
            ),
            "budget_scaled_raw_volume": maybe_number_text(
               coerce_float(row.fields.get("budget_scaled_raw_volume")),
               places=8,
            ),
            "budget_scaled_floored_volume": maybe_number_text(
               coerce_float(row.fields.get("budget_scaled_floored_volume")),
               places=8,
            ),
            "meta_choice": "",
            "meta_confidence": "",
            "meta_regime": "",
            "meta_gating_reason": "",
            "meta_news_window_state": "",
            "meta_spread_q": "",
            "meta_slippage_q": "",
            "meta_hold_time_min": "",
            "meta_emrt": "",
            "meta_policy_source_file": "",
            "meta_policy_source_row": "",
            "risk_sizing_source_file": "",
            "risk_sizing_source_row": "",
            "order_plan_source_file": safe_relative(row.source_path),
            "order_plan_source_row": row.source_row,
            "intent_accept_source_file": "",
            "intent_accept_source_row": "",
            "execute_order_success_source_file": "",
            "execute_order_success_source_row": "",
            "place_ok_source_file": "",
            "place_ok_source_row": "",
         }

         if meta_row is not None and meta_row.ts == row.ts:
            candidate["meta_choice"] = normalize_candidate_text(meta_row.fields.get("choice"))
            candidate["meta_confidence"] = maybe_number_text(coerce_float(meta_row.fields.get("confidence")), places=6)
            candidate["meta_regime"] = normalize_candidate_text(meta_row.fields.get("regime"))
            candidate["meta_gating_reason"] = normalize_candidate_text(meta_row.fields.get("gating_reason"))
            candidate["meta_news_window_state"] = normalize_candidate_text(meta_row.fields.get("news_window_state"))
            candidate["meta_spread_q"] = maybe_number_text(coerce_float(meta_row.fields.get("spread_q")), places=6)
            candidate["meta_slippage_q"] = maybe_number_text(coerce_float(meta_row.fields.get("slippage_q")), places=6)
            candidate["meta_hold_time_min"] = maybe_number_text(coerce_float(meta_row.fields.get("hold_time_min")), places=2)
            candidate["meta_emrt"] = maybe_number_text(coerce_float(meta_row.fields.get("emrt")), places=6)
            attach_source_reference(candidate, "meta_policy", meta_row)

         if risk_row is not None and risk_row.ts == row.ts:
            candidate["logged_worst_case_risk_money"] = maybe_number_text(
               coerce_float(risk_row.fields.get("risk_money")),
               places=2,
            )
            candidate["effective_risk_pct"] = maybe_number_text(
               coerce_float(risk_row.fields.get("effective_risk_pct")),
               places=2,
            )
            candidate["risk_raw_volume"] = maybe_number_text(
               coerce_float(risk_row.fields.get("raw_volume")),
               places=8,
            )
            candidate["risk_floored_volume"] = maybe_number_text(
               coerce_float(risk_row.fields.get("floored_volume")),
               places=8,
            )
            candidate["risk_final_volume"] = maybe_number_text(
               coerce_float(risk_row.fields.get("final_volume")),
               places=8,
            )
            candidate["volume_min"] = maybe_number_text(
               coerce_float(risk_row.fields.get("volume_min") or row.fields.get("volume_min")),
               places=8,
            )
            candidate["volume_step"] = maybe_number_text(
               coerce_float(risk_row.fields.get("volume_step") or row.fields.get("volume_step")),
               places=8,
            )
            candidate["risk_raw_gap_to_min_lot_frac"] = maybe_number_text(
               coerce_float(risk_row.fields.get("raw_gap_to_min_lot_frac")),
               places=8,
            )
            candidate["risk_floored_gap_to_min_lot_frac"] = maybe_number_text(
               coerce_float(risk_row.fields.get("floored_gap_to_min_lot_frac")),
               places=8,
            )
            candidate["risk_volume_zero_subcause"] = normalize_candidate_text(
               risk_row.fields.get("volume_zero_subcause")
            )
            candidate["risk_volume_zero_reference_volume"] = maybe_number_text(
               coerce_float(risk_row.fields.get("volume_zero_reference_volume")),
               places=8,
            )
            candidate["risk_volume_zero_gap_to_min_lot_frac"] = maybe_number_text(
               coerce_float(risk_row.fields.get("volume_zero_gap_to_min_lot_frac")),
               places=8,
            )
            attach_source_reference(candidate, "risk_sizing", risk_row)

         candidates.append(candidate)
         candidates_by_id[candidate_id] = candidate
         if coerce_bool(row.fields.get("valid")):
            pending_by_symbol.setdefault(symbol, []).append(candidate)
         continue

      if row.component == "OrderEngine" and row.message == "INTENT_ACCEPT":
         symbol = normalize_candidate_text(row.fields.get("symbol") or row.symbol)
         matches = [
            item
            for item in pending_by_symbol.get(symbol, [])
            if not item["intent_id"]
            and row_matches_candidate(
               item,
               symbol=symbol,
               price=row.fields.get("price"),
               sl=row.fields.get("sl"),
               tp=row.fields.get("tp"),
               comment=normalize_candidate_text(row.fields.get("reason")),
            )
         ]
         if len(matches) > 1:
            raise PhaseABlocked(f"Ambiguous INTENT_ACCEPT match in {row.source_path} line {row.source_row}")
         if len(matches) == 1:
            candidate = matches[0]
            candidate["intent_id"] = normalize_candidate_text(row.fields.get("intent_id"))
            attach_source_reference(candidate, "intent_accept", row)
         continue

      if row.component == "OrderEngine" and row.message == "EXECUTE_ORDER_SUCCESS":
         symbol = normalize_candidate_text(row.fields.get("symbol") or row.symbol)
         matches = [
            item
            for item in pending_by_symbol.get(symbol, [])
            if not item["entry_ticket"]
            and row_matches_candidate(item, symbol=symbol, price=row.fields.get("requested"))
         ]
         if len(matches) > 1:
            raise PhaseABlocked(
               f"Ambiguous EXECUTE_ORDER_SUCCESS match in {row.source_path} line {row.source_row}"
            )
         if len(matches) == 1:
            candidate = matches[0]
            ticket = coerce_int(row.fields.get("ticket"))
            if ticket is None:
               raise PhaseABlocked(f"Missing execution ticket in {row.source_path} line {row.source_row}")
            candidate["entry_ticket"] = str(ticket)
            candidate["ticket_source"] = "decision_execute_order_success"
            candidate["order_sent"] = bool_text(True)
            attach_source_reference(candidate, "execute_order_success", row)
            ticket_to_candidate_id[ticket] = candidate["candidate_id"]
            pending_by_symbol[symbol] = [item for item in pending_by_symbol.get(symbol, []) if item is not candidate]
         continue

      if row.component == "Scheduler" and row.message == "PLACE_OK":
         ticket = coerce_int(row.fields.get("ticket"))
         if ticket is None:
            continue
         candidate_id = ticket_to_candidate_id.get(ticket)
         if candidate_id is None:
            continue
         candidate = candidates_by_id[candidate_id]
         candidate["place_ok"] = bool_text(True)
         candidate["place_retcode"] = str(coerce_int(row.fields.get("retcode")) or "")
         attach_source_reference(candidate, "place_ok", row)
         continue

      if row.component == "Scheduler" and row.message == "PLACE_FAIL":
         symbol = normalize_candidate_text(row.fields.get("symbol") or row.symbol)
         if not symbol:
            continue
         queue = pending_by_symbol.get(symbol, [])
         if queue:
            candidate = queue.pop(0)
            candidate["order_sent"] = bool_text(False)
            candidate["place_ok"] = bool_text(False)
            candidate["place_retcode"] = str(coerce_int(row.fields.get("retcode")) or "")
         continue

   for event_row in event_rows:
      if event_row.event != "ORDER_INTENT_EXECUTED":
         continue
      intent_id = normalize_candidate_text(event_row.fields.get("intent_id"))
      ticket = coerce_int(event_row.fields.get("ticket"))
      if not intent_id or ticket is None:
         continue
      for candidate in candidates:
         if candidate["intent_id"] == intent_id and not candidate["entry_ticket"]:
            candidate["entry_ticket"] = str(ticket)
            candidate["ticket_source"] = "event_order_intent_executed"
            ticket_to_candidate_id[ticket] = candidate["candidate_id"]
            break

   return candidates


def build_gate_intervals(decision_rows: list[DecisionRow]) -> list[dict[str, Any]]:
   intervals: list[dict[str, Any]] = []
   active: dict[tuple[str, str], dict[str, Any]] = {}

   def close_interval(key: tuple[str, str]) -> None:
      interval = active.pop(key, None)
      if interval is None:
         return
      start_dt = datetime.fromisoformat(interval["start_ts"])
      end_dt = datetime.fromisoformat(interval["end_ts"])
      interval["duration_seconds"] = int((end_dt - start_dt).total_seconds())
      intervals.append(interval)

   for row in decision_rows:
      symbol = row.symbol
      if row.component == "Allocator" and row.message == "ORDER_PLAN" and symbol:
         for family in ("Liquidity.GATED", "Scheduler.GATED", "MetaPolicy.EVAL.Skip"):
            close_interval((family, symbol))

      family = None
      payload: dict[str, Any] = {}
      normalized_key = ""

      if row.component == "Liquidity" and row.message == "GATED" and symbol:
         family = "Liquidity.GATED"
         reason = normalize_candidate_text(row.fields.get("reason"))
         payload = {"reason": reason}
         normalized_key = "|".join((symbol, reason))
      elif row.component == "Scheduler" and row.message == "GATED" and symbol:
         family = "Scheduler.GATED"
         payload = {
            "news": bool_text(coerce_bool(row.fields.get("news"))),
            "spread_ok": bool_text(coerce_bool(row.fields.get("spread_ok"))),
            "in_session": bool_text(coerce_bool(row.fields.get("in_session"))),
            "in_or": bool_text(coerce_bool(row.fields.get("in_or"))),
            "anomaly_block": bool_text(coerce_bool(row.fields.get("anomaly_block"))),
            "anomaly_action": normalize_candidate_text(row.fields.get("anomaly_action")),
         }
         normalized_key = "|".join(
            (
               symbol,
               payload["news"],
               payload["spread_ok"],
               payload["in_session"],
               payload["in_or"],
               payload["anomaly_block"],
               payload["anomaly_action"],
            )
         )
      elif (
         row.component == "MetaPolicy"
         and row.message == "EVAL"
         and symbol
         and normalize_candidate_text(row.fields.get("choice")) == "Skip"
      ):
         family = "MetaPolicy.EVAL.Skip"
         payload = {
            "choice": "Skip",
            "gating_reason": normalize_candidate_text(row.fields.get("gating_reason")),
            "regime": normalize_candidate_text(row.fields.get("regime")),
            "news_window_state": normalize_candidate_text(row.fields.get("news_window_state")),
         }
         normalized_key = "|".join(
            (
               symbol,
               payload["choice"],
               payload["gating_reason"],
               payload["regime"],
               payload["news_window_state"],
            )
         )

      if family is None or symbol is None:
         continue

      key = (family, symbol)
      current = active.get(key)
      if current is not None and current["normalized_key"] != normalized_key:
         close_interval(key)
         current = None
      if current is None:
         active[key] = {
            "run_id": row.run_id,
            "baseline_role": row.baseline_role,
            "gate_family": family,
            "symbol": symbol,
            "normalized_key": normalized_key,
            "start_ts": row.ts_text,
            "end_ts": row.ts_text,
            "row_count": 1,
            "source_first_file": safe_relative(row.source_path),
            "source_first_row": row.source_row,
            "source_last_file": safe_relative(row.source_path),
            "source_last_row": row.source_row,
            "reason": payload.get("reason", ""),
            "news": payload.get("news", ""),
            "spread_ok": payload.get("spread_ok", ""),
            "in_session": payload.get("in_session", ""),
            "in_or": payload.get("in_or", ""),
            "anomaly_block": payload.get("anomaly_block", ""),
            "anomaly_action": payload.get("anomaly_action", ""),
            "choice": payload.get("choice", ""),
            "gating_reason": payload.get("gating_reason", ""),
            "regime": payload.get("regime", ""),
            "news_window_state": payload.get("news_window_state", ""),
            "duration_seconds": 0,
         }
      else:
         current["end_ts"] = row.ts_text
         current["row_count"] += 1
         current["source_last_file"] = safe_relative(row.source_path)
         current["source_last_row"] = row.source_row

   for key in list(active):
      close_interval(key)

   intervals.sort(key=lambda item: (item["run_id"], item["start_ts"], item["gate_family"], item["symbol"]))
   return intervals


def parse_gate_intervals(run_input: PhaseARunInput) -> list[dict[str, Any]]:
   intervals: list[dict[str, Any]] = []
   active: dict[tuple[str, str], dict[str, Any]] = {}
   pending_scheduler_symbol: str | None = None

   def close_interval(key: tuple[str, str]) -> None:
      interval = active.pop(key, None)
      if interval is None:
         return
      start_dt = datetime.fromisoformat(interval["start_ts"])
      end_dt = datetime.fromisoformat(interval["end_ts"])
      interval["duration_seconds"] = int((end_dt - start_dt).total_seconds())
      intervals.append(interval)

   for source_path in sorted(run_input.decision_log_paths):
      pending_scheduler_symbol = None
      relative_source = safe_relative(source_path)
      for source_row, parts in iter_log_lines(
         source_path,
         expected_header="date,time,event,component,level,message,fields_json",
      ):
         date_value, time_value, event_value, component_value, level_value, message_value, fields_value = parts
         del level_value
         if event_value != "DECISION":
            continue

         row_kind = (component_value, message_value)
         if row_kind == ("Scheduler", "ANOMALY_EVAL"):
            pending_scheduler_symbol = normalize_candidate_text(extract_json_string(fields_value, "symbol")) or None
            continue
         if row_kind not in GATE_ROWS_RELEVANT:
            continue

         symbol = normalize_candidate_text(
            extract_json_string(fields_value, "symbol")
            or extract_json_string(fields_value, "exec_symbol")
            or extract_json_string(fields_value, "signal_symbol")
         ) or None
         if row_kind == ("Scheduler", "GATED"):
            symbol = symbol or pending_scheduler_symbol
            pending_scheduler_symbol = None
            if symbol is None:
               raise PhaseABlocked(
                  f"Scheduler.GATED row missing ANOMALY_EVAL symbol context in {source_path} line {source_row}"
               )
         if symbol is None:
            raise PhaseABlocked(f"Gate row missing symbol in {source_path} line {source_row}: {component_value}.{message_value}")

         ts_text = f"{date_value}T{time_value}"

         if row_kind == ("Allocator", "ORDER_PLAN"):
            for family in ("Liquidity.GATED", "Scheduler.GATED", "MetaPolicy.EVAL.Skip"):
               close_interval((family, symbol))
            continue

         family = None
         payload: dict[str, Any] = {}
         normalized_key = ""

         if row_kind == ("Liquidity", "GATED"):
            family = "Liquidity.GATED"
            reason = normalize_candidate_text(extract_json_string(fields_value, "reason"))
            payload = {"reason": reason}
            normalized_key = "|".join((symbol, reason))
         elif row_kind == ("Scheduler", "GATED"):
            family = "Scheduler.GATED"
            payload = {
               "news": bool_text(extract_json_bool(fields_value, "news")),
               "spread_ok": bool_text(extract_json_bool(fields_value, "spread_ok")),
               "in_session": bool_text(extract_json_bool(fields_value, "in_session")),
               "in_or": bool_text(extract_json_bool(fields_value, "in_or")),
               "anomaly_block": bool_text(extract_json_bool(fields_value, "anomaly_block")),
               "anomaly_action": normalize_candidate_text(extract_json_string(fields_value, "anomaly_action")),
            }
            normalized_key = "|".join(
               (
                  symbol,
                  payload["news"],
                  payload["spread_ok"],
                  payload["in_session"],
                  payload["in_or"],
                  payload["anomaly_block"],
                  payload["anomaly_action"],
               )
            )
         elif normalize_candidate_text(extract_json_string(fields_value, "choice")) == "Skip":
            family = "MetaPolicy.EVAL.Skip"
            payload = {
               "choice": "Skip",
               "gating_reason": normalize_candidate_text(extract_json_string(fields_value, "gating_reason")),
               "regime": normalize_candidate_text(extract_json_string(fields_value, "regime")),
               "news_window_state": normalize_candidate_text(extract_json_string(fields_value, "news_window_state")),
            }
            normalized_key = "|".join(
               (
                  symbol,
                  payload["choice"],
                  payload["gating_reason"],
                  payload["regime"],
                  payload["news_window_state"],
               )
            )

         if family is None:
            continue

         key = (family, symbol)
         current = active.get(key)
         if current is not None and current["normalized_key"] != normalized_key:
            close_interval(key)
            current = None
         if current is None:
            active[key] = {
               "run_id": run_input.id,
               "baseline_role": run_input.baseline_role,
               "gate_family": family,
               "symbol": symbol,
               "normalized_key": normalized_key,
               "start_ts": ts_text,
               "end_ts": ts_text,
               "row_count": 1,
               "source_first_file": relative_source,
               "source_first_row": source_row,
               "source_last_file": relative_source,
               "source_last_row": source_row,
               "reason": payload.get("reason", ""),
               "news": payload.get("news", ""),
               "spread_ok": payload.get("spread_ok", ""),
               "in_session": payload.get("in_session", ""),
               "in_or": payload.get("in_or", ""),
               "anomaly_block": payload.get("anomaly_block", ""),
               "anomaly_action": payload.get("anomaly_action", ""),
               "choice": payload.get("choice", ""),
               "gating_reason": payload.get("gating_reason", ""),
               "regime": payload.get("regime", ""),
               "news_window_state": payload.get("news_window_state", ""),
               "duration_seconds": 0,
            }
         else:
            current["end_ts"] = ts_text
            current["row_count"] += 1
            current["source_last_file"] = relative_source
            current["source_last_row"] = source_row

   for key in list(active):
      close_interval(key)

   intervals.sort(key=lambda item: (item["run_id"], item["start_ts"], item["gate_family"], item["symbol"]))
   return intervals


def build_timestop_index(decision_rows: list[DecisionRow]) -> dict[int, list[DecisionRow]]:
   index: dict[int, list[DecisionRow]] = {}
   for row in decision_rows:
      if row.component != "Scheduler" or row.message != "MR_TIMESTOP":
         continue
      ticket = coerce_int(row.fields.get("ticket"))
      if ticket is None or not coerce_bool(row.fields.get("close_requested")):
         continue
      index.setdefault(ticket, []).append(row)
   for items in index.values():
      items.sort(key=lambda item: item.ts)
   return index


def build_trade_row(
   *,
   run_input: PhaseARunInput,
   candidate: dict[str, Any],
   entry_order: ReportOrderRow | None,
   exit_order: ReportOrderRow | None,
   entry_deal: ReportDealRow,
   exit_deal: ReportDealRow,
   timestops_by_ticket: dict[int, list[DecisionRow]],
) -> dict[str, Any]:
   risk_money = coerce_float(candidate.get("logged_worst_case_risk_money"))
   if risk_money is None or risk_money <= 0.0:
      raise PhaseABlocked(
         f"Missing logged worst-case risk for executed candidate {candidate['candidate_id']} in {run_input.id}"
      )

   entry_price = entry_deal.price
   exit_price = exit_deal.price
   if entry_price is None or exit_price is None or entry_deal.volume is None or exit_deal.volume is None:
      raise PhaseABlocked(f"Incomplete deal pricing for trade ticket {candidate['entry_ticket']} in {run_input.id}")

   requested_sl = coerce_float(candidate.get("sl"))
   requested_tp = coerce_float(candidate.get("tp"))
   if requested_sl is None or requested_tp is None:
      raise PhaseABlocked(f"Candidate geometry missing for executed trade {candidate['candidate_id']} in {run_input.id}")

   sl_distance = abs(entry_price - requested_sl)
   tp_distance = abs(requested_tp - entry_price)
   if sl_distance <= 0.0 or tp_distance <= 0.0:
      raise PhaseABlocked(f"Invalid SL/TP geometry for executed trade {candidate['candidate_id']} in {run_input.id}")

   realized_pnl = float((exit_deal.profit or 0.0) + (exit_deal.commission or 0.0) + (exit_deal.swap or 0.0))
   theoretical_r = tp_distance / sl_distance
   realized_r = realized_pnl / risk_money
   friction_r = max(theoretical_r - realized_r, 0.0)

   exit_reason_class = "unknown"
   exit_reason_exact = ""
   close_source = "report_deals"

   exit_comment = normalize_candidate_text(exit_deal.comment)
   if not exit_comment and exit_order is not None:
      exit_comment = normalize_candidate_text(exit_order.comment)
   if exit_comment.lower().startswith("sl "):
      exit_reason_class = "stop_loss"
      exit_reason_exact = exit_comment
      close_source = "report_deals+report_orders"
   else:
      entry_ticket = int(candidate["entry_ticket"])
      timestop_rows = [
         row
         for row in timestops_by_ticket.get(entry_ticket, [])
         if entry_deal.time <= row.ts <= exit_deal.time
      ]
      if timestop_rows:
         exit_reason_class = "timestop"
         exit_reason_exact = "MR_TIMESTOP"
         close_source = "report_deals+decision_logs"

   return {
      "run_id": run_input.id,
      "baseline_role": run_input.baseline_role,
      "candidate_id": candidate["candidate_id"],
      "intent_id": candidate["intent_id"],
      "entry_ticket": candidate["entry_ticket"],
      "symbol": candidate["symbol"],
      "strategy": candidate["strategy"],
      "entry_time": format_ts(entry_deal.time),
      "exit_time": format_ts(exit_deal.time),
      "entry_price": maybe_number_text(entry_price, places=5),
      "exit_price": maybe_number_text(exit_price, places=5),
      "volume": maybe_number_text(entry_deal.volume, places=4),
      "realized_pnl": maybe_number_text(realized_pnl, places=2),
      "hold_minutes": maybe_number_text((exit_deal.time - entry_deal.time).total_seconds() / 60.0, places=2),
      "theoretical_r": maybe_number_text(theoretical_r, places=6),
      "realized_r": maybe_number_text(realized_r, places=6),
      "friction_r": maybe_number_text(friction_r, places=6),
      "exit_reason_class": exit_reason_class,
      "exit_reason_exact": exit_reason_exact,
      "close_source": close_source,
      "requested_entry_price": candidate["requested_entry_price"],
      "sl": candidate["sl"],
      "tp": candidate["tp"],
      "confidence": candidate["meta_confidence"],
      "regime": candidate["meta_regime"],
      "spread_q": candidate["meta_spread_q"],
      "slippage_q": candidate["meta_slippage_q"],
      "logged_worst_case_risk_money": candidate["logged_worst_case_risk_money"],
      "entry_order_id": str(entry_order.order_id) if entry_order is not None else "",
      "entry_deal_id": str(entry_deal.deal_id),
      "exit_order_id": str(exit_order.order_id) if exit_order is not None else "",
      "exit_deal_id": str(exit_deal.deal_id),
      "exit_comment": exit_comment,
   }


def build_trades(
   *,
   run_input: PhaseARunInput,
   candidates: list[dict[str, Any]],
   decision_rows: list[DecisionRow],
   orders: list[ReportOrderRow],
   deals: list[ReportDealRow],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
   candidates_by_ticket = {
      int(item["entry_ticket"]): item
      for item in candidates
      if item.get("entry_ticket")
   }
   orders_by_id = {item.order_id: item for item in orders}
   entry_orders = [item for item in orders if item.order_type.lower() in ("buy", "sell")]
   timestops_by_ticket = build_timestop_index(decision_rows)

   trades: list[dict[str, Any]] = []
   open_by_symbol: dict[str, tuple[ReportOrderRow | None, ReportDealRow, dict[str, Any]]] = {}
   entry_deals_seen = 0

   for deal in deals:
      if deal.direction not in ("in", "out"):
         continue
      if deal.symbol != "XAUUSD":
         raise PhaseABlocked(f"Unexpected symbol in Phase A trade truth set: {deal.symbol!r} ({run_input.id})")

      if deal.direction == "in":
         entry_deals_seen += 1
         if deal.order_id is None:
            raise PhaseABlocked(f"Entry deal missing order id in {run_input.report_path}")
         candidate = candidates_by_ticket.get(deal.order_id)
         if candidate is None:
            raise PhaseABlocked(
               f"Entry deal order id {deal.order_id} missing decision-log join coverage in {run_input.id}"
            )
         if deal.symbol in open_by_symbol:
            raise PhaseABlocked(
               f"MaxOpenPerSymbol invariant violated for {deal.symbol} in {run_input.id}: overlapping entry deals"
            )
         open_by_symbol[deal.symbol] = (orders_by_id.get(deal.order_id), deal, candidate)
         continue

      if deal.symbol not in open_by_symbol:
         raise PhaseABlocked(f"Out deal without matching open entry for {deal.symbol} in {run_input.id}")

      entry_order, entry_deal, candidate = open_by_symbol.pop(deal.symbol)
      if entry_deal.volume is None or deal.volume is None:
         raise PhaseABlocked(f"Missing deal volume while pairing {candidate['candidate_id']} in {run_input.id}")
      if not math.isclose(entry_deal.volume, deal.volume, rel_tol=0.0, abs_tol=1e-9):
         raise PhaseABlocked(
            f"Partial-close invariant violated for trade {candidate['candidate_id']} in {run_input.id}: "
            f"entry volume={entry_deal.volume} exit volume={deal.volume}"
         )

      exit_order = orders_by_id.get(deal.order_id or -1)
      trades.append(
         build_trade_row(
            run_input=run_input,
            candidate=candidate,
            entry_order=entry_order,
            exit_order=exit_order,
            entry_deal=entry_deal,
            exit_deal=deal,
            timestops_by_ticket=timestops_by_ticket,
         )
      )

   if open_by_symbol:
      symbols = ", ".join(sorted(open_by_symbol))
      raise PhaseABlocked(f"Open report trades left unmatched in {run_input.id}: {symbols}")

   invariant_summary = {
      "entry_deal_count": entry_deals_seen,
      "trade_count": len(trades),
      "candidate_join_coverage_count": len(candidates_by_ticket),
      "entry_order_count": len(entry_orders),
      "max_open_per_symbol_ok": True,
      "partial_close_ok": True,
   }
   return trades, invariant_summary


def build_research_daily(
   *,
   run_input: PhaseARunInput,
   daily_rows: list[dict[str, str]],
   candidates: list[dict[str, Any]],
   trades: list[dict[str, Any]],
   gate_intervals: list[dict[str, Any]],
) -> list[dict[str, Any]]:
   trade_stats_by_date: dict[str, dict[str, float]] = {}
   for trade in trades:
      server_date = trade["exit_time"][:10]
      bucket = trade_stats_by_date.setdefault(
         server_date,
         {
            "trade_count_closed": 0.0,
            "trade_realized_pnl": 0.0,
            "trade_realized_r_sum": 0.0,
            "trade_friction_r_sum": 0.0,
            "trade_exit_count_timestop": 0.0,
            "trade_exit_count_stop_loss": 0.0,
         },
      )
      bucket["trade_count_closed"] += 1.0
      bucket["trade_realized_pnl"] += float(trade["realized_pnl"])
      bucket["trade_realized_r_sum"] += float(trade["realized_r"])
      bucket["trade_friction_r_sum"] += float(trade["friction_r"])
      if trade["exit_reason_class"] == "timestop":
         bucket["trade_exit_count_timestop"] += 1.0
      if trade["exit_reason_class"] == "stop_loss":
         bucket["trade_exit_count_stop_loss"] += 1.0

   candidate_stats_by_date: dict[str, dict[str, float]] = {}
   for candidate in candidates:
      server_date = candidate["decision_ts"][:10]
      bucket = candidate_stats_by_date.setdefault(
         server_date,
         {"candidate_count": 0.0, "candidate_valid_count": 0.0, "candidate_executed_count": 0.0},
      )
      bucket["candidate_count"] += 1.0
      if candidate["plan_valid"] == "true":
         bucket["candidate_valid_count"] += 1.0
      if candidate["entry_ticket"]:
         bucket["candidate_executed_count"] += 1.0

   gate_stats_by_date: dict[str, dict[str, float]] = {}
   for interval in gate_intervals:
      server_date = interval["start_ts"][:10]
      bucket = gate_stats_by_date.setdefault(
         server_date,
         {
            "gate_interval_count": 0.0,
            "gate_interval_seconds": 0.0,
            "liquidity_gate_interval_count": 0.0,
            "scheduler_gate_interval_count": 0.0,
            "metapolicy_skip_interval_count": 0.0,
         },
      )
      bucket["gate_interval_count"] += 1.0
      bucket["gate_interval_seconds"] += float(interval["duration_seconds"])
      if interval["gate_family"] == "Liquidity.GATED":
         bucket["liquidity_gate_interval_count"] += 1.0
      elif interval["gate_family"] == "Scheduler.GATED":
         bucket["scheduler_gate_interval_count"] += 1.0
      elif interval["gate_family"] == "MetaPolicy.EVAL.Skip":
         bucket["metapolicy_skip_interval_count"] += 1.0

   research_daily: list[dict[str, Any]] = []
   for row in daily_rows:
      server_date = row["server_date"]
      merged: dict[str, Any] = {"run_id": run_input.id, "baseline_role": run_input.baseline_role}
      for field_name in DAILY_SOURCE_FIELDS:
         merged[field_name] = row.get(field_name, "")
      merged.update(
         {
            "trade_count_closed": "0",
            "trade_realized_pnl": "0.00",
            "trade_realized_r_sum": "0.000000",
            "trade_friction_r_sum": "0.000000",
            "trade_exit_count_timestop": "0",
            "trade_exit_count_stop_loss": "0",
            "candidate_count": "0",
            "candidate_valid_count": "0",
            "candidate_executed_count": "0",
            "gate_interval_count": "0",
            "gate_interval_seconds": "0",
            "liquidity_gate_interval_count": "0",
            "scheduler_gate_interval_count": "0",
            "metapolicy_skip_interval_count": "0",
         }
      )

      trade_bucket = trade_stats_by_date.get(server_date, {})
      candidate_bucket = candidate_stats_by_date.get(server_date, {})
      gate_bucket = gate_stats_by_date.get(server_date, {})

      merged["trade_count_closed"] = str(int(trade_bucket.get("trade_count_closed", 0.0)))
      merged["trade_realized_pnl"] = maybe_number_text(trade_bucket.get("trade_realized_pnl"), places=2)
      merged["trade_realized_r_sum"] = maybe_number_text(trade_bucket.get("trade_realized_r_sum"), places=6)
      merged["trade_friction_r_sum"] = maybe_number_text(trade_bucket.get("trade_friction_r_sum"), places=6)
      merged["trade_exit_count_timestop"] = str(int(trade_bucket.get("trade_exit_count_timestop", 0.0)))
      merged["trade_exit_count_stop_loss"] = str(int(trade_bucket.get("trade_exit_count_stop_loss", 0.0)))
      merged["candidate_count"] = str(int(candidate_bucket.get("candidate_count", 0.0)))
      merged["candidate_valid_count"] = str(int(candidate_bucket.get("candidate_valid_count", 0.0)))
      merged["candidate_executed_count"] = str(int(candidate_bucket.get("candidate_executed_count", 0.0)))
      merged["gate_interval_count"] = str(int(gate_bucket.get("gate_interval_count", 0.0)))
      merged["gate_interval_seconds"] = str(int(gate_bucket.get("gate_interval_seconds", 0.0)))
      merged["liquidity_gate_interval_count"] = str(int(gate_bucket.get("liquidity_gate_interval_count", 0.0)))
      merged["scheduler_gate_interval_count"] = str(int(gate_bucket.get("scheduler_gate_interval_count", 0.0)))
      merged["metapolicy_skip_interval_count"] = str(
         int(gate_bucket.get("metapolicy_skip_interval_count", 0.0))
      )
      research_daily.append(merged)

   return research_daily


def summarize_gate_intervals(rows: list[dict[str, Any]]) -> dict[str, Any]:
   family_counts: dict[str, int] = {}
   family_durations: dict[str, int] = {}
   top_keys: list[dict[str, Any]] = []
   counts_by_key: dict[tuple[str, str], dict[str, Any]] = {}

   for row in rows:
      family = row["gate_family"]
      family_counts[family] = family_counts.get(family, 0) + 1
      family_durations[family] = family_durations.get(family, 0) + int(row["duration_seconds"])
      key = (family, row["normalized_key"])
      item = counts_by_key.setdefault(
         key,
         {"gate_family": family, "normalized_key": row["normalized_key"], "interval_count": 0, "row_count": 0},
      )
      item["interval_count"] += 1
      item["row_count"] += int(row["row_count"])

   for item in sorted(
      counts_by_key.values(),
      key=lambda candidate: (candidate["interval_count"], candidate["row_count"]),
      reverse=True,
   )[:5]:
      top_keys.append(item)

   return {
      "interval_count": len(rows),
      "family_counts": family_counts,
      "family_duration_seconds": family_durations,
      "top_normalized_keys": top_keys,
   }


def build_confidence_split(trades: list[dict[str, Any]]) -> dict[str, Any]:
   scored = [item for item in trades if item.get("confidence")]
   if len(scored) < 4:
      return {"available": False}

   confidence_values = [float(item["confidence"]) for item in scored]
   median_value = statistics.median(confidence_values)
   low = [item for item in scored if float(item["confidence"]) <= median_value]
   high = [item for item in scored if float(item["confidence"]) > median_value]
   if not low or not high:
      return {"available": False}

   return {
      "available": True,
      "median_confidence": round(median_value, 6),
      "low_count": len(low),
      "high_count": len(high),
      "low_pnl_per_trade": round(statistics.fmean(float(item["realized_pnl"]) for item in low), 6),
      "high_pnl_per_trade": round(statistics.fmean(float(item["realized_pnl"]) for item in high), 6),
      "low_realized_r_mean": round(statistics.fmean(float(item["realized_r"]) for item in low), 6),
      "high_realized_r_mean": round(statistics.fmean(float(item["realized_r"]) for item in high), 6),
   }


def build_spread_split(trades: list[dict[str, Any]]) -> dict[str, Any]:
   scored = [item for item in trades if item.get("spread_q")]
   if len(scored) < 4:
      return {"available": False}

   spread_values = [float(item["spread_q"]) for item in scored]
   median_value = statistics.median(spread_values)
   low = [item for item in scored if float(item["spread_q"]) <= median_value]
   high = [item for item in scored if float(item["spread_q"]) > median_value]
   if not low or not high:
      return {"available": False}

   return {
      "available": True,
      "median_spread_q": round(median_value, 6),
      "low_count": len(low),
      "high_count": len(high),
      "low_pnl_per_trade": round(statistics.fmean(float(item["realized_pnl"]) for item in low), 6),
      "high_pnl_per_trade": round(statistics.fmean(float(item["realized_pnl"]) for item in high), 6),
      "low_realized_r_mean": round(statistics.fmean(float(item["realized_r"]) for item in low), 6),
      "high_realized_r_mean": round(statistics.fmean(float(item["realized_r"]) for item in high), 6),
   }


def summarize_trades(trades: list[dict[str, Any]]) -> dict[str, Any]:
   exit_reason_counts: dict[str, int] = {}
   exact_reason_counts: dict[str, int] = {}
   risk_weighted_potential_gap = 0.0
   timestop_gap = 0.0

   for trade in trades:
      exit_reason_counts[trade["exit_reason_class"]] = exit_reason_counts.get(trade["exit_reason_class"], 0) + 1
      if trade["exit_reason_exact"]:
         exact_reason_counts[trade["exit_reason_exact"]] = exact_reason_counts.get(trade["exit_reason_exact"], 0) + 1
      theoretical_r = float(trade["theoretical_r"])
      risk_money = float(trade["logged_worst_case_risk_money"])
      realized_pnl = float(trade["realized_pnl"])
      gap = max((theoretical_r * risk_money) - realized_pnl, 0.0)
      risk_weighted_potential_gap += gap
      if trade["exit_reason_exact"] == "MR_TIMESTOP":
         timestop_gap += gap

   return {
      "trade_count": len(trades),
      "realized_pnl_total": round(sum(float(item["realized_pnl"]) for item in trades), 2),
      "realized_r_mean": round(safe_mean(float(item["realized_r"]) for item in trades) or 0.0, 6),
      "realized_r_median": round(safe_median(float(item["realized_r"]) for item in trades) or 0.0, 6),
      "theoretical_r_mean": round(safe_mean(float(item["theoretical_r"]) for item in trades) or 0.0, 6),
      "friction_r_mean": round(safe_mean(float(item["friction_r"]) for item in trades) or 0.0, 6),
      "friction_r_median": round(safe_median(float(item["friction_r"]) for item in trades) or 0.0, 6),
      "exit_reason_class_counts": exit_reason_counts,
      "exit_reason_exact_counts": exact_reason_counts,
      "potential_gap_usd_total": round(risk_weighted_potential_gap, 2),
      "timestop_gap_usd_total": round(timestop_gap, 2),
      "confidence_split": build_confidence_split(trades),
      "spread_split": build_spread_split(trades),
   }


def build_change_candidates(run_summaries: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
   holdout = run_summaries["holdout"]
   corroboration = run_summaries["contiguous_public_rule3"]
   changes: list[dict[str, Any]] = []

   holdout_trade_stats = holdout["trade_summary"]
   corroboration_trade_stats = corroboration["trade_summary"]

   holdout_timestop_share = (
      holdout_trade_stats["exit_reason_exact_counts"].get("MR_TIMESTOP", 0) / holdout_trade_stats["trade_count"]
      if holdout_trade_stats["trade_count"]
      else 0.0
   )
   corroboration_timestop_share = (
      corroboration_trade_stats["exit_reason_exact_counts"].get("MR_TIMESTOP", 0)
      / corroboration_trade_stats["trade_count"]
      if corroboration_trade_stats["trade_count"]
      else 0.0
   )
   if (
      holdout_timestop_share >= 0.50
      and corroboration_timestop_share >= 0.50
      and holdout_trade_stats["friction_r_median"] > 0.20
      and corroboration_trade_stats["friction_r_median"] > 0.20
   ):
      expected_delta_usd = round(holdout_trade_stats["timestop_gap_usd_total"] * 0.15, 2)
      changes.append(
         {
            "rank_hint": 1,
            "title": "Re-test the MR time-stop and close stack",
            "phase_source": PHASE_SOURCE,
            "problem_observed": (
               "The executed book is dominated by MR time-stop exits, and measured friction remains positive even "
               "before any stress overlays."
            ),
            "evidence": [
               (
                  "Holdout: "
                  f"{holdout_trade_stats['exit_reason_exact_counts'].get('MR_TIMESTOP', 0)}/"
                  f"{holdout_trade_stats['trade_count']} trades end via MR_TIMESTOP, "
                  f"median friction={holdout_trade_stats['friction_r_median']:.3f}R, "
                  f"timestop gap upper bound=${holdout_trade_stats['timestop_gap_usd_total']:.2f}."
               ),
               (
                  "Corroboration: "
                  f"{corroboration_trade_stats['exit_reason_exact_counts'].get('MR_TIMESTOP', 0)}/"
                  f"{corroboration_trade_stats['trade_count']} trades end via MR_TIMESTOP, "
                  f"median friction={corroboration_trade_stats['friction_r_median']:.3f}R."
               ),
            ],
            "module_or_parameter": "scheduler.mqh MR time-stop path and config.mqh MR_TimeStopMin/MR_TimeStopMax",
            "expected_delta_usd": expected_delta_usd,
            "expected_delta_pct": round(expected_delta_usd * PCT_CONVERSION, 4),
            "confidence": "high",
            "reliability_risk": "medium; any relaxation must stay non-negative under moderate stress and preserve breach headroom.",
            "validation_rerun_needed": (
               "Untouched holdout plus the later Phase 5 report-window matrix, mild stress, and moderate stress."
            ),
         }
      )

   holdout_conf = holdout_trade_stats["confidence_split"]
   corroboration_conf = corroboration_trade_stats["confidence_split"]
   if (
      holdout_conf.get("available")
      and corroboration_conf.get("available")
      and holdout_conf["high_pnl_per_trade"] > holdout_conf["low_pnl_per_trade"]
      and corroboration_conf["high_pnl_per_trade"] > corroboration_conf["low_pnl_per_trade"]
   ):
      delta_per_trade = holdout_conf["high_pnl_per_trade"] - holdout_conf["low_pnl_per_trade"]
      expected_delta_usd = round(max(delta_per_trade, 0.0) * holdout_conf["low_count"] * 0.25, 2)
      changes.append(
         {
            "rank_hint": 2,
            "title": "Tighten MR acceptance on the weakest confidence slice",
            "phase_source": PHASE_SOURCE,
            "problem_observed": (
               "The lower-confidence half of executed MR trades underperforms the higher-confidence half in both "
               "the deciding holdout and the contiguous corroboration run."
            ),
            "evidence": [
               (
                  "Holdout: "
                  f"confidence median={holdout_conf['median_confidence']:.3f}, "
                  f"low-half pnl/trade=${holdout_conf['low_pnl_per_trade']:.2f}, "
                  f"high-half pnl/trade=${holdout_conf['high_pnl_per_trade']:.2f}."
               ),
               (
                  "Corroboration: "
                  f"confidence median={corroboration_conf['median_confidence']:.3f}, "
                  f"low-half pnl/trade=${corroboration_conf['low_pnl_per_trade']:.2f}, "
                  f"high-half pnl/trade=${corroboration_conf['high_pnl_per_trade']:.2f}."
               ),
            ],
            "module_or_parameter": "config.mqh MR_ConfCut and the MR acceptance path in signals_mr.mqh / meta_policy.mqh",
            "expected_delta_usd": expected_delta_usd,
            "expected_delta_pct": round(expected_delta_usd * PCT_CONVERSION, 4),
            "confidence": "medium",
            "reliability_risk": "low-to-medium; this can raise selectivity but may also reduce trade-day coverage if cut too aggressively.",
            "validation_rerun_needed": (
               "Untouched holdout, trade-day coverage review, then later report-window plus stress confirmation."
            ),
         }
      )

   holdout_spread = holdout_trade_stats["spread_split"]
   corroboration_spread = corroboration_trade_stats["spread_split"]
   if (
      holdout_spread.get("available")
      and corroboration_spread.get("available")
      and holdout_spread["low_pnl_per_trade"] > holdout_spread["high_pnl_per_trade"]
      and corroboration_spread["low_pnl_per_trade"] > corroboration_spread["high_pnl_per_trade"]
   ):
      delta_per_trade = holdout_spread["low_pnl_per_trade"] - holdout_spread["high_pnl_per_trade"]
      expected_delta_usd = round(max(delta_per_trade, 0.0) * holdout_spread["high_count"] * 0.20, 2)
      changes.append(
         {
            "rank_hint": 3,
            "title": "Re-test spread/liquidity tolerance on high-spread MR entries",
            "phase_source": PHASE_SOURCE,
            "problem_observed": (
               "Higher-spread executed MR entries lag lower-spread entries in both Phase A datasets, which points to "
               "an entry-quality leak rather than a post-entry stop-loss issue."
            ),
            "evidence": [
               (
                  "Holdout: "
                  f"spread_q median={holdout_spread['median_spread_q']:.3f}, "
                  f"low-half pnl/trade=${holdout_spread['low_pnl_per_trade']:.2f}, "
                  f"high-half pnl/trade=${holdout_spread['high_pnl_per_trade']:.2f}."
               ),
               (
                  "Corroboration: "
                  f"spread_q median={corroboration_spread['median_spread_q']:.3f}, "
                  f"low-half pnl/trade=${corroboration_spread['low_pnl_per_trade']:.2f}, "
                  f"high-half pnl/trade=${corroboration_spread['high_pnl_per_trade']:.2f}."
               ),
            ],
            "module_or_parameter": "liquidity.mqh / config.mqh spread gates (SpreadMultATR, MaxSpreadPoints)",
            "expected_delta_usd": expected_delta_usd,
            "expected_delta_pct": round(expected_delta_usd * PCT_CONVERSION, 4),
            "confidence": "medium",
            "reliability_risk": "medium; tightening spread tolerance can protect expectancy but can also reduce entries and min-trade-day coverage.",
            "validation_rerun_needed": (
               "Untouched holdout, then later report-window matrix with mild/moderate stress to ensure no overfitting."
            ),
         }
      )

   changes.sort(key=lambda item: (item["rank_hint"], -item["expected_delta_usd"]))
   for index, item in enumerate(changes, start=1):
      item["rank"] = index
   return changes


def build_reconciliation_summary(
   *,
   run_input: PhaseARunInput,
   summary: dict[str, Any],
   daily_rows: list[dict[str, str]],
   research_daily: list[dict[str, Any]],
   trades: list[dict[str, Any]],
) -> dict[str, Any]:
   expected_trades = int(summary["trades_total"])
   actual_trades = len(trades)
   expected_pnl = round(float(summary["final_balance"]) - float(summary["initial_balance"]), 2)
   actual_pnl = round(sum(float(item["realized_pnl"]) for item in trades), 2)

   daily_match = len(daily_rows) == len(research_daily)
   if daily_match:
      for source_row, research_row in zip(daily_rows, research_daily):
         for field_name in DAILY_SOURCE_FIELDS:
            if source_row.get(field_name, "") != research_row.get(field_name, ""):
               daily_match = False
               break
         if not daily_match:
            break

   return {
      "run_id": run_input.id,
      "expected_trade_count": expected_trades,
      "actual_trade_count": actual_trades,
      "trade_count_match": expected_trades == actual_trades,
      "expected_realized_pnl": expected_pnl,
      "actual_realized_pnl": actual_pnl,
      "realized_pnl_within_tolerance": math.isclose(expected_pnl, actual_pnl, rel_tol=0.0, abs_tol=0.01),
      "daily_csv_match": daily_match,
   }


def build_lineage_spot_check(candidates: list[dict[str, Any]]) -> dict[str, Any]:
   target_ts = "2025-11-03T02:16:59"
   target_candidates = [
      item
      for item in candidates
      if item["run_id"] == "holdout" and item["decision_ts"] == target_ts and item["symbol"] == "XAUUSD"
   ]
   if len(target_candidates) != 1:
      return {"passed": False, "reason": f"expected exactly one holdout candidate at {target_ts}, found {len(target_candidates)}"}

   candidate = target_candidates[0]
   missing = [
      field_name
      for field_name in (
         "meta_policy_source_row",
         "risk_sizing_source_row",
         "order_plan_source_row",
         "intent_accept_source_row",
         "execute_order_success_source_row",
         "place_ok_source_row",
      )
      if not candidate.get(field_name)
   ]
   return {
      "passed": not missing,
      "candidate_id": candidate["candidate_id"],
      "missing_steps": missing,
      "sequence": {
         "MetaPolicy.EVAL": f"{candidate['meta_policy_source_file']}:{candidate['meta_policy_source_row']}",
         "Risk.SIZING": f"{candidate['risk_sizing_source_file']}:{candidate['risk_sizing_source_row']}",
         "Allocator.ORDER_PLAN": f"{candidate['order_plan_source_file']}:{candidate['order_plan_source_row']}",
         "INTENT_ACCEPT": f"{candidate['intent_accept_source_file']}:{candidate['intent_accept_source_row']}",
         "EXECUTE_ORDER_SUCCESS": (
            f"{candidate['execute_order_success_source_file']}:{candidate['execute_order_success_source_row']}"
         ),
         "PLACE_OK": f"{candidate['place_ok_source_file']}:{candidate['place_ok_source_row']}",
      },
   }


def build_summary(
   *,
   runs: tuple[PhaseARunInput, ...],
   candidates_by_run: dict[str, list[dict[str, Any]]],
   gate_intervals_by_run: dict[str, list[dict[str, Any]]],
   trades_by_run: dict[str, list[dict[str, Any]]],
   daily_by_run: dict[str, list[dict[str, Any]]],
   summaries_by_run: dict[str, dict[str, Any]],
   daily_source_by_run: dict[str, list[dict[str, str]]],
   invariant_summaries: dict[str, dict[str, Any]],
) -> dict[str, Any]:
   run_summaries: dict[str, dict[str, Any]] = {}
   for run_input in runs:
      trades = trades_by_run[run_input.id]
      candidates = candidates_by_run[run_input.id]
      gates = gate_intervals_by_run[run_input.id]
      research_daily = daily_by_run[run_input.id]
      summary = summaries_by_run[run_input.id]
      run_summaries[run_input.id] = {
         "baseline_role": run_input.baseline_role,
         "root": safe_relative(run_input.root),
         "manifest_path": safe_relative(run_input.manifest_path),
         "summary_path": safe_relative(run_input.summary_path),
         "daily_path": safe_relative(run_input.daily_path),
         "report_path": safe_relative(run_input.report_path),
         "summary_snapshot": {
            "trades_total": int(summary["trades_total"]),
            "final_return_pct": float(summary["final_return_pct"]),
            "final_balance": float(summary["final_balance"]),
            "any_daily_breach": bool(summary["any_daily_breach"]),
            "overall_breach": bool(summary["overall_breach"]),
         },
         "candidate_count": len(candidates),
         "candidate_valid_count": sum(1 for item in candidates if item["plan_valid"] == "true"),
         "candidate_executed_count": sum(1 for item in candidates if item["entry_ticket"]),
         "gate_summary": summarize_gate_intervals(gates),
         "trade_summary": summarize_trades(trades),
         "reconciliation": build_reconciliation_summary(
            run_input=run_input,
            summary=summary,
            daily_rows=daily_source_by_run[run_input.id],
            research_daily=research_daily,
            trades=trades,
         ),
         "invariants": invariant_summaries[run_input.id],
      }

   changes = build_change_candidates(run_summaries)
   holdout_reconciliation = run_summaries["holdout"]["reconciliation"]

   return {
      "generated_at_utc": utc_now_iso(),
      "phase_source": PHASE_SOURCE,
      "commit": "d0e5558",
      "baseline": {
         "holdout_dir": safe_relative(runs[0].root),
         "corroboration_dir": safe_relative(runs[1].root),
         "phase_b_required": False,
         "phase_b_reason": "Phase A invariants, joins, and trade pairing completed on the pinned artifacts.",
      },
      "acceptance_checks": {
         "holdout_trade_count_107": holdout_reconciliation["actual_trade_count"] == 107,
         "holdout_pnl_78_61": math.isclose(holdout_reconciliation["actual_realized_pnl"], 78.61, rel_tol=0.0, abs_tol=0.01),
         "holdout_daily_csv_match": holdout_reconciliation["daily_csv_match"],
         "candidate_lineage_spot_check": build_lineage_spot_check(candidates_by_run["holdout"]),
      },
      "runs": run_summaries,
      "recommended_changes": changes,
   }


def render_change_rankings(summary: dict[str, Any]) -> str:
   lines = [
      "# Research Change Rankings",
      "",
      f"Phase source: {PHASE_SOURCE} artifact analysis only.",
      "",
   ]
   changes = summary.get("recommended_changes", [])
   if not changes:
      lines.extend(
         [
            "No lever met the promotion bar from Phase A alone.",
            "",
            "The pinned artifacts still support narrow validation next, but the current evidence is stronger as a watchlist than as a ranked rerun slate.",
         ]
      )
      return "\n".join(lines) + "\n"

   for change in changes:
      lines.extend(
         [
            f"## {change['rank']}. {change['title']}",
            "",
            f"- Phase source: {change['phase_source']}",
            f"- Problem observed: {change['problem_observed']}",
            f"- Evidence: {change['evidence'][0]}",
            f"- Evidence: {change['evidence'][1]}",
            f"- Exact parameter/module: {change['module_or_parameter']}",
            f"- Expected delta: about +${change['expected_delta_usd']:.2f} ({change['expected_delta_pct']:.4f}%) on holdout, treated as a conservative heuristic rather than a guaranteed gain.",
            f"- Risk to pass reliability: {change['reliability_risk']}",
            f"- Validation rerun needed: {change['validation_rerun_needed']}",
            "",
         ]
      )
   return "\n".join(lines)


def write_csv_rows(path: Path, rows: list[dict[str, Any]], fieldnames: Iterable[str]) -> None:
   hpo.ensure_directory(path.parent)
   with path.open("w", encoding="utf-8", newline="") as handle:
      writer = csv.DictWriter(handle, fieldnames=list(fieldnames))
      writer.writeheader()
      for row in rows:
         writer.writerow({name: row.get(name, "") for name in writer.fieldnames})


def write_outputs(
   *,
   output_dir: Path,
   candidates: list[dict[str, Any]],
   gate_intervals: list[dict[str, Any]],
   trades: list[dict[str, Any]],
   research_daily: list[dict[str, Any]],
   summary: dict[str, Any],
) -> dict[str, str]:
   candidate_fields = [
      "run_id",
      "baseline_role",
      "candidate_id",
      "decision_ts",
      "symbol",
      "signal_symbol",
      "strategy",
      "setup_type",
      "requested_entry_price",
      "sl",
      "tp",
      "volume",
      "comment",
      "plan_valid",
      "rejection_reason",
      "intent_id",
      "entry_ticket",
      "ticket_source",
      "order_sent",
      "place_ok",
      "place_retcode",
      "logged_worst_case_risk_money",
      "effective_risk_pct",
      "risk_raw_volume",
      "risk_floored_volume",
      "risk_final_volume",
      "volume_min",
      "volume_step",
      "risk_raw_gap_to_min_lot_frac",
      "risk_floored_gap_to_min_lot_frac",
      "risk_volume_zero_subcause",
      "risk_volume_zero_reference_volume",
      "risk_volume_zero_gap_to_min_lot_frac",
      "volume_zero_subcause",
      "volume_zero_reference_volume",
      "volume_zero_gap_to_min_lot_frac",
      "budget_scaled_raw_volume",
      "budget_scaled_floored_volume",
      "meta_choice",
      "meta_confidence",
      "meta_regime",
      "meta_gating_reason",
      "meta_news_window_state",
      "meta_spread_q",
      "meta_slippage_q",
      "meta_hold_time_min",
      "meta_emrt",
      "meta_policy_source_file",
      "meta_policy_source_row",
      "risk_sizing_source_file",
      "risk_sizing_source_row",
      "order_plan_source_file",
      "order_plan_source_row",
      "intent_accept_source_file",
      "intent_accept_source_row",
      "execute_order_success_source_file",
      "execute_order_success_source_row",
      "place_ok_source_file",
      "place_ok_source_row",
   ]
   gate_fields = [
      "run_id",
      "baseline_role",
      "gate_family",
      "symbol",
      "normalized_key",
      "start_ts",
      "end_ts",
      "row_count",
      "duration_seconds",
      "source_first_file",
      "source_first_row",
      "source_last_file",
      "source_last_row",
      "reason",
      "news",
      "spread_ok",
      "in_session",
      "in_or",
      "anomaly_block",
      "anomaly_action",
      "choice",
      "gating_reason",
      "regime",
      "news_window_state",
   ]
   trade_fields = list(
      (
         "run_id",
         "baseline_role",
         *REQUIRED_TRADE_FIELDS,
         "requested_entry_price",
         "sl",
         "tp",
         "confidence",
         "regime",
         "spread_q",
         "slippage_q",
         "logged_worst_case_risk_money",
         "entry_order_id",
         "entry_deal_id",
         "exit_order_id",
         "exit_deal_id",
         "exit_comment",
      )
   )
   daily_fields = [
      "run_id",
      "baseline_role",
      *DAILY_SOURCE_FIELDS,
      "trade_count_closed",
      "trade_realized_pnl",
      "trade_realized_r_sum",
      "trade_friction_r_sum",
      "trade_exit_count_timestop",
      "trade_exit_count_stop_loss",
      "candidate_count",
      "candidate_valid_count",
      "candidate_executed_count",
      "gate_interval_count",
      "gate_interval_seconds",
      "liquidity_gate_interval_count",
      "scheduler_gate_interval_count",
      "metapolicy_skip_interval_count",
   ]

   candidates_path = output_dir / "research_candidates.csv"
   gates_path = output_dir / "research_gate_intervals.csv"
   trades_path = output_dir / "research_trades.csv"
   daily_path = output_dir / "research_daily.csv"
   summary_path = output_dir / "research_attribution_summary.json"
   rankings_path = output_dir / "research_change_rankings.md"

   write_csv_rows(candidates_path, candidates, candidate_fields)
   write_csv_rows(gates_path, gate_intervals, gate_fields)
   write_csv_rows(trades_path, trades, trade_fields)
   write_csv_rows(daily_path, research_daily, daily_fields)
   summary_path.write_text(stable_json(summary) + "\n", encoding="utf-8")
   rankings_path.write_text(render_change_rankings(summary), encoding="utf-8")

   return {
      "research_candidates": str(candidates_path),
      "research_gate_intervals": str(gates_path),
      "research_trades": str(trades_path),
      "research_daily": str(daily_path),
      "research_attribution_summary": str(summary_path),
      "research_change_rankings": str(rankings_path),
   }


def build_phase_a_research(output_dir: Path, runs: tuple[PhaseARunInput, ...]) -> dict[str, Any]:
   candidates_by_run: dict[str, list[dict[str, Any]]] = {}
   gate_intervals_by_run: dict[str, list[dict[str, Any]]] = {}
   trades_by_run: dict[str, list[dict[str, Any]]] = {}
   daily_by_run: dict[str, list[dict[str, Any]]] = {}
   summaries_by_run: dict[str, dict[str, Any]] = {}
   daily_source_by_run: dict[str, list[dict[str, str]]] = {}
   invariant_summaries: dict[str, dict[str, Any]] = {}

   all_candidates: list[dict[str, Any]] = []
   all_gates: list[dict[str, Any]] = []
   all_trades: list[dict[str, Any]] = []
   all_daily: list[dict[str, Any]] = []

   for run_input in runs:
      decision_rows = parse_decision_logs(run_input)
      event_rows = parse_event_logs(run_input)
      orders, deals = parse_report_tables(run_input.report_path)
      daily_rows = hpo.load_csv_rows(run_input.daily_path)
      summary = hpo.load_json_file(run_input.summary_path)

      candidates = build_candidates(decision_rows, event_rows)
      gate_intervals = parse_gate_intervals(run_input)
      trades, invariant_summary = build_trades(
         run_input=run_input,
         candidates=candidates,
         decision_rows=decision_rows,
         orders=orders,
         deals=deals,
      )
      research_daily = build_research_daily(
         run_input=run_input,
         daily_rows=daily_rows,
         candidates=candidates,
         trades=trades,
         gate_intervals=gate_intervals,
      )

      candidates_by_run[run_input.id] = candidates
      gate_intervals_by_run[run_input.id] = gate_intervals
      trades_by_run[run_input.id] = trades
      daily_by_run[run_input.id] = research_daily
      summaries_by_run[run_input.id] = summary
      daily_source_by_run[run_input.id] = daily_rows
      invariant_summaries[run_input.id] = invariant_summary

      all_candidates.extend(candidates)
      all_gates.extend(gate_intervals)
      all_trades.extend(trades)
      all_daily.extend(research_daily)

   all_candidates.sort(key=lambda item: (item["run_id"], item["decision_ts"], item["candidate_id"]))
   all_gates.sort(key=lambda item: (item["run_id"], item["start_ts"], item["gate_family"], item["symbol"]))
   all_trades.sort(key=lambda item: (item["run_id"], item["entry_time"], int(item["entry_ticket"])))
   all_daily.sort(key=lambda item: (item["run_id"], item["server_date"]))

   summary = build_summary(
      runs=runs,
      candidates_by_run=candidates_by_run,
      gate_intervals_by_run=gate_intervals_by_run,
      trades_by_run=trades_by_run,
      daily_by_run=daily_by_run,
      summaries_by_run=summaries_by_run,
      daily_source_by_run=daily_source_by_run,
      invariant_summaries=invariant_summaries,
   )
   outputs = write_outputs(
      output_dir=output_dir,
      candidates=all_candidates,
      gate_intervals=all_gates,
      trades=all_trades,
      research_daily=all_daily,
      summary=summary,
   )
   return {"summary": summary, "outputs": outputs}


def parse_args(argv: list[str]) -> argparse.Namespace:
   parser = argparse.ArgumentParser(description=__doc__)
   parser.add_argument("command", nargs="?", choices=("build",), default="build")
   parser.add_argument("--output-dir", default=None, help="Output directory for normalized Phase A artifacts.")
   parser.add_argument("--holdout-dir", default=None, help="Override holdout run directory.")
   parser.add_argument("--corroboration-dir", default=None, help="Override corroboration run directory.")
   return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
   args = parse_args(argv or sys.argv[1:])
   holdout_root = repo_root() / Path(args.holdout_dir) if args.holdout_dir else repo_root() / DEFAULT_HOLDOUT_DIR
   corroboration_root = (
      repo_root() / Path(args.corroboration_dir) if args.corroboration_dir else repo_root() / DEFAULT_CORROBORATION_DIR
   )
   runs = (
      load_phase_a_run_input(root=holdout_root, run_id="holdout", baseline_role=PRIMARY_ROLE),
      load_phase_a_run_input(
         root=corroboration_root,
         run_id="contiguous_public_rule3",
         baseline_role=SECONDARY_ROLE,
      ),
   )
   output_dir = (
      Path(args.output_dir).resolve()
      if args.output_dir
      else (repo_root() / DEFAULT_RESEARCH_ROOT / DEFAULT_RESEARCH_NAME).resolve()
   )

   try:
      result = build_phase_a_research(output_dir, runs)
   except PhaseABlocked as exc:
      print(json.dumps({"status": "blocked", "phase_source": PHASE_SOURCE, "blocker": str(exc)}, indent=2))
      return 2

   output = {
      "status": "completed",
      "phase_source": PHASE_SOURCE,
      "output_dir": str(output_dir),
      "outputs": result["outputs"],
      "acceptance_checks": result["summary"]["acceptance_checks"],
      "phase_b_required": result["summary"]["baseline"]["phase_b_required"],
      "phase_b_reason": result["summary"]["baseline"]["phase_b_reason"],
   }
   print(json.dumps(output, indent=2))
   return 0


if __name__ == "__main__":  # pragma: no cover - CLI entrypoint
   raise SystemExit(main())
