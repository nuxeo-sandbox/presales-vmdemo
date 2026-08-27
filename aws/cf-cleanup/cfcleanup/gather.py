"""Enumerate all CloudFormation stacks per region into a fresh cleanup batch.

A batch is one cleanup cycle: gather -> report -> workbook -> review -> delete.
Creates batches/<name>/ (default name is <UTC-date>-cf-cleanup-batch) and writes:
    stacks/<region>.json   raw describe-stacks output, one file per region
    batch.json             gather timestamp + account id (used for age math)

Regions default to every region enabled for the account (auto-discovered via
`aws ec2 describe-regions`); override with --regions or the CF_REGIONS env var
(space- or comma-separated).

Run as:
    python3 -m cfcleanup gather [--name NAME] [--regions "us-east-1 eu-west-1 ..."]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

from . import common as cf


def aws_text(args: list[str]) -> str:
    out = subprocess.run(["aws", *args], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else ""


def discover_regions() -> list[str]:
    """Every region enabled for the account; falls back to REGIONS_ORDER on failure."""
    txt = aws_text(["ec2", "describe-regions", "--query", "Regions[].RegionName", "--output", "text"])
    found = txt.split()
    return cf.sort_regions(found) if found else list(cf.REGIONS_ORDER)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m cfcleanup gather")
    ap.add_argument("--name", help="batch name (default: <UTC-date>-cf-cleanup-batch)")
    ap.add_argument("--regions", help="space/comma separated region list")
    args = ap.parse_args(argv)

    regions_src = args.regions or os.environ.get("CF_REGIONS")
    if regions_src:
        regions = [r for r in regions_src.replace(",", " ").split() if r]
    else:
        regions = discover_regions()
        print(f"Auto-discovered {len(regions)} enabled region(s).")

    batch = cf.new_batch(args.name)
    print(f"Batch: {batch}")

    account = aws_text(["sts", "get-caller-identity", "--query", "Account", "--output", "text"])
    for region in regions:
        print(f"  gathering {region} ...")
        out = subprocess.run(
            ["aws", "cloudformation", "describe-stacks", "--region", region, "--output", "json"],
            capture_output=True,
            text=True,
        )
        if out.returncode != 0:
            print(f"  WARNING: {region}: {out.stderr.strip()}", file=sys.stderr)
            payload = '{"Stacks": []}'
        else:
            payload = out.stdout
        with open(os.path.join(batch, "stacks", f"{region}.json"), "w") as fh:
            fh.write(payload)

    meta = {
        "gathered_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "account": account,
    }
    with open(os.path.join(batch, "batch.json"), "w") as fh:
        json.dump(meta, fh, indent=2)
    print(f"Wrote {batch}/batch.json  ({meta['gathered_utc']}, account {account})")
    print("Next: python3 -m cfcleanup report && python3 -m cfcleanup workbook")
    return 0
