# AGENTS.md — CloudFormation Demo Stack Cleanup

Operating guide for an agent driving this tooling. It deletes AWS
CloudFormation stacks, so follow the guardrails exactly.

## What this is

A batch-based cleanup: enumerate demo stacks and produce a review workbook for
humans to mark keep/delete. Humans review it out-of-band and delete each approved
stack (emptying its S3 storage first) with `./cfcleanup.sh <stack-id>`, which is
recorded in a local CSV audit trail. The tooling is a Python package (`cfcleanup/`)
driven as `python3 -m cfcleanup <command>`, with a `./cfcleanup.sh` wrapper as the
human entry point. It is human-driven; an agent, if used, just relays stack ids
and the confirmation prompt.

**Nothing here reads the workbook.** The workbook is a human artifact for
deciding what to delete. Deletion acts only on the stack id given - the tooling
does not open, parse, or derive anything from the `.xlsx`. `gather`/`report`/
`workbook` create it; `run`/`delete`/`status` operate on stack ids and the local
deletion log. The same batch dir stays current across sessions.

## Guardrails (do not violate)

1. **Never delete without human confirmation.** Only delete a stack the human
   has explicitly named, and always show the `--dry-run` preview and get an OK
   before the real delete. The human naming the stack id is the approval.
2. **Do not read or derive deletions from the workbook.** It is human-owned.
   Do not open, parse, or derive the delete list from the `.xlsx`; act only on
   the stack ids you are given.
3. **Only delete the exact stack id(s) you are given.** Do not infer, expand, or
   guess additional stacks. Never touch platform/automation/governance stacks
   (`INFRA_PATTERNS` in `cfcleanup/common.py`) or nested `NestedStackNEV-*`
   stacks even if named by mistake - flag them instead.
4. **Preview first.** Run `delete ... --dry-run` and show the result
   before a real deletion.
5. **One account.** Confirm `aws sts get-caller-identity` points at the intended
   presales account before deleting.
6. **One stack at a time.** Fully finish a stack (`delete` → `status` to
   `DELETE_COMPLETE`) and get the human's confirmation before starting the next
   one. Never initiate multiple deletes back-to-back, even when given several ids.
7. **Never `--retain-resources`.** The point of deleting via CloudFormation is to
   fully clean up the resources; retaining orphans them. If a delete fails on a
   stuck resource, clear the blocker so a normal full delete succeeds (see
   Troubleshooting) — do not fall back to retain. (A retain is only ever
   acceptable as an explicit, human-authorized one-off when the resource is
   already verified gone and retaining orphans nothing; do not generalize it.)
8. **Never regenerate a real batch's workbook or report.** The `.xlsx` holds the
   team's hand-entered `Decision` values and hand-tuned formatting, and there is
   no backup. Do not run `gather`/`workbook`/`report` against a live batch to
   "refresh" or test — it overwrites those edits. To test code changes, build a
   disposable throwaway batch and run against `--batch <that>`.

## Preconditions

- AWS CLI v2 authenticated to the presales account.
- Python 3 with `openpyxl`.
- Run every command from the `aws/cf-cleanup/` directory so the `cfcleanup`
  package resolves.
- **Disable the AWS CLI pager first.** In a fresh shell, run `export AWS_PAGER=""`
  once before any `aws` command. Otherwise the CLI opens `less` (the terminal's
  alternate screen) and an automation-driven terminal hangs, with later commands
  piling up behind the stuck pager. Per-command flags like `--no-cli-pager` do not
  recover a terminal that is already stuck — open a new shell and export it there.

## Commands

All commands act on the most recent batch unless `--batch <name|dir>` is given.
No command reads the reviewed workbook.

