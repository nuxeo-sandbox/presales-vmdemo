"""Render a batch's stacks as a readable markdown cleanup report.

Writes <batch>/report.md. With no --batch, uses the most recent batch.

Run as:
    python3 -m cfcleanup report [--batch NAME|DIR]
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime
import os

from . import common as cf


def fmt_date(dt: datetime | None) -> str:
    return dt.date().isoformat() if dt else "?"


def fmt_age(a: float | None) -> str:
    return f"{a:.0f}mo" if a is not None else "?"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m cfcleanup report")
    ap.add_argument("--batch", help="batch name or dir (default: most recent)")
    args = ap.parse_args(argv)

    batch = cf.resolve_batch(args.batch)
    meta = cf.load_meta(batch)
    rows, now = cf.load_rows(batch)
    demo, infra = cf.split_rows(rows)
    account = meta.get("account", "(unknown account)")

    L: list[str] = []
    L.append("# CloudFormation Stack Inventory & Cleanup Report")
    L.append("")
    L.append(
        f"Account **{account}** \u00b7 generated {now.date()} \u00b7 "
        f"**{len(demo)} Nuxeo demo/customer stacks** "
        f"(plus {len(infra)} platform/infra stacks excluded \u2014 see appendix)"
    )
    L.append("")

    L.append("## Summary by region")
    L.append("")
    L.append("| Region | Stacks | Customer | Generic | Stale >12mo | Aging 6-12mo | Recent <6mo |")
    L.append("|---|--:|--:|--:|--:|--:|--:|")
    for reg in cf.sort_regions(r["region"] for r in demo):
        rr = [r for r in demo if r["region"] == reg]
        if not rr:
            continue
        cust = sum(1 for r in rr if r["class"].startswith("customer"))
        gen = sum(1 for r in rr if r["class"].startswith("generic"))
        stale = sum(1 for r in rr if "stale" in r["class"])
        aging = sum(1 for r in rr if "aging" in r["class"])
        recent = sum(1 for r in rr if "recent" in r["class"])
        L.append(f"| {reg} | {len(rr)} | {cust} | {gen} | {stale} | {aging} | {recent} |")
    L.append(f"| **TOTAL** | **{len(demo)}** | | | | | |")
    L.append("")

    for reg in cf.sort_regions(r["region"] for r in demo):
        rr = [r for r in demo if r["region"] == reg]
        if not rr:
            continue
        rr.sort(key=lambda r: (r["age_months"] is None, -(r["age_months"] or 0)))
        L.append(f"## {reg} ({len(rr)} stacks)")
        L.append("")
        L.append("| Stack | Customer | Owner | Studio | Nuxeo | Last activity | Age | Status | Class |")
        L.append("|---|---|---|---|---|---|---|---|---|")
        for r in rr:
            L.append(
                f"| {r['name']} | {r['customer']} | {r['owner']} | {r['studio']} | "
                f"{r['nuxeo']} | {fmt_date(r['last_activity'])} | {fmt_age(r['age_months'])} | "
                f"{r['status']} | {r['class']} |"
            )
        L.append("")

    L.append("## Appendix \u2014 excluded platform & automation stacks")
    L.append("")
    L.append(
        "These are AWS governance and presales-platform automation stacks \u2014 not Nuxeo "
        "demo/customer environments. They are **kept in place** and excluded from the cleanup "
        "tables above."
    )
    L.append("")
    L.append("| Stack | Regions | Count |")
    L.append("|---|---|--:|")
    by: dict[str, list[str]] = defaultdict(list)
    for r in infra:
        by[r["name"]].append(r["region"])

    def key(item: tuple[str, list[str]]) -> tuple[int, str]:
        name = item[0]
        gov = 1 if (name.startswith("StackSet-") or name.startswith("AWS-QuickSetup-")) else 0
        return (gov, name.lower())

    for name, regs in sorted(by.items(), key=key):
        rs = ", ".join(
            f"{reg}\u00d7{regs.count(reg)}" if regs.count(reg) > 1 else reg
            for reg in cf.sort_regions(regs)
        )
        L.append(f"| {name} | {rs} | {len(regs)} |")
    L.append("")

    out = os.path.join(batch, "report.md")
    with open(out, "w") as fh:
        fh.write("\n".join(L))
    print(f"Wrote {out} ({len(demo)} stacks, {len(infra)} infra excluded)")
    c = Counter(r["class"] for r in demo)
    for k in sorted(c):
        print(f"  {k}: {c[k]}")
    return 0
