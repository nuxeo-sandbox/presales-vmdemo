"""Report a stack's CloudFormation status and record its completion in the
batch's deletion-log.csv.

Exit code 3 = still in progress, 0 = gone or failed.

Run as:
    python3 -m cfcleanup status <stack> <region> [--batch NAME|DIR]
"""
from __future__ import annotations

import argparse
import csv
import os
import subprocess
from datetime import datetime, timezone

from . import common as cf


def stack_status(stack: str, region: str) -> str:
    out = subprocess.run(
        [
            "aws", "cloudformation", "describe-stacks", "--stack-name", stack,
            "--region", region, "--query", "Stacks[0].StackStatus", "--output", "text",
        ],
        capture_output=True,
        text=True,
    )
    if out.returncode == 0 and out.stdout.strip():
        return out.stdout.strip()
    text = (out.stdout + out.stderr).strip()
    if "does not exist" in text:
        return "DELETE_COMPLETE" if _deleted_in_history(stack, region) else "NOT_FOUND"
    return f"ERROR:{text}"


def _deleted_in_history(stack: str, region: str) -> bool:
    """True if CloudFormation still lists a DELETE_COMPLETE stack of this name."""
    out = subprocess.run(
        [
            "aws", "cloudformation", "list-stacks", "--region", region,
            "--stack-status-filter", "DELETE_COMPLETE",
            "--query", f"StackSummaries[?StackName=='{stack}'] | [0].StackName",
            "--output", "text",
        ],
        capture_output=True,
        text=True,
    )
    return out.returncode == 0 and stack in out.stdout.split()


def append_complete(log: str, stack: str, region: str) -> None:
    """Append a 'complete' event for the stack (once, if it was initiated)."""
    if not os.path.exists(log):
        return
    rows = list(csv.reader(open(log)))
    hdr, body = rows[0], rows[1:]
    si, pi = hdr.index("stack"), hdr.index("phase")
    initiated = any(r[si] == stack and r[pi] == "initiated" for r in body)
    completed = any(r[si] == stack and r[pi] == "complete" for r in body)
    if not initiated or completed:
        return
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(log, "a", newline="") as f:
        csv.writer(f).writerow([ts, stack, region, "", "", "complete", ""])


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m cfcleanup status")
    ap.add_argument("stack")
    ap.add_argument("region")
    ap.add_argument("--batch")
    args = ap.parse_args(argv)

    batch = cf.resolve_batch(args.batch)
    log = os.path.join(batch, "deletion-log.csv")

    st = stack_status(args.stack, args.region)
    if st == "NOT_FOUND":
        print(f"{args.stack:<32} {args.region:<15} not found")
        return 0
    if st == "DELETE_COMPLETE":
        append_complete(log, args.stack, args.region)
    print(f"{args.stack:<32} {args.region:<15} {st}")
    if st == "DELETE_COMPLETE" or st.endswith("FAILED"):
        return 0
    return 3
