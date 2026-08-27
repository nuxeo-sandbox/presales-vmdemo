"""Delete a presales CloudFormation demo stack, emptying its S3 storage first.

Paper-trail tool: every run appends a line to the batch's deletion-log.csv.

NON-BLOCKING: empties the bucket (fast), then initiates the stack delete and
returns immediately. It does NOT wait for DELETE_COMPLETE. Poll with the
status command.

Bucket modes (from aws/cf-templates/Nuxeo.template UseS3Bucket):
    Create -> dedicated bucket "<stack>-bucket"      (whole bucket emptied)
    Shared -> shared bucket   "<region>-demo-bucket" (only "<stack>/" folder)
    None   -> no bucket

Requires: awscli v2, authenticated to the target account.

Run as:
    python3 -m cfcleanup delete <stack> <region> [--dry-run] [--batch NAME|DIR]
"""
from __future__ import annotations

import argparse
import csv
import os
import subprocess
from datetime import datetime, timezone

from . import common as cf
from .decision import check as decision_check
from .s3 import empty_location


def aws_text(args: list[str]) -> str:
    out = subprocess.run(["aws", *args], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else ""


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m cfcleanup delete")
    ap.add_argument("stack")
    ap.add_argument("region")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--batch")
    ap.add_argument("--workbook", help="Path to the reviewed workbook (defaults to CF_WORKBOOK, then the batch's own).")
    args = ap.parse_args(argv)

    batch = cf.resolve_batch(args.batch)
    log = os.path.join(batch, "deletion-log.csv")
    print(f"=== Deleting stack: {args.stack} ({args.region})   [batch: {os.path.basename(batch)}] ===")

    # 0. Safety gate: a human must have marked this stack "Delete" in the workbook.
    rc = decision_check(args.stack, batch, args.workbook)
    if rc != 0:
        print("ABORT: not human-marked 'Delete' in the workbook. Set Decision='Delete' first.")
        return rc

    # 1. Determine bucket mode from the stack's parameters.
    mode = (
        aws_text(
            [
                "cloudformation", "describe-stacks", "--stack-name", args.stack,
                "--region", args.region,
                "--query", "Stacks[0].Parameters[?ParameterKey=='UseS3Bucket'].ParameterValue | [0]",
                "--output", "text",
            ]
        )
        or "MISSING"
    )
    print(f"UseS3Bucket = {mode}")

    bucket = prefix = ""
    if mode == "Create":
        bucket = f"{args.stack}-bucket"
    elif mode == "Shared":
        bucket, prefix = f"{args.region}-demo-bucket", f"{args.stack}/"
    elif mode == "None":
        print("No bucket to empty.")
    else:
        print(f"WARNING: unknown/missing bucket mode ('{mode}'); skipping bucket emptying.")

    # 2. Empty the bucket (or just the stack's folder in the shared bucket).
    if bucket:
        empty_location(bucket, prefix, args.dry_run)

    # 3. Initiate stack deletion. NON-BLOCKING: returns immediately.
    if args.dry_run:
        print(f"DRY-RUN> aws cloudformation delete-stack --stack-name {args.stack} --region {args.region}")
    else:
        r = subprocess.run(
            ["aws", "cloudformation", "delete-stack", "--stack-name", args.stack, "--region", args.region]
        )
        if r.returncode != 0:
            return r.returncode

    # 4. Append an "initiated" event to the paper-trail log.
    if not args.dry_run:
        arn = aws_text(["sts", "get-caller-identity", "--query", "Arn", "--output", "text"])
        by = arn.rsplit("/", 1)[-1] if arn else ""
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        new = not os.path.exists(log)
        with open(log, "a", newline="") as fh:
            w = csv.writer(fh)
            if new:
                w.writerow(["timestamp_utc", "stack", "region", "bucket_mode", "bucket", "phase", "deleted_by"])
            w.writerow([ts, args.stack, args.region, mode, bucket or "none", "initiated", by])
        print(f"Delete initiated and logged to {log}")
        print("Monitor with:  python3 -m cfcleanup status")
        print(f"When DELETE_COMPLETE, record it with:  python3 -m cfcleanup log {args.stack}")
    return 0
