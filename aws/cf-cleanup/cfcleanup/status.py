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


def mark_complete(log: str, stack: str) -> None:
    if not os.path.exists(log):
        return
    rows = list(csv.reader(open(log)))
    hdr, body = rows[0], rows[1:]
    pi, si = hdr.index("phase"), hdr.index("stack")
    for r in body:
        if r[si] == stack and r[pi] == "initiated":
            r[pi] = "complete"
    with open(log, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(hdr)
        w.writerows(body)


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
        mark_complete(log, args.stack)
    print(f"{args.stack:<32} {args.region:<15} {st}")
    if st == "DELETE_COMPLETE" or st.endswith("FAILED"):
        return 0
    return 3
