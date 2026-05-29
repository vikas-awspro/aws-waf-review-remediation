#!/usr/bin/env python3
"""Schema-validate findings/findings.yaml. Run by CI on every PR."""
from __future__ import annotations

import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]

SCHEMA = {
    "type": "object",
    "required": ["id", "pillar", "title", "risk", "waf_reference", "status", "before", "after"],
    "properties": {
        "id":            {"type": "string", "pattern": r"^(SEC|REL|PERF|COST)-\d{2}$"},
        "pillar":        {"enum": ["security", "reliability", "performance", "cost"]},
        "title":         {"type": "string"},
        "risk":          {"enum": ["HIGH", "MEDIUM", "LOW"]},
        "waf_reference": {"type": "string"},
        "status":        {"enum": ["remediated", "in_progress", "accepted_with_residual"]},
        "fixed_by": {
            "type": "object",
            "properties": {
                "module":  {"type": "string"},
                "runbook": {"type": "string"},
                "script":  {"type": "string"},
            },
        },
        "before":          {"type": "string"},
        "after":           {"type": "string"},
        "effort_days":     {"type": "number"},
        "risk_reduction":  {"type": "string"},
        "saving_usd_month": {"type": "number"},
        "notes":           {"type": "string"},
    },
    "additionalProperties": False,
}

EXPECTED_PILLAR_COUNTS = {"security": 7, "reliability": 7, "performance": 7, "cost": 6}


def main() -> int:
    data = yaml.safe_load((ROOT / "findings" / "findings.yaml").read_text())["findings"]
    validator = Draft202012Validator(SCHEMA)
    errors = 0
    ids = []
    pillar_counts = {p: 0 for p in EXPECTED_PILLAR_COUNTS}

    for f in data:
        ids.append(f["id"])
        pillar_counts[f["pillar"]] = pillar_counts.get(f["pillar"], 0) + 1
        for err in validator.iter_errors(f):
            print(f"  {f.get('id', '?')}: {err.message}")
            errors += 1

    # Uniqueness
    if len(ids) != len(set(ids)):
        print(f"  duplicate finding IDs: {[x for x in ids if ids.count(x) > 1]}")
        errors += 1

    # Pillar totals match the WAF Review Report
    if pillar_counts != EXPECTED_PILLAR_COUNTS:
        print(f"  pillar totals drifted from report: expected {EXPECTED_PILLAR_COUNTS}, got {pillar_counts}")
        errors += 1

    if errors == 0:
        print(f"✓ validated {len(data)} findings · pillar totals {pillar_counts}")
    return 0 if errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
