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


def aws_run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(["aws", *args], capture_output=True, text=True)


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

    # 1. Require a human "Delete" decision in the workbook before doing anything.
    rc = decision_check(args.stack, batch, args.workbook)
    if rc != 0:
        print("ABORT: not human-marked 'Delete' in the workbook. Set Decision='Delete' first.")
        return rc

    # 2. Confirm the AWS session is valid up front, so a lapsed token can't masquerade
    # downstream as an empty bucket or a missing stack.
    who = aws_run(["sts", "get-caller-identity", "--query", "Arn", "--output", "text"])
    if who.returncode != 0:
        print("ABORT: AWS credentials are not valid (often an expired SSO session). "
              "Re-authenticate and retry.")
        err = (who.stderr or "").strip()
        if err:
            print(f"  aws error: {err}")
        return 1

    # 3. Read the bucket mode from the stack's parameters. No UseS3Bucket parameter
    # reads back as "None"; a failed call aborts rather than deleting blindly.
    params = aws_run(
        [
            "cloudformation", "describe-stacks", "--stack-name", args.stack,
            "--region", args.region,
            "--query", "Stacks[0].Parameters[?ParameterKey=='UseS3Bucket'].ParameterValue | [0]",
            "--output", "text",
        ]
    )
    if params.returncode != 0:
        print("ABORT: could not read the stack's bucket mode (describe-stacks failed) - "
              "refusing to delete without knowing what to empty.")
        err = (params.stderr or "").strip()
        if err:
            print(f"  aws error: {err}")
        return 1
    mode = params.stdout.strip() or "None"
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

    # 4. Empty the bucket (or just the stack's folder in the shared bucket).
    if bucket:
        empty_location(bucket, prefix, args.dry_run)

    # 5. Initiate stack deletion. NON-BLOCKING: returns immediately.
    if args.dry_run:
        print(f"DRY-RUN> aws cloudformation delete-stack --stack-name {args.stack} --region {args.region}")
    else:
        r = subprocess.run(
            ["aws", "cloudformation", "delete-stack", "--stack-name", args.stack, "--region", args.region]
        )
        if r.returncode != 0:
            return r.returncode

    # 6. Append an "initiated" event to the paper-trail log.
    if not args.dry_run:
        arn = who.stdout.strip()
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
        print(f"When DELETE_COMPLETE, get the manual workbook entry with:  python3 -m cfcleanup log {args.stack}")
    return 0
