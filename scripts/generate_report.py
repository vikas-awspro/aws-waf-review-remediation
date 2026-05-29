#!/usr/bin/env python3
"""
Renders docs/remediation-summary.md from findings/findings.yaml.

The summary fulfils the customer's "update report with remediation summary"
ask: it's the appendix to the original PLM_WAF_Review_Report.docx, listing
each finding's current state, the artefact that fixed it, and the savings /
risk-reduction delivered.

Run on every CI build so the markdown stays in sync with the YAML.
"""
from __future__ import annotations

import datetime as dt
from collections import Counter, defaultdict
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def fmt_artefact(fix: dict) -> str:
    """Render the `fixed_by` block as a bulleted list of links."""
    if not fix:
        return "—"
    bits = []
    if "module" in fix:
        bits.append(f"[`{fix['module']}`](../{fix['module']}/)")
    if "runbook" in fix:
        bits.append(f"[`{fix['runbook']}`](../{fix['runbook']})")
    if "script" in fix:
        bits.append(f"[`{fix['script']}`](../{fix['script']})")
    return "<br>".join(bits)


def pillar_score(findings: list[dict]) -> dict[str, tuple[int, int, int]]:
    """Mirror the report's score table: pre, post, delta per pillar."""
    # Values pulled from the original report's "Projected Pillar Scores Post-Remediation" table.
    return {
        "security":    (52, 81, 29),
        "reliability": (58, 84, 26),
        "performance": (61, 87, 26),
        "cost":        (44, 78, 34),
    }


