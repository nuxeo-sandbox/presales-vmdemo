"""One-shot, human-driven cleanup of a single stack.

Interrogates the stack, reports the inspection (what would be emptied and
deleted), prompts for confirmation, deletes, then blocks - polling - until the
deletion completes. This is the command a human runs directly (see the
`cfcleanup.sh` wrapper).

Run as:
    python3 -m cfcleanup run <stack> [region] [--batch NAME|DIR]
"""
from __future__ import annotations

import argparse
import os
import time
from datetime import date

from . import common as cf
from . import delete, status

POLL_SECONDS = 10


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m cfcleanup run")
    ap.add_argument("stack")
    ap.add_argument("region", nargs="?")
    ap.add_argument("--batch")
    args = ap.parse_args(argv)

    batch = cf.resolve_batch(args.batch)
    region = delete.resolve_region(batch, args.stack, args.region)
    if region is None:
        return 1

    # Header first (local data only), then the session check, then AWS work.
    delete.print_header(args.stack, batch, region)
    if not cf.ensure_session():
        return 1

    # 1. Interrogate and report (inspection only - changes nothing).
    result = delete.inspect(args.stack, region, batch)
    if result is None:
        return 1

    # 2. Prompt for execution (always interactive).
    try:
        answer = input(f"\nReady to delete {args.stack}? [y/N] ").strip().lower()
    except EOFError:
        answer = ""
    if answer not in ("y", "yes"):
        print("Aborted - nothing deleted.")
        return 0

    # 3. Execute.
    mode, targets, inspected = result
    rc = delete.execute(args.stack, region, batch, mode, targets, inspected)
    if rc != 0:
        return rc

    # 4. Monitor until the stack is gone.
    log = os.path.join(batch, "deletion-log.csv")
    while True:
        st = status.stack_status(args.stack, region)
        print(f"  {args.stack} {st}", flush=True)
        if st == "DELETE_COMPLETE":
            status.append_complete(log, args.stack, region)
            print(f"...Stack {args.stack} Deleted {date.today().isoformat()}")
            return 0
        if st == "NOT_FOUND" or st.endswith("FAILED") or st.startswith("ERROR"):
            print(f"...{args.stack} {st}")
            return 1
        time.sleep(POLL_SECONDS)
