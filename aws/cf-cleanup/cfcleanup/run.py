"""One-shot, human-driven cleanup of a single stack.

Interrogates the stack, reports the inspection (what would be emptied and
deleted), prompts for confirmation, deletes, then blocks - polling - until the
stack reaches DELETE_COMPLETE. This is the command a human runs directly (see
the `cfcleanup.sh` wrapper).

Run as:
    python3 -m cfcleanup run <stack> [region] [--batch NAME|DIR]
"""
from __future__ import annotations

import argparse
import time

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

    # 1. Interrogate and report (inspection only - changes nothing).
    rc = delete.perform(args.stack, region, batch, dry_run=True)
    if rc != 0:
        return rc

    # 2. Prompt for execution (always interactive).
    try:
        answer = input(f"\nDelete {args.stack} ({region})? [y/N] ").strip().lower()
    except EOFError:
        answer = ""
    if answer not in ("y", "yes"):
        print("Aborted - nothing deleted.")
        return 0

    # 3. Execute.
    rc = delete.perform(args.stack, region, batch, dry_run=False)
    if rc != 0:
        return rc

    # 4. Monitor until the stack is gone.
    print("\nMonitoring until DELETE_COMPLETE ...")
    status_args = (["--batch", args.batch] if args.batch else []) + [args.stack, region]
    while status.main(status_args) == 3:
        time.sleep(POLL_SECONDS)
    return 0
