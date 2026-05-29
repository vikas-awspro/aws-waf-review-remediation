#!/usr/bin/env python3
"""
COST-06 helper — audits EBS snapshots in the account, classifies each as
keep / delete-candidate, and (with --apply) deletes the candidates.

Classification rules (in priority order):
  1. Tag `RetainForever=true` → KEEP
  2. Tag `Backup=manual` AND age > 30 days → DELETE
  3. Source volume no longer exists AND age > 7 days → DELETE
  4. Snapshot is part of an active AMI → KEEP
  5. Anything else → KEEP (reviewer decides)

Always dry-run by default. The `--apply` flag is required to actually delete.
"""
from __future__ import annotations

import argparse
import sys
from datetime import datetime, timedelta, timezone

import boto3


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--region", default="eu-west-1")
    p.add_argument("--apply", action="store_true",
                   help="Actually delete the snapshots flagged for deletion")
    p.add_argument("--max-age-days", type=int, default=30,
                   help="Manual snapshots older than this are deletion candidates")
    p.add_argument("--owner-id", default="self")
    return p.parse_args()


def fetch_snapshots(ec2, owner: str) -> list[dict]:
    paginator = ec2.get_paginator("describe_snapshots")
    snaps: list[dict] = []
    for page in paginator.paginate(OwnerIds=[owner]):
        snaps.extend(page["Snapshots"])
    return snaps


def fetch_active_ami_snapshots(ec2) -> set[str]:
    """Return the set of snapshot IDs referenced by any AMI."""
    snap_ids: set[str] = set()
    for image in ec2.describe_images(Owners=["self"])["Images"]:
        for bdm in image.get("BlockDeviceMappings", []):
            ebs = bdm.get("Ebs")
            if ebs and ebs.get("SnapshotId"):
                snap_ids.add(ebs["SnapshotId"])
    return snap_ids


def fetch_existing_volume_ids(ec2) -> set[str]:
    paginator = ec2.get_paginator("describe_volumes")
    vol_ids: set[str] = set()
    for page in paginator.paginate():
        for v in page["Volumes"]:
            vol_ids.add(v["VolumeId"])
    return vol_ids


def classify(snap: dict, ami_snaps: set[str], existing_vols: set[str],
             max_age_days: int) -> tuple[str, str]:
    tags = {t["Key"]: t["Value"] for t in snap.get("Tags", [])}
    age = datetime.now(timezone.utc) - snap["StartTime"]

    if tags.get("RetainForever", "").lower() == "true":
        return "KEEP", "RetainForever tag"
    if snap["SnapshotId"] in ami_snaps:
        return "KEEP", "referenced by active AMI"
    if tags.get("Backup") == "manual" and age > timedelta(days=max_age_days):
        return "DELETE", f"manual backup, age {age.days}d > {max_age_days}d"
    if snap["VolumeId"] not in existing_vols and age > timedelta(days=7):
        return "DELETE", f"source volume {snap['VolumeId']} no longer exists"
    return "KEEP", "uncategorised — review manually"


def main() -> int:
    args = parse_args()
    ec2 = boto3.client("ec2", region_name=args.region)

    snaps = fetch_snapshots(ec2, args.owner_id)
    print(f"[+] Found {len(snaps)} snapshot(s)")

    ami_snaps = fetch_active_ami_snapshots(ec2)
    existing_vols = fetch_existing_volume_ids(ec2)

    total_size_gb = sum(s["VolumeSize"] for s in snaps)
    delete_size_gb = 0
    delete_ids: list[str] = []

    print(f"\n{'ID':<25} {'Age(d)':>6} {'Size(GB)':>9}  Decision   Reason")
    print("-" * 100)
    for snap in sorted(snaps, key=lambda s: s["StartTime"]):
        decision, reason = classify(snap, ami_snaps, existing_vols, args.max_age_days)
        age_days = (datetime.now(timezone.utc) - snap["StartTime"]).days
        print(f"{snap['SnapshotId']:<25} {age_days:>6} {snap['VolumeSize']:>9}  {decision:<9}  {reason}")
        if decision == "DELETE":
            delete_ids.append(snap["SnapshotId"])
            delete_size_gb += snap["VolumeSize"]

    print("-" * 100)
    print(f"Total snapshots:     {len(snaps)} ({total_size_gb} GB)")
    print(f"Deletion candidates: {len(delete_ids)} ({delete_size_gb} GB)")
    print(f"Estimated saving:    ${delete_size_gb * 0.05:.2f}/month")

    if not args.apply:
        print("\nDry run. Re-run with --apply to actually delete.")
        return 0

    print("\n[!] APPLYING — deleting flagged snapshots ...")
    for sid in delete_ids:
        try:
            ec2.delete_snapshot(SnapshotId=sid)
            print(f"    deleted {sid}")
        except Exception as exc:  # noqa: BLE001
            print(f"    FAILED {sid}: {exc}")
    print("[+] Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