def main() -> None:
    findings = yaml.safe_load((ROOT / "findings" / "findings.yaml").read_text())["findings"]

    by_status   = Counter(f["status"] for f in findings)
    by_pillar   = Counter(f["pillar"] for f in findings)
    by_risk     = Counter(f["risk"] for f in findings)
    by_pillar_risk: dict[tuple[str, str], int] = defaultdict(int)
    for f in findings:
        by_pillar_risk[(f["pillar"], f["risk"])] += 1

    total_savings = sum(
        f.get("saving_usd_month", 0) for f in findings
        if isinstance(f.get("saving_usd_month"), (int, float))
    )

    today = dt.date.today().isoformat()
    pillar_human = {"security": "Security", "reliability": "Reliability",
                    "performance": "Performance Efficiency", "cost": "Cost Optimisation"}

    md = []
    md.append("# Remediation summary — appendix to the WAF Review Report")
    md.append("")
    md.append(f"> **Status**: {by_status['remediated']} of {len(findings)} findings remediated · "
              f"{by_status.get('accepted_with_residual', 0)} accepted with residual risk. "
              f"Generated from [`findings/findings.yaml`](../findings/findings.yaml) on {today}.")
    md.append("")
    md.append("This document is the appendix to [`docs/PLM_WAF_Review_Report.docx`](PLM_WAF_Review_Report.docx) — "
              "the original review found 27 issues across four Well-Architected pillars. "
              "Each row below records the artefact (Terraform module, runbook, or script) "
              "that delivered the fix.")
    md.append("")

    # ===== Headline numbers =====
    md.append("## Headline")
    md.append("")
    md.append("| Metric | Value |")
    md.append("|--------|-------|")
    md.append(f"| Findings total | {len(findings)} |")
    md.append(f"| HIGH risk remediated | "
              f"{sum(1 for f in findings if f['risk']=='HIGH' and f['status']=='remediated')} / "
              f"{by_risk['HIGH']} |")
    md.append(f"| MEDIUM risk remediated | "
              f"{sum(1 for f in findings if f['risk']=='MEDIUM' and f['status']=='remediated')} / "
              f"{by_risk['MEDIUM']} |")
    md.append(f"| LOW risk remediated | "
              f"{sum(1 for f in findings if f['risk']=='LOW' and f['status']=='remediated')} / "
              f"{by_risk['LOW']} |")
    md.append(f"| **Net monthly saving delivered** | **${total_savings:,}/month** |")
    md.append(f"| Annualised | ${total_savings * 12:,}/year |")
    md.append("")

    # ===== Pillar scores =====
    md.append("## Pillar scores — projected post-remediation")
    md.append("")
    md.append("| Pillar | Score at review | Post-remediation | Delta |")
    md.append("|--------|-----------------|------------------|-------|")
    for p, (pre, post, delta) in pillar_score(findings).items():
        md.append(f"| {pillar_human[p]} | {pre} / 100 | {post} / 100 | **+{delta}** |")
    md.append("")

    # ===== Per-pillar detail =====
    for pillar_key in ["security", "reliability", "performance", "cost"]:
        pillar_findings = [f for f in findings if f["pillar"] == pillar_key]
        md.append(f"## {pillar_human[pillar_key]} ({len(pillar_findings)} findings)")
        md.append("")
        md.append("| ID | Risk | Title | Status | Before → After | Artefact |")
        md.append("|----|------|-------|--------|----------------|----------|")
        for f in pillar_findings:
            status_icon = "✅" if f["status"] == "remediated" else "⚠️"
            ba = f"{f['before']} → {f['after']}"
            md.append(f"| **{f['id']}** | {f['risk']} | {f['title']} | "
                      f"{status_icon} {f['status'].replace('_', ' ')} | "
                      f"{ba} | {fmt_artefact(f.get('fixed_by', {}))} |")
        md.append("")

    # ===== Savings detail =====
    md.append("## Cost savings detail")
    md.append("")
    md.append("| ID | Description | Monthly | Annual |")
    md.append("|----|-------------|---------|--------|")
    cost_findings = sorted(
        [f for f in findings if isinstance(f.get("saving_usd_month"), (int, float))
         and f["saving_usd_month"] != 0],
        key=lambda x: -x["saving_usd_month"],
    )
    for f in cost_findings:
        m = f["saving_usd_month"]
        sign = "−" if m < 0 else ""
        md.append(f"| {f['id']} | {f['title']} | {sign}${abs(m):,} | {sign}${abs(m)*12:,} |")
    md.append("| **TOTAL** | | **${:,}/month** | **${:,}/year** |".format(total_savings, total_savings * 12))
    md.append("")

    # ===== Sequencing diagram =====
    md.append("## Implementation sequencing")
    md.append("")
    md.append("Findings sharing resources were sequenced to minimise maintenance windows.")
    md.append("")
    md.append("```")
    md.append("Sprint 1 (Week 1–2)  ─┐")
    md.append("  SEC-04  AWS WAF (COUNT mode 2-week baseline)")
    md.append("  SEC-03  S3 bucket policy + Access Analyser")
    md.append("  SEC-01  Least-privilege IAM (CloudTrail observation begins)")
    md.append("  REL-03  ASG ELB health checks")
    md.append("  REL-05  Lambda DLQ + alarm")
    md.append("  PERF-03 ALB idle_timeout 300s")
    md.append("  COST-04 VPC Endpoints (S3, DynamoDB, SSM, SQS, SM, Logs)")
    md.append("  COST-06 EBS snapshot cleanup + DLM policy")
    md.append("")
    md.append("Sprint 2 (Week 3–4)  ─┐")
    md.append("  PERF-04 Web tier t3.large → m5.large (rolling refresh)")
    md.append("  PERF-02 ElastiCache Redis Multi-AZ")
    md.append("  REL-06  S3 versioning + CRR + Object Lock + Batch Replication")
    md.append("  COST-03 S3 lifecycle policy")
    md.append("  COST-05 Detailed monitoring off on web tier")
    md.append("")
    md.append("Sprint 3 (Week 5)  ─┐  ★ RDS maintenance window — 4 cross-pillar finding fixes")
    md.append("  SEC-02 + REL-01 + PERF-01/COST-02 + PERF-07 ★")
    md.append("    snapshot → encrypted copy → restore as Multi-AZ r5.xlarge")
    md.append("    apply Query Store via T-SQL bootstrap")
    md.append("  REL-04  RDS Proxy (after RDS cutover stable)")
    md.append("")
    md.append("Sprint 4 (Week 6)  ─┐")
    md.append("  SEC-05  SSM Patch Manager")
    md.append("  PERF-05 Presigned URL 3600s + multipart upload")
    md.append("  COST-01 Savings Plan purchase (after PERF-01 + PERF-04 validated)")
    md.append("")
    md.append("Sprint 5 (Week 7–8)  ─┐")
    md.append("  SEC-06  CloudTrail → Splunk (PMI IT coordination — 3 weeks)")
    md.append("  SEC-07  IR runbook + tabletop exercise")
    md.append("  REL-02  RTO/RPO BIA + SLA sign-off")
    md.append("  REL-07  FIS templates + Game Day")
    md.append("```")
    md.append("")

    # ===== Sign-off =====
    md.append("## Sign-off")
    md.append("")
    md.append("Remediations were applied to the PMI PLM-PROD account between Apr 2023 and "
              "Sep 2023 by the IBM cloud engineering team. All 26 'remediated' findings have "
              "Terraform / runbook artefacts in this repository. The one finding marked "
              "*accepted with residual risk* (PERF-06) is a documented cost/granularity "
              "trade-off — app-tier instances retain 1-min monitoring; web tier moved to "
              "5-min baseline (COST-05).")
    md.append("")
    md.append("- Cloud Architect, IBM India: Vikas Jain")
    md.append("- Cloud Infrastructure Lead, PMI: signed (date in document management system)")
    md.append("- IT Security Officer, PMI: signed")
    md.append("")
    md.append("Annual re-review of the four pillars is scheduled for Q1 of each year, with "
              "the next quarterly Game Day exercising the REL-07 templates.")

    out = ROOT / "docs" / "remediation-summary.md"
    out.write_text("\n".join(md) + "\n")
    print(f"[+] Wrote {out.relative_to(ROOT)} ({len(md)} lines)")


if __name__ == "__main__":
    main()
