"""Set up a new cleanup batch in one step: gather -> report -> workbook.

Run as:
    python3 -m cfcleanup setup [--name NAME] [--regions "r1 r2 ..."]
"""
from __future__ import annotations

import argparse

from . import gather, report, workbook


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m cfcleanup setup")
    ap.add_argument("--name", help="batch name (default: <UTC-date>-cf-cleanup-batch)")
    ap.add_argument("--regions", help="space/comma separated region list")
    args = ap.parse_args(argv)

    gather_args = []
    if args.name:
        gather_args += ["--name", args.name]
    if args.regions:
        gather_args += ["--regions", args.regions]

    # gather creates the new batch; report and workbook then default to it (newest).
    rc = gather.main(gather_args)
    if rc:
        return rc
    rc = report.main([])
    if rc:
        return rc
    return workbook.main([])
