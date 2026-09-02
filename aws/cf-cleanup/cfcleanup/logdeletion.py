"""Show the manual workbook edit for a completed deletion (READ-ONLY).

The reviewed workbook is HUMAN-OWNED. This tool never writes it: rewriting the
shared/OneDrive-synced .xlsx in place corrupts the file's sync state. So instead
of editing the workbook, this command reads it read-only and prints the exact
cells for a human to fill in by hand on the matching 'Cleanup' row:

    Deleted?  ->  Yes
    Notes     ->  <existing text>; Deleted YYYY-MM-DD

The authoritative, machine-written audit trail is the batch's deletion-log.csv,
appended by 'delete' (initiated) and 'status' (complete). This command reports
only; it changes nothing.

Run as:
    python3 -m cfcleanup log <stack-name> [--batch NAME|DIR] [--date YYYY-MM-DD] [--workbook PATH]
"""
from __future__ import annotations

import argparse
import csv
import os
import sys
from datetime import date

from . import common as cf

SHEET = "Cleanup"


def _csv_phase(batch: str, stack: str) -> str | None:
    """Latest deletion-log.csv phase recorded for the stack, or None if absent."""
    log = os.path.join(batch, "deletion-log.csv")
    if not os.path.exists(log):
        return None
    phase = None
    with open(log, newline="") as fh:
        for row in csv.DictReader(fh):
            if row.get("stack") == stack:
                phase = row.get("phase")
    return phase


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m cfcleanup log")
    ap.add_argument("stack")
    ap.add_argument("--batch")
    ap.add_argument("--date", default=date.today().isoformat())
    ap.add_argument("--workbook", help="Path to the reviewed workbook (defaults to CF_WORKBOOK, then the batch's own).")
    args = ap.parse_args(argv)

    batch = cf.resolve_batch(args.batch)
    wb_path = cf.resolve_workbook(batch, args.workbook)
    if wb_path is None:
        sys.exit(f"ERROR: no review workbook (*-cf-cleanup.xlsx) in batch {batch}")

    phase = _csv_phase(batch, args.stack)
    if phase is None:
        print(f"WARNING: '{args.stack}' has no entry in deletion-log.csv - has it actually been deleted?")
    elif phase != "complete":
        print(f"NOTE: '{args.stack}' is logged as '{phase}', not yet 'complete'. "
              "Run 'status' until DELETE_COMPLETE before recording it.")

    # Read-only: locate the stack's row and its existing Notes in a single pass.
    wb = cf.open_workbook_readonly(wb_path)
    ws = wb[SHEET]
    stack_i = notes_i = None
    found_row = None
    existing_notes = ""
    for n, row in enumerate(ws.iter_rows(), start=1):
        if n == 1:
            header = [(str(c.value).strip().lower() if c.value is not None else "") for c in row]
            try:
                stack_i, notes_i = header.index("stack"), header.index("notes")
            except ValueError as exc:
                wb.close()
                sys.exit(f"ERROR: expected column missing on '{SHEET}' sheet: {exc}")
            continue
        val = row[stack_i].value
        if val is not None and str(val).strip() == args.stack:
            found_row = n
            nv = row[notes_i].value
            existing_notes = str(nv).strip() if nv is not None else ""
            break
    wb.close()

    if found_row is None:
        print(f"ERROR: stack '{args.stack}' not found on '{SHEET}' sheet.")
        return 1

    stamp = f"Deleted {args.date}"
    new_notes = f"{existing_notes}; {stamp}" if existing_notes else stamp
    print()
    print("MANUAL WORKBOOK UPDATE - this tool does not write the workbook.")
    print(f"On the '{SHEET}' sheet, row {found_row} ({args.stack}), enter by hand:")
    print("  Deleted?  ->  Yes")
    print(f"  Notes     ->  {new_notes}")
    print()
    return 0