| Step | Command | Notes |
|---|---|---|
| Setup | `python3 -m cfcleanup setup [--name NAME] [--regions "r1 r2 …"]` | One-shot: `gather` + `report` + `workbook`. Creates a new batch and its review workbook. |
| Enumerate | `python3 -m cfcleanup gather [--name NAME] [--regions "r1 r2 …"]` | Creates a new batch under `batches/`. Regions are auto-discovered (every region enabled for the account); override with `--regions` or `CF_REGIONS`. |
| Report | `python3 -m cfcleanup report [--batch B]` | Writes `report.md`. |
| Workbook | `python3 -m cfcleanup workbook [--batch B]` | Writes `<date>-cf-cleanup.xlsx` for humans to review. |
| Delete (preview) | `python3 -m cfcleanup delete <stack> [region] --dry-run [--batch B]` | Shows bucket + delete actions, changes nothing. Region is optional (resolved from the batch). |
| Delete | `python3 -m cfcleanup delete <stack> [region] [--batch B]` | Empty S3 → initiate delete. Non-blocking. Appends to `deletion-log.csv`. |
| Poll | `python3 -m cfcleanup status [--batch B] [<stack> <region>]` | Exit `3` = still in progress, `0` = done. Re-run to refresh. |
| Run (one-shot) | `python3 -m cfcleanup run <stack> [region] [--batch B]` | Human-driven: inspect → prompt `[y/N]` → empty S3 + delete → block until `DELETE_COMPLETE`. Always prompts for confirmation. |

The normal, human-driven path is the `./cfcleanup.sh` wrapper at the tool root:
`./cfcleanup.sh <stack-id>` sets `AWS_PAGER=""` and calls `run`. A bare stack id
routes to `run`; `gather`/`report`/`workbook`/`delete`/`status`/`run` still work
by name. `delete` and `status` are non-blocking building blocks that `run`
orchestrates.

The `cfcleanup/s3.py` module is a helper used by the `delete` command; it is not
invoked directly.

## Typical run

One-time setup of a batch (rare — only when starting a brand-new cleanup):

1. `python3 -m cfcleanup setup` (or `./cfcleanup.sh setup`) — gather + report + workbook.
2. Humans review the workbook and decide what to delete.

Ongoing sessions (the common case):

The human runs `./cfcleanup.sh <stack-id>` for each stack, which inspects,
prompts, deletes, and monitors on its own.

If an agent is asked to do it anyway:

1. Confirm the account (`aws sts get-caller-identity`).
2. The human gives you a stack id. The region is optional - it is resolved from
   the batch's gather data (with a live region scan as fallback); only ask for
   it if resolution reports the name as ambiguous or not found.
3. Delete that **one** stack with `python3 -m cfcleanup run <stack>`. It prints
   the inspection, waits at the `[y/N]` prompt (relay it to the human - never
   auto-answer), then deletes and blocks until `DELETE_COMPLETE`. Do not use the
   `--dry-run`/`delete`/`status` primitives separately unless `run` can't be used.
4. Wait for the next stack id. Do not work ahead or infer other stacks.

## Decision values (human-facing)

The workbook's `Decision` dropdown is `Keep - active engagement`,
`Keep - generic demo`, `Delete`, `Investigate`. Humans use it to decide, then
tell the agent which stacks to delete.

## The workbook is human-owned

The reviewed workbook (`<date>-cf-cleanup.xlsx`) is created by `workbook`, then
shared with the team and reviewed out-of-band. Humans decide from it and give the
agent the stack ids to delete. The machine-written audit trail is the batch's
`deletion-log.csv`, appended by `delete` and `status`.

## Troubleshooting

**`DELETE_FAILED` on an `AWS::EC2::SecurityGroup`** with a reason like *"No
default VPC for this user. GroupName is only supported for EC2-Classic and
default VPC."* Old NEV/Nuxeo templates identify the SG by `GroupName`, and
`DeleteSecurityGroup`-by-name is an `InvalidRequest` in this account (no default
VPC). First check whether the SG even still exists:
`aws ec2 describe-security-groups --region <r> --query
'SecurityGroups[].[GroupId,GroupName,VpcId]' --output text | grep -i <stack>`.
If the instance that used it is already `DELETE_COMPLETE`, the SG is usually
already gone too. If it still exists, delete it by its `sg-…` id and re-run
`delete-stack`. If it is already gone, you cannot delete it to unblock and a plain
retry re-hits the same by-name error — surface this to the human rather than
silently retaining (see guardrail 8).

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
