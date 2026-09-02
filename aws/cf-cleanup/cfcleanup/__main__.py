"""Command dispatcher for the cleanup tool.

Usage:
    python3 -m cfcleanup <command> [args]

Commands:
    setup      one-shot batch setup: gather + report + workbook
    gather     enumerate stacks across regions into a new batch
    report     write report.md for a batch
    workbook   write the <date>-cf-cleanup.xlsx review workbook
    delete     empty S3 + initiate a stack delete (by stack id)
    status     poll in-flight deletions
    run        one-shot human-driven delete: inspect -> confirm -> delete -> monitor
"""
from __future__ import annotations

import sys

from . import delete, gather, report, run, setup, status, workbook

COMMANDS = {
    "setup": setup.main,
    "gather": gather.main,
    "report": report.main,
    "workbook": workbook.main,
    "delete": delete.main,
    "status": status.main,
    "run": run.main,
}


def usage() -> str:
    lines = ["usage: python3 -m cfcleanup <command> [args]", "", "commands:"]
    lines += [f"  {name}" for name in COMMANDS]
    lines += ["", "Run 'python3 -m cfcleanup <command> --help' for command options."]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0] in ("-h", "--help"):
        print(usage())
        return 0 if argv else 2

    cmd, rest = argv[0], argv[1:]
    fn = COMMANDS.get(cmd)
    if fn is None:
        print(f"unknown command: {cmd}\n", file=sys.stderr)
        print(usage(), file=sys.stderr)
        return 2

    ret = fn(rest)
    return ret


if __name__ == "__main__":
    raise SystemExit(main())
