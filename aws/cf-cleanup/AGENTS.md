# AGENTS.md — CloudFormation Demo Stack Cleanup

Operating guide for an agent driving this tooling. It deletes AWS
CloudFormation stacks, so follow the guardrails exactly.

## What this is

A batch-based cleanup: enumerate demo stacks, produce a review workbook, let
humans mark keep/delete, then delete the approved stacks (emptying their S3
storage first) and record each deletion. The tooling is a Python package
(`cfcleanup/`) driven as `python3 -m cfcleanup <command>`; each command is one
step, run in order. There are no shell scripts, and no human runs this by hand.

**Review is incremental, not one-shot.** The human does not review the whole
workbook in a single sitting. They mark a few rows `Delete` whenever they get to
it and check in over time; each session you process only the rows that are newly
`Delete` and not yet `Deleted? = Yes`, then stop. The set of `Delete` rows grows
between sessions. "Continue the batch" means re-read the current workbook fresh
and pick up the newly-approved rows — it does **not** mean `gather` a new batch.
The same batch dir stays current across all these sessions until the whole sheet
is reviewed.

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
7. **One stack at a time.** Fully finish a stack (`delete` → `status` to
   `DELETE_COMPLETE` → `log`) and get the human's confirmation before starting the
   next one. Never initiate multiple deletes back-to-back, even when several rows
   are marked `Delete`. Skip any row already `Deleted? = Yes`; never re-delete.
8. **Never `--retain-resources`.** The point of deleting via CloudFormation is to
   fully clean up the resources; retaining orphans them. If a delete fails on a
   stuck resource, clear the blocker so a normal full delete succeeds (see
   Troubleshooting) — do not fall back to retain. (A retain is only ever
   acceptable as an explicit, human-authorized one-off when the resource is
   already verified gone and retaining orphans nothing; do not generalize it.)
9. **Never regenerate a real batch's workbook or report.** The `.xlsx` holds the
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

One-time setup of a batch (rare — only when starting a brand-new cleanup):

1. `python3 -m cfcleanup gather` — new batch.
2. `python3 -m cfcleanup report` and `python3 -m cfcleanup workbook`.
3. Humans fill `Decision` in the workbook over time.

Ongoing incremental sessions (the common case):

1. Confirm the account (`aws sts get-caller-identity`) and the reviewed workbook
   path; re-read the workbook fresh.
2. Find rows where `Decision = Delete` and `Deleted?` is blank.
3. For **one** such stack at a time:
   - `python3 -m cfcleanup delete <stack> <region> --dry-run` → show the preview
     and get confirmation.
   - `python3 -m cfcleanup delete <stack> <region>`.
   - `python3 -m cfcleanup status` until the stack is `DELETE_COMPLETE`.
   - `python3 -m cfcleanup log <stack>`.
   - Confirm with the human before moving to the next stack.

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
