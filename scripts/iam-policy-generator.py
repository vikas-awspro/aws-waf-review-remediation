#!/usr/bin/env python3
"""
SEC-01 helper — generates a least-privilege IAM policy from observed CloudTrail
events for a target IAM role, over a configurable observation window.

Usage:
    python3 iam-policy-generator.py \
        --role-name aras-app-tier-prod \
        --start-time "2026-04-01T00:00:00Z" \
        --end-time   "2026-05-01T00:00:00Z" \
        --output     policy.json

The output is intentionally a *draft* — the Cloud Architect must review every
statement and tighten resource ARNs from `*` to specific buckets / RDS
resource IDs / Secret ARNs before applying.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

import boto3


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--role-name", required=True,
                   help="IAM role name to observe (the one currently over-privileged)")
    p.add_argument("--start-time", required=True,
                   help="ISO 8601 — earliest CloudTrail event to consider")
    p.add_argument("--end-time", required=True,
                   help="ISO 8601 — latest CloudTrail event to consider")
    p.add_argument("--output", default="generated-policy.json",
                   help="Destination JSON file (default: generated-policy.json)")
    p.add_argument("--region", default="eu-west-1")
    return p.parse_args()


def fetch_role_arn(iam, name: str) -> str:
    return iam.get_role(RoleName=name)["Role"]["Arn"]


def fetch_events(cloudtrail, role_arn: str, start: datetime, end: datetime) -> list[dict]:
    """LookupEvents is rate-limited and capped at 50 events/page — paginate."""
    events: list[dict] = []
    paginator = cloudtrail.get_paginator("lookup_events")
    for page in paginator.paginate(
        LookupAttributes=[{"AttributeKey": "Username", "AttributeValue": role_arn}],
        StartTime=start, EndTime=end,
    ):
        events.extend(page["Events"])
    return events


def derive_actions_and_resources(events: list[dict]) -> dict[str, set[str]]:
    """Returns {action -> set(resource_arn)} from CloudTrail event records."""
    actions: dict[str, set[str]] = defaultdict(set)
    for event in events:
        record = json.loads(event["CloudTrailEvent"])
        svc = record.get("eventSource", "").split(".")[0]   # ec2.amazonaws.com → ec2
        action = f"{svc}:{record.get('eventName', 'Unknown')}"
        # Resources are best-effort — CloudTrail doesn't always populate.
        for resource in record.get("resources", []) or []:
            arn = resource.get("ARN")
            if arn:
                actions[action].add(arn)
        if not record.get("resources"):
            actions[action].add("*")
    return actions


def build_policy(actions_by_resource: dict[str, set[str]]) -> dict:
    statements: list[dict] = []
    # Group actions by resource set so we don't emit one statement per action.
    by_resource: dict[tuple[str, ...], list[str]] = defaultdict(list)
    for action, resources in actions_by_resource.items():
        by_resource[tuple(sorted(resources))].append(action)

    for idx, (resources, actions) in enumerate(by_resource.items(), start=1):
        statements.append({
            "Sid": f"ObservedActions{idx}",
            "Effect": "Allow",
            "Action": sorted(actions),
            "Resource": list(resources),
        })

    return {"Version": "2012-10-17", "Statement": statements}


def main() -> int:
    args = parse_args()

    iam = boto3.client("iam")
    cloudtrail = boto3.client("cloudtrail", region_name=args.region)

    role_arn = fetch_role_arn(iam, args.role_name)
    start = datetime.fromisoformat(args.start_time.replace("Z", "+00:00")).astimezone(timezone.utc)
    end   = datetime.fromisoformat(args.end_time.replace("Z", "+00:00")).astimezone(timezone.utc)

    print(f"[+] Fetching CloudTrail events for {role_arn} between {start} and {end}")
    events = fetch_events(cloudtrail, role_arn, start, end)
    print(f"    {len(events)} events observed")

    if not events:
        print("[!] No events. Either the role is genuinely unused (consider deletion) "
              "or the observation window is too short / CloudTrail isn't capturing this principal.")
        return 1

    actions = derive_actions_and_resources(events)
    print(f"[+] Distinct actions: {len(actions)}")

    policy = build_policy(actions)
    Path(args.output).write_text(json.dumps(policy, indent=2))
    print(f"[+] Draft policy written to {args.output}")
    print("[!] REVIEW before applying:")
    print("    - Replace any `*` Resource with specific ARNs (S3 bucket, RDS resource ID, secret ARN).")
    print("    - Remove read-only enumeration calls that aren't needed in production")
    print("      (Describe*, List* — usually not required by the application).")
    print("    - Add ServiceName / ViaService conditions where possible (e.g. KMS).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
