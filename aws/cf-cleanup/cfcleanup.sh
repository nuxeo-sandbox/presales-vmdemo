#!/usr/bin/env bash
# Human-driven entry point for the CF cleanup tool.
#
# The common case is a one-shot delete of a single stack:
#     ./cfcleanup.sh <stack-id>
# which interrogates the stack, reports what will be emptied/deleted, prompts
# for confirmation, deletes, then monitors until DELETE_COMPLETE.
#
# Named subcommands:
#     ./cfcleanup.sh setup | gather | report | workbook | delete | status | run
set -euo pipefail

# CloudFormation/S3 calls must not open the pager (it hangs a non-tty).
export AWS_PAGER=""

# Make the tool's usage/help refer to this wrapper rather than the raw module.
export CFCLEANUP_PROG="./cfcleanup.sh"

cd "$(dirname "$0")"

# Prefer the batch-mode venv (see README) so callers never invoke python directly.
PY="python3"
[[ -x .venv/bin/python3 ]] && PY=".venv/bin/python3"

case "${1:-}" in
  setup|gather|report|workbook|delete|status|run|-h|--help|"")
    exec "$PY" -m cfcleanup "$@" ;;
  *)
    # Anything else is treated as a stack id for the one-shot `run` flow.
    exec "$PY" -m cfcleanup run "$@" ;;
esac
