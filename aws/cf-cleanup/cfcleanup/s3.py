"""Empty an S3 location: all current objects, non-current versions, and delete
markers under a bucket (optionally restricted to a key prefix / "folder").

Shells out to the AWS CLI.
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

    A 404 (bucket gone) returns False; an auth/permission failure is raised.
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


def delete_all(bucket: str, items: list[dict], progress=None) -> None:
    """Delete every given object version/marker from the bucket, in batches.

    If given, progress(done, total) is called before each batch of 1000, where
    done is the running total that batch will bring the deletion to.
    """
    total = len(items)
    for i in range(0, total, 1000):
        chunk = items[i : i + 1000]
        if progress:
            progress(min(i + 1000, total), total)
        delete_batch(bucket, chunk)
