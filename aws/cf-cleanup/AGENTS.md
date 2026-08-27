# AGENTS.md — CloudFormation Demo Stack Cleanup

Operating guide for an agent driving this tooling. It deletes AWS
CloudFormation stacks, so follow the guardrails exactly.

## What this is

A batch-based cleanup: enumerate demo stacks, produce a review workbook, let
humans mark keep/delete, then delete the approved stacks (emptying their S3
storage first) and record each deletion. The tooling is a Python package
(`cfcleanup/`) driven as `python3 -m cfcleanup <command>`; each command is one
step, run in order. There are no shell scripts, and no human runs this by hand.

## Guardrails (do not violate)

1. **Never delete without human confirmation.** Only delete a stack whose
   `Decision` is `Delete` in the workbook. The `delete` command enforces this and
   aborts otherwise — do not work around it.
2. **Never set or edit the `Decision` column.** It is human-owned. The agent
   reads it; it does not write it.
3. **Never target excluded stacks.** Platform/automation/governance stacks
   (`INFRA_PATTERNS` in `cfcleanup/common.py`) and nested `NestedStackNEV-*`
   stacks are not cleanup targets. They never appear in the cleanup list.
4. **Preview first.** Run `delete ... --dry-run` and show the result
   before a real deletion.
5. **One account.** Confirm `aws sts get-caller-identity` points at the intended
   presales account before gathering or deleting.
6. **Always read the workbook fresh from disk.** It is shared with the team
   out-of-band and edited elsewhere (see Workbook handoff). Ask the human for the
   reviewed workbook path and pass it with `--workbook`; re-read it right
   before every decision check; never act on `Decision`/`Deleted?` values
   remembered from earlier in the session.

## Preconditions

- AWS CLI v2 authenticated to the presales account.
- Python 3 with `openpyxl`.
- Run every command from the `aws/cf-cleanup/` directory so the `cfcleanup`
  package resolves.

## Commands

All commands act on the most recent batch unless `--batch <name|dir>` is given.
Commands that read decisions (`check`, `delete`, `log`) read the reviewed
workbook supplied with `--workbook <path>` (or the `CF_WORKBOOK` env var), and
fall back to a workbook inside the batch when neither is given.

| Step | Command | Notes |
|---|---|---|
| Enumerate | `python3 -m cfcleanup gather [--name NAME] [--regions "r1 r2 …"]` | Creates a new batch under `batches/`. Regions are auto-discovered (every region enabled for the account); override with `--regions` or `CF_REGIONS`. |
| Report | `python3 -m cfcleanup report [--batch B]` | Writes `report.md`. |
| Workbook | `python3 -m cfcleanup workbook [--batch B]` | Writes `<date>-cf-cleanup.xlsx`. |
| Check decision | `python3 -m cfcleanup check <stack> [--batch B] [--workbook PATH]` | Gate only. Exit `0` = Delete, `2` = other/blank, `1` = not found. |
| Delete (preview) | `python3 -m cfcleanup delete <stack> <region> --dry-run [--batch B] [--workbook PATH]` | Runs the gate, shows bucket + delete actions, changes nothing. |
| Delete | `python3 -m cfcleanup delete <stack> <region> [--batch B] [--workbook PATH]` | Gate → empty S3 → initiate delete. Non-blocking. |
| Poll | `python3 -m cfcleanup status [--batch B] [<stack> <region>]` | Exit `3` = still in progress, `0` = done. Re-run to refresh. |
| Record | `python3 -m cfcleanup log <stack> [--batch B] [--date YYYY-MM-DD] [--workbook PATH]` | Sets `Deleted? = Yes` and appends `Deleted <date>` to `Notes`. |

The `cfcleanup/s3.py` module is a helper used by the `delete` command; it is not
invoked directly.

## Typical run

1. `python3 -m cfcleanup gather` — new batch.
2. `python3 -m cfcleanup report` and `python3 -m cfcleanup workbook`.
3. Wait for humans to fill `Decision` in the workbook.
4. For each stack marked `Delete`:
   - `python3 -m cfcleanup delete <stack> <region> --dry-run` → show the preview
     and get confirmation.
   - `python3 -m cfcleanup delete <stack> <region>`.
   - `python3 -m cfcleanup status` until the stack is `DELETE_COMPLETE`.
   - `python3 -m cfcleanup log <stack>`.

## Decision values

The `Decision` dropdown is `Keep - active engagement`, `Keep - generic demo`,
`Delete`, `Investigate`. Only `Delete` is eligible; treat everything else
(including blank) as keep.

## Workbook handoff

The reviewed workbook (`<date>-cf-cleanup.xlsx`) lives outside the batch, shared
with the team and edited there. Ask the human for its path and pass it to the
decision-reading commands with `--workbook PATH` (or set `CF_WORKBOOK` once for
the session). `check`, `delete`, and `log` accept it; without it they fall back
to a workbook inside the batch.

Its contents can change between steps, so:

- Ask the human for the workbook path at the start of a deletion cycle. Do not
  assume a fixed location.
- Always re-read it from disk immediately before use. Never cache `Decision`,
  `Deleted?`, or `Notes` in the agent's own context and reason from that.
- Go through the commands (`check`, `delete`, `log`); each opens the file fresh
  on every call. Do not substitute values seen in an earlier view.
- Don't hold the file open longer than a single command; an external editor may
  have it open at the same time.

## Batch layout

```
batches/<yyyy-mm-dd-cf-cleanup-batch>/
  stacks/<region>.json   raw describe-stacks output
  batch.json             gather timestamp + account id
  report.md
  <date>-cf-cleanup.xlsx  written here by `workbook`, then moved out for review
  deletion-log.csv       audit trail of initiated/complete deletions
```

`batches/` is gitignored. Never commit its contents or paste them outside the
working session.
