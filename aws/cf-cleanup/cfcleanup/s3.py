"""Empty an S3 location: all current objects, non-current versions, and delete
markers under a bucket (optionally restricted to a key prefix / "folder").

Used by the delete command so the tricky version-purge logic lives in Python
rather than fragile shell. Shells out to the AWS CLI (no boto3 dependency).

Exits 0 on success (including when nothing needed deleting or the bucket is
missing), non-zero only on an actual error.
"""
from __future__ import annotations

import json
import subprocess


def aws_json(args: list[str]) -> dict:
    """Run an aws CLI command expected to return JSON; return {} on empty."""
    out = subprocess.run(
        ["aws", *args, "--output", "json"],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or f"aws {' '.join(args)} failed")
    txt = out.stdout.strip()
    return json.loads(txt) if txt else {}


def bucket_exists(bucket: str) -> bool:
    """True if the bucket exists and is accessible.

    A genuine 404 (bucket gone) returns False; an auth/permission failure such as
    an expired token is raised, never silently treated as 'already gone' - so a
    stack delete can't skip bucket emptying just because credentials lapsed.
    """
    out = subprocess.run(
        ["aws", "s3api", "head-bucket", "--bucket", bucket],
        capture_output=True,
        text=True,
    )
    if out.returncode == 0:
        return True
    low = (out.stderr or "").lower()
    if "404" in low or "not found" in low or "nosuchbucket" in low:
        return False
    raise RuntimeError(
        (out.stderr or "").strip() or f"head-bucket {bucket} failed (rc={out.returncode})"
    )


def collect_versions(bucket: str, prefix: str) -> list[dict]:
    """All versions + delete markers under prefix, paginated."""
    items: list[dict] = []
    token: dict[str, str] = {}
    while True:
        args = ["s3api", "list-object-versions", "--bucket", bucket]
        if prefix:
            args += ["--prefix", prefix]
        for k, v in token.items():
            args += [k, v]
        data = aws_json(args)
        for group in ("Versions", "DeleteMarkers"):
            for o in data.get(group) or []:
                items.append({"Key": o["Key"], "VersionId": o["VersionId"]})
        if data.get("IsTruncated"):
            token = {}
            if data.get("NextKeyMarker"):
                token["--key-marker"] = data["NextKeyMarker"]
            if data.get("NextVersionIdMarker"):
                token["--version-id-marker"] = data["NextVersionIdMarker"]
            if not token:
                break
        else:
            break
    return items


def delete_batch(bucket: str, batch: list[dict]) -> None:
    payload = json.dumps({"Objects": batch, "Quiet": True})
    out = subprocess.run(
        ["aws", "s3api", "delete-objects", "--bucket", bucket, "--delete", payload],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "delete-objects failed")


def empty_location(bucket: str, prefix: str = "", dry_run: bool = False) -> int:
    """Empty a bucket (or one prefix within it); return 0 on success."""
    loc = f"s3://{bucket}/{prefix}"
    if not bucket_exists(bucket):
        print(f"Bucket {bucket} not found (already gone?); nothing to empty.")
        return 0

    items = collect_versions(bucket, prefix)
    if not items:
        print(f"{loc}: already empty (0 objects/versions).")
        return 0

    print(f"{loc}: {len(items)} object version(s)/delete-marker(s) to remove.")
    if dry_run:
        print(f"DRY-RUN> would delete {len(items)} item(s) from {loc}")
        return 0

    for i in range(0, len(items), 1000):
        delete_batch(bucket, items[i : i + 1000])
    print(f"Emptied {loc} ({len(items)} item(s) deleted).")
    return 0
