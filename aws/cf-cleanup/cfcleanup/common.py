"""Shared helpers for the CF cleanup tool: stack parsing, classification, the
infra-exclusion list, and batch directory resolution.

A "batch" is one cleanup cycle. Everything a cycle produces lives under
batches/<name>/ and is generated data that is never committed (see .gitignore):

    stacks/<region>.json   raw describe-stacks dumps (gather)
    batch.json             metadata: gather timestamp + account id (gather)
    report.md              readable inventory (report)
    <date>-cf-cleanup.xlsx review workbook (workbook)
    deletion-log.csv       append-only audit trail (delete)

batches/ lives beside this package, at the tool root.
"""
from __future__ import annotations

import glob
import json
import os
import re
import sys
from datetime import datetime, timezone

PKG_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(PKG_DIR)
BATCHES_DIR = os.path.join(ROOT, "batches")

# Preferred display order. gather auto-discovers the regions to scan, so any
# region not listed here still appears in reports/workbook, ordered after these.
REGIONS_ORDER = ["us-east-1", "us-west-1", "us-west-2", "eu-west-1", "eu-west-2", "ap-northeast-1"]


def region_key(region: str) -> tuple[int, str]:
    """Sort key: preferred regions first (in REGIONS_ORDER), then the rest alphabetically."""
    idx = REGIONS_ORDER.index(region) if region in REGIONS_ORDER else len(REGIONS_ORDER)
    return (idx, region)


def sort_regions(regions) -> list[str]:
    """Unique regions ordered by region_key (preferred order, then alphabetical)."""
    return sorted(set(regions), key=region_key)

# Platform automation & AWS governance stacks. Not Nuxeo demo/customer
# environments: kept in place, excluded from cleanup, listed separately.
INFRA_PATTERNS = [
    re.compile(p)
    for p in (
        r"^StackSet-",
        r"^CDKToolkit$",
        r"^AWS-QuickSetup-",
        r"^MacieServiceRolesMaster$",
        r"^MCIEM$",
        r"^nuxeo-route53-auto-update$",
        r"^nuxeo-scheduled-ec2-start$",
        r"^nuxeo-scheduled-ec2-shutdown$",
        r"^NuxeoDynamicAssetTransformationEdgeLambdaStack$",
        r"^EC2ContainerService-",
    )
]


def is_infra(name: str) -> bool:
    return any(p.search(name) for p in INFRA_PATTERNS)


def params_to_dict(stack: dict) -> dict[str, str]:
    return {p["ParameterKey"]: p.get("ParameterValue", "") for p in stack.get("Parameters", [])}


def tags_to_dict(stack: dict) -> dict[str, str]:
    return {t["Key"]: t.get("Value", "") for t in stack.get("Tags", [])}


def parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def months_ago(dt: datetime | None, now: datetime) -> float | None:
    if dt is None:
        return None
    return (now - dt).days / 30.44


def classify(customer: str, age: float | None) -> str:
    cust = (customer or "").strip().lower()
    if cust in ("generic", "generic demo", "demo", ""):
        base = "generic" if cust.startswith("generic") else "unknown-customer"
    else:
        base = "customer"
    if age is not None and age >= 12:
        return f"{base}/stale(>12mo)"
    if age is not None and age >= 6:
        return f"{base}/aging(6-12mo)"
    return f"{base}/recent(<6mo)"


# ---- batch resolution ------------------------------------------------------
def resolve_batch(arg: str | None = None) -> str:
    """Return an existing batch dir. With no arg, the most recent one."""
    if arg:
        p = arg if (os.path.isabs(arg) or os.path.sep in arg) else os.path.join(BATCHES_DIR, arg)
        if not os.path.isdir(p):
            sys.exit(f"ERROR: batch not found: {p}")
        return os.path.abspath(p)
    subs = [d for d in glob.glob(os.path.join(BATCHES_DIR, "*")) if os.path.isdir(d)]
    if not subs:
        sys.exit("ERROR: no batches found under batches/. Run 'python3 -m cfcleanup gather' first.")
    return os.path.abspath(sorted(subs)[-1])


def new_batch(name: str | None = None) -> str:
    """Create (idempotently) a batch dir; default name is <UTC-date>-cf-cleanup-batch."""
    name = name or datetime.now(timezone.utc).strftime("%Y-%m-%d") + "-cf-cleanup-batch"
    p = os.path.join(BATCHES_DIR, name)
    os.makedirs(os.path.join(p, "stacks"), exist_ok=True)
    return os.path.abspath(p)


