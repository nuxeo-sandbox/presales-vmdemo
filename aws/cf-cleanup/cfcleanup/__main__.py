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

import importlib
import sys

from . import common

# Command -> module attribute. Modules are imported lazily so the single-stack
# path (`run`) never pulls in openpyxl, which only the workbook commands need.
COMMANDS = {
    "setup": "setup",
    "gather": "gather",
    "report": "report",
    "workbook": "workbook",
    "delete": "delete",
    "status": "status",
    "run": "run",
}

# Every command that touches AWS. The session is validated once here, up front,
# before dispatching, so an expired or absent login fails fast with a single
# clear message instead of surfacing later as a confusing per-command error
# (e.g. a live region scan reporting a stack "not found"). Only report/workbook
# work purely off on-disk batch data and need no session.
AWS_COMMANDS = {"setup", "gather", "status", "delete", "run"}


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
    module_name = COMMANDS.get(cmd)
    if module_name is None:
        print(f"unknown command: {cmd}\n", file=sys.stderr)
        print(usage(), file=sys.stderr)
        return 2

    if cmd in AWS_COMMANDS and not common.ensure_session():
        return 1

    fn = importlib.import_module(f".{module_name}", __package__).main
    ret = fn(rest)
    return ret


if __name__ == "__main__":
    raise SystemExit(main())
