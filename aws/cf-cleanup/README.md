# CloudFormation Demo Stack Cleanup

Inventory the presales CloudFormation demo stacks, collect keep/delete decisions
in an Excel workbook, and delete stacks (emptying their S3 storage first) by the
stack ids a human hands off from that review, recording each deletion.

A few things make this fiddly:

* CloudFormation requires S3 buckets to be empty before a stack can be deleted.
* Some stacks share an S3 bucket, so only the stack's own folder can be emptied
  without disturbing objects other stacks still need.
* Not all stacks are demo stacks. Platform and governance stacks must be left
  alone.
* Stacks are spread across many regions.

## Requirements

* AWS CLI v2, authenticated to the presales account (hint: `aws sso login`)
* Python 3 with `openpyxl`.
* Run every command from the `aws/cf-cleanup/` directory so the `cfcleanup`
  package resolves.

## Usage

### Create a Batch

```
./cfcleanup.sh setup
```

Inspect `batches/<yyyy-mm-dd>-cf-cleanup-batch/<date>-cf-cleanup.xlsx`. It contains columns to track the decision (keep/delete), whether the stack was deleted, and notes.

### Delete a Stack

```
./cfcleanup.sh <stack-id>
```

That one command interrogates the stack, reports what will be emptied and
deleted, prompts `Delete <stack> (<region>)? [y/N]`, and - on `y` - empties S3,
deletes the stack, and blocks until `DELETE_COMPLETE`. The region is resolved
automatically from the batch.

## Batch contents

A batch is one cleanup cycle. This is not an ongoing rolling list. Run it once
and process the whole batch; if you don't finish, just start a fresh batch when
you come back in six months. Its output lives under a dated root folder
`batches/<yyyy-mm-dd>-cf-cleanup-batch/`, which is gitignored:

```
stacks/<region>.json   raw describe-stacks output
batch.json             gather timestamp + account id
report.md              readable inventory
<date>-cf-cleanup.xlsx  review workbook
deletion-log.csv       audit trail
```

## Workbook columns

* `Decision`, `Deleted?`, and `Notes` are the ones to focus on.
* The workbook is a human review artifact: people decide from it, then run
  `./cfcleanup.sh <stack-id>` per stack. The machine-written record of deletions
  is `deletion-log.csv`.

## Bucket handling

The `delete` command reads each stack's `UseS3Bucket` parameter and empties the
right location before deleting:

* `Create`: dedicated bucket `<stack>-bucket` (emptied entirely)
* `Shared`: shared bucket `<region>-demo-bucket`, only the `<stack>/` folder
* `None`: no bucket

## Excluded stacks

Platform, automation, and AWS governance stacks (StackSets, CDKToolkit, Macie,
route53/scheduler automation) match `INFRA_PATTERNS` in `cfcleanup/common.py`
and appear only on the workbook's "Excluded infra" sheet. Nested NEV stacks (those with a `NestedStackNEV-` prefix) are also omitted.

# About Hyland Nuxeo

Hyland Nuxeo is an open source Content Services platform, written in Java. Data
can be stored in both SQL & NoSQL databases. The development of the Nuxeo
Platform is mostly done by Hyland employees with an open development model. The
source code, documentation, roadmap, issue tracker, testing, benchmarks are all
public.

Organizations across industries such as financial services, insurance,
manufacturing, healthcare, and government use Nuxeo to build a wide range of
information management solutions on a single platform. Its schema-flexible
metadata and content models let the same platform be adapted to different
industries and their requirements.

More information is available at [https://www.hyland.com/products/nuxeo-platform](https://www.hyland.com/products/nuxeo-platform).

# About Hyland

[Hyland](https://www.hyland.com) is a leading content services provider that
enables thousands of organizations to deliver better experiences to the people
they serve. Learn more at [hyland.com](https://www.hyland.com).
