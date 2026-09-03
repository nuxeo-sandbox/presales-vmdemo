"""Delete a presales CloudFormation demo stack, emptying its S3 storage first.

The caller supplies the stack id and, optionally, its region.

Paper-trail tool: every run appends a line to the batch's deletion-log.csv.

NON-BLOCKING: empties the bucket (fast), then initiates the stack delete and
returns immediately. It does NOT wait for DELETE_COMPLETE. Poll with the
status command.

The stack's own S3 buckets (its AWS::S3::Bucket resources) are emptied entirely.
When the stack's UseS3Bucket parameter is "Shared", its "<stack>/" folder in the
shared bucket "<region>-demo-bucket" is emptied too.

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
from .s3 import bucket_exists, collect_versions, delete_all


def aws_run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(["aws", *args], capture_output=True, text=True)


def stack_buckets(stack: str, region: str) -> list[str] | None:
    """Physical names of the stack's own S3 buckets; None if resources can't be read."""
    out = aws_run(
        [
            "cloudformation", "describe-stack-resources", "--stack-name", stack,
            "--region", region,
            "--query", "StackResources[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId",
            "--output", "text",
        ]
    )
    if out.returncode != 0:
        return None
    return out.stdout.split()


def bucket_mode(stack: str, region: str) -> str:
    """The stack's UseS3Bucket parameter value ('Create'/'Shared'/'None')."""
    out = aws_run(
        [
            "cloudformation", "describe-stacks", "--stack-name", stack,
            "--region", region,
            "--query", "Stacks[0].Parameters[?ParameterKey=='UseS3Bucket'].ParameterValue | [0]",
            "--output", "text",
        ]
    )
    return out.stdout.strip() or "None"


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


def inspect(stack: str, region: str, batch: str):
    """Read the stack's S3 targets, print the report header, and return
    (mode, targets, inspected). Returns None if the stack can't be read."""
    buckets = stack_buckets(stack, region)
    if buckets is None:
        print("ABORT: could not read the stack's resources (describe-stack-resources failed).")
        return None
    mode = bucket_mode(stack, region)
    if buckets:
        s3 = "Created" if mode == "Create" else "Dedicated"
    elif mode == "Shared":
        s3 = "Shared"
    else:
        s3 = "None"
    targets = [(b, "") for b in buckets]
    if mode == "Shared":
        targets.append((f"{region}-demo-bucket", f"{stack}/"))

    inspected = []
    for b, p in targets:
        items = collect_versions(b, p) if bucket_exists(b) else None
        inspected.append((b, p, items))

    bar = "=" * 80
    print(f"{bar}\nDelete {stack}\n{bar}")
    print(f"Batch: {os.path.basename(batch)}")
    print(f"Region: {region}")
    print(f"S3: {s3}")
    for b, p, items in inspected:
        print(f"Bucket: s3://{b}/{p}")
        print("Objects: bucket not found" if items is None else f"Objects: {len(items)} to delete")
    return mode, targets, inspected


def execute(stack: str, region: str, batch: str, mode: str, targets, inspected) -> int:
    """Empty the inspected S3 targets and initiate the stack deletion."""
    log = os.path.join(batch, "deletion-log.csv")

    print()
    print("=== Starting Deletion ===")
    for b, _, items in inspected:
        if items:
            total = len(items)
            print("Deleting objects...", flush=True)
            delete_all(b, items, progress=lambda done, tot: print(f"  deleting {done}/{tot}", flush=True))
            print(f"...{total} objects deleted")
    print("Deleting stack...")
    r = subprocess.run(
        ["aws", "cloudformation", "delete-stack", "--stack-name", stack, "--region", region]
    )
    if r.returncode != 0:
        return r.returncode

    who = aws_run(["sts", "get-caller-identity", "--query", "Arn", "--output", "text"])
    by = who.stdout.strip().rsplit("/", 1)[-1] if who.returncode == 0 else ""
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    new = not os.path.exists(log)
    with open(log, "a", newline="") as fh:
        w = csv.writer(fh)
        if new:
            w.writerow(["timestamp_utc", "stack", "region", "bucket_mode", "bucket", "phase", "deleted_by"])
        w.writerow([ts, stack, region, mode,
                    ";".join(b for b, _ in targets) or "none", "initiated", by])
    return 0


def perform(stack: str, region: str, batch: str, dry_run: bool) -> int:
    """Interrogate the stack, empty its S3 storage, and (unless dry_run) delete it."""
    result = inspect(stack, region, batch)
    if result is None:
        return 1
    mode, targets, inspected = result

    if dry_run:
        print()
        print("=== Dry Run ===")
        print(f"Command: aws cloudformation delete-stack --stack-name {stack} --region {region}")
        return 0

    return execute(stack, region, batch, mode, targets, inspected)


def resolve_region(batch: str, stack: str, given: str | None) -> str | None:
    """Return the region to act on: the one given, else resolved from the batch."""
    if given:
        return given
    region, note = _resolve_region(batch, stack)
    if region is None:
        print(f"ABORT: {note}")
        return None
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
    rc = perform(args.stack, region, batch, args.dry_run)
    if rc == 0 and not args.dry_run:
        print(f"Monitor: python3 -m cfcleanup status {args.stack} {region}")
    return rc