def load_meta(batch: str) -> dict:
    f = os.path.join(batch, "batch.json")
    if os.path.exists(f):
        with open(f) as fh:
            return json.load(fh)
    return {}


def batch_now(batch: str) -> datetime:
    """The reference 'now' for age math: the batch's gather time if recorded."""
    g = load_meta(batch).get("gathered_utc")
    return parse_dt(g) if g else datetime.now(timezone.utc)


# ---- workbook location -----------------------------------------------------
def batch_date(batch: str) -> str:
    """The batch's date (YYYY-MM-DD): gather date, else folder-name prefix, else today."""
    g = load_meta(batch).get("gathered_utc")
    if g:
        date = g[:10]
    else:
        m = re.match(r"(\d{4}-\d{2}-\d{2})", os.path.basename(batch.rstrip(os.sep)))
        date = m.group(1) if m else datetime.now(timezone.utc).strftime("%Y-%m-%d")
    return date


def workbook_path(batch: str) -> str:
    """Canonical review-workbook path for a batch: <batch>/<date>-cf-cleanup.xlsx."""
    p = os.path.join(batch, f"{batch_date(batch)}-cf-cleanup.xlsx")
    return p


def find_workbook(batch: str) -> str | None:
    """Locate an existing review workbook, tolerant of a copied-back rename.

    Prefers the canonical dated name; otherwise the single *.xlsx in the batch.
    Excel lock files (~$...) are ignored. Returns None if none is found.
    """
    canonical = workbook_path(batch)
    if os.path.exists(canonical):
        return canonical
    candidates = [
        c for c in sorted(glob.glob(os.path.join(batch, "*.xlsx")))
        if not os.path.basename(c).startswith("~$")
    ]
    if len(candidates) == 1:
        found = candidates[0]
    else:
        dated = [c for c in candidates if c.endswith("-cf-cleanup.xlsx")]
        found = dated[0] if len(dated) == 1 else None
    return found


def resolve_workbook(batch: str, supplied: str | None = None) -> str | None:
    """Resolve the review workbook to read.

    A supplied path (--workbook, or the CF_WORKBOOK env var) wins, so the copy
    shared with the team can be processed in place without copying it back into
    the batch. Falls back to a workbook found inside the batch. Returns None if a
    supplied path is missing, or if nothing is found in the batch.
    """
    supplied = supplied or os.environ.get("CF_WORKBOOK")
    if supplied:
        p = os.path.abspath(os.path.expanduser(supplied))
        if not os.path.isfile(p):
            print(f"ERROR: supplied workbook not found: {p}", file=sys.stderr)
            return None
        return p
    return find_workbook(batch)


# ---- row loading -----------------------------------------------------------
def load_rows(batch: str) -> tuple[list[dict], datetime]:
    """Parse every stacks/<region>.json in a batch into flat row dicts."""
    now = batch_now(batch)
    rows: list[dict] = []
    for path in sorted(glob.glob(os.path.join(batch, "stacks", "*.json"))):
        region = os.path.splitext(os.path.basename(path))[0]
        with open(path) as fh:
            data = json.load(fh)
        for s in data.get("Stacks", []):
            p = params_to_dict(s)
            t = tags_to_dict(s)
            created = parse_dt(s.get("CreationTime"))
            updated = parse_dt(s.get("LastUpdatedTime"))
            last = updated or created
            rows.append(
                {
                    "region": region,
                    "name": s.get("StackName", ""),
                    "status": s.get("StackStatus", ""),
                    "nested": bool(s.get("ParentId")),
                    "customer": p.get("Customer", "") or t.get("Customer", ""),
                    "dns": p.get("DnsName", "") or t.get("dns_entry", ""),
                    "owner": p.get("OnwerName", "") or p.get("OwnerName", ""),
                    "owner_email": p.get("OnwerEmail", "") or p.get("OwnerEmail", ""),
                    "manager": p.get("ManagerName", ""),
                    "studio": p.get("StudioProject", ""),
                    "nuxeo": p.get("NuxeoVersion", ""),
                    "last_activity": last,
                    "age_months": months_ago(last, now),
                }
            )
    return rows, now


def split_rows(rows: list[dict]) -> tuple[list[dict], list[dict]]:
    """Split rows into (demo, infra); nested stacks are dropped from demo."""
    infra = [r for r in rows if is_infra(r["name"])]
    demo = [r for r in rows if not is_infra(r["name"]) and not r["nested"]]
    for r in demo:
        r["class"] = classify(r["customer"], r["age_months"])
    demo.sort(
        key=lambda r: (
            region_key(r["region"]),
            r["age_months"] is None,
            -(r["age_months"] or 0),
        )
    )
    return demo, infra
