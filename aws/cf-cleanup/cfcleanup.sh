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

cd "$(dirname "$0")"

case "${1:-}" in
  setup|gather|report|workbook|delete|status|run|-h|--help|"")
    exec python3 -m cfcleanup "$@" ;;
  *)
    # Anything else is treated as a stack id for the one-shot `run` flow.
    exec python3 -m cfcleanup run "$@" ;;
esac
