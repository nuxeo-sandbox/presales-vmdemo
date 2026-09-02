"""Delete a presales CloudFormation demo stack, emptying its S3 storage first.

The caller supplies the stack id and, optionally, its region.

Paper-trail tool: every run appends a line to the batch's deletion-log.csv.

NON-BLOCKING: empties the bucket (fast), then initiates the stack delete and
returns immediately. It does NOT wait for DELETE_COMPLETE. Poll with the
status command.

Bucket modes (from aws/cf-templates/Nuxeo.template UseS3Bucket):
    Create -> dedicated bucket "<stack>-bucket"      (whole bucket emptied)
    Shared -> shared bucket   "<region>-demo-bucket" (only "<stack>/" folder)
    None   -> no bucket

Requires: awscli v2, authenticated to the target account.

The region is optional: if omitted it is resolved from the batch's gather data
(falling back to a live scan of the account's enabled regions).

Run as:
    python3 -m cfcleanup delete <stack> [region] [--dry-run] [--batch NAME|DIR]
"""
from __future__ import annotations

import argparse
import csv
import os
import subprocess
from datetime import datetime, timezone

from . import common as cf
from . import gather
from .s3 import empty_location


def aws_run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(["aws", *args], capture_output=True, text=True)


def _resolve_region(batch: str, stack: str) -> tuple[str | None, str]:
    """Determine a stack's region when the caller omits it.

    Prefer the batch's gather data (no API calls); fall back to scanning the
    account's enabled regions live. Returns (region, note) or (None, reason).
    """
    regions = cf.find_stack_regions(batch, stack)
    if len(regions) == 1:
        return regions[0], "from batch data"
    if len(regions) > 1:
        return None, f"ambiguous - '{stack}' appears in {regions}; pass the region explicitly"
    for region in gather.discover_regions():
        got = aws_run(
            ["cloudformation", "describe-stacks", "--stack-name", stack, "--region", region,
             "--query", "Stacks[0].StackName", "--output", "text"]
        )
        if got.returncode == 0 and got.stdout.strip() == stack:
            return region, f"found live in {region}"
    return None, f"'{stack}' not found in the batch or any enabled region - check the name"


def perform(stack: str, region: str, batch: str, dry_run: bool) -> int:
    """Interrogate the stack, empty its S3 storage, and (unless dry_run) delete it.

    With dry_run=True this only inspects and reports what would happen - it
    changes nothing. Shared by the `delete` and `run` commands.
    """
    log = os.path.join(batch, "deletion-log.csv")
    label = "Inspecting" if dry_run else "Deleting"
    print(f"=== {label} stack: {stack} ({region})   [batch: {os.path.basename(batch)}] ===")

    # 1. Read the bucket mode. A missing UseS3Bucket parameter reads back as "None".
    params = aws_run(
        [
            "cloudformation", "describe-stacks", "--stack-name", stack,
            "--region", region,
            "--query", "Stacks[0].Parameters[?ParameterKey=='UseS3Bucket'].ParameterValue | [0]",
            "--output", "text",
        ]
    )
    if params.returncode != 0:
        print("ABORT: could not read the stack's bucket mode (describe-stacks failed).")
        err = (params.stderr or "").strip()
        if err:
            print(f"  aws error: {err}")
        return 1
    mode = params.stdout.strip() or "None"
    print(f"UseS3Bucket = {mode}")

    bucket = prefix = ""
    if mode == "Create":
        bucket = f"{stack}-bucket"
    elif mode == "Shared":
        bucket, prefix = f"{region}-demo-bucket", f"{stack}/"
    elif mode == "None":
        print("No bucket to empty.")
    else:
        print(f"WARNING: unknown/missing bucket mode ('{mode}'); skipping bucket emptying.")

    # 2. Empty the bucket (or just the stack's folder in the shared bucket).
    if bucket:
        empty_location(bucket, prefix, dry_run)

    # 3. Initiate stack deletion. NON-BLOCKING: returns immediately.
    if dry_run:
        print(f"DRY-RUN> aws cloudformation delete-stack --stack-name {stack} --region {region}")
        return 0

    r = subprocess.run(
        ["aws", "cloudformation", "delete-stack", "--stack-name", stack, "--region", region]
    )
    if r.returncode != 0:
        return r.returncode

    # 4. Append the deletion to the log.
    who = aws_run(["sts", "get-caller-identity", "--query", "Arn", "--output", "text"])
    by = who.stdout.strip().rsplit("/", 1)[-1] if who.returncode == 0 else ""
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    new = not os.path.exists(log)
    with open(log, "a", newline="") as fh:
        w = csv.writer(fh)
        if new:
            w.writerow(["timestamp_utc", "stack", "region", "bucket_mode", "bucket", "phase", "deleted_by"])
        w.writerow([ts, stack, region, mode, bucket or "none", "initiated", by])
    print(f"Delete initiated and logged to {log}")
    print("Monitor with:  python3 -m cfcleanup status")
    return 0


def resolve_region(batch: str, stack: str, given: str | None) -> str | None:
    """Return the region to act on: the one given, else resolved from the batch."""
    if given:
        return given
    region, note = _resolve_region(batch, stack)
    if region is None:
        print(f"ABORT: {note}")
        return None
    print(f"Region for '{stack}': {region} ({note})")
    return region


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m cfcleanup delete")
    ap.add_argument("stack")
    ap.add_argument("region", nargs="?")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--batch")
    args = ap.parse_args(argv)

    batch = cf.resolve_batch(args.batch)
    region = resolve_region(batch, args.stack, args.region)
    if region is None:
        return 1
    return perform(args.stack, region, batch, args.dry_run)
