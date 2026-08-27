"""Report the CloudFormation status of stacks whose deletion was initiated in a
batch. Fast and NON-BLOCKING: one describe call per stack. Re-run to watch
progress.

When a stack has finished deleting (no longer exists), its log phase is flipped
from 'initiated' to 'complete' so it drops out of future "all" checks.

Exit code 3 = something still in progress, 0 = all done.

Run as:
    python3 -m cfcleanup status [--batch NAME|DIR] [<stack> <region>]
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
    text = (out.stdout + out.stderr).strip()
    if "does not exist" in text:
        return "GONE"
    if out.returncode != 0 or not out.stdout.strip():
        return f"ERROR:{text}"
    return out.stdout.strip()


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


def initiated_targets(log: str) -> list[tuple[str, str]]:
    if not os.path.exists(log):
        return []
    rows = list(csv.reader(open(log)))
    hdr, body = rows[0], rows[1:]
    si, ri, pi = hdr.index("stack"), hdr.index("region"), hdr.index("phase")
    return [(r[si], r[ri]) for r in body if r[pi] == "initiated"]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m cfcleanup status")
    ap.add_argument("--batch")
    ap.add_argument("stack", nargs="?")
    ap.add_argument("region", nargs="?")
    args = ap.parse_args(argv)

    batch = cf.resolve_batch(args.batch)
    log = os.path.join(batch, "deletion-log.csv")

    if args.stack and args.region:
        targets = [(args.stack, args.region)]
    else:
        targets = initiated_targets(log)

    if not targets:
        print(f"No in-flight deletions to monitor (nothing 'initiated') in {os.path.basename(batch)}.")
        return 0

    print(f"{'STACK':<32} {'REGION':<15} STATUS")
    print(f"{'-----':<32} {'------':<15} ------")
    pending = 0
    for stack, region in targets:
        st = stack_status(stack, region)
        if st == "GONE":
            st = "DELETE_COMPLETE (gone)"
            mark_complete(log, stack)
        elif st.endswith("FAILED"):
            pass  # surface as-is, not pending
        else:
            pending += 1
        print(f"{stack:<32} {region:<15} {st}")

    print()
    if pending:
        print(f"{pending} still in progress - re-run 'python3 -m cfcleanup status' to refresh.")
        return 3
    print("All monitored deletions have finished.")
    return 0
