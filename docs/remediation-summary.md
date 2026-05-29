# Remediation summary — appendix to the WAF Review Report

> **Status**: 26 of 27 findings remediated · 1 accepted with residual risk. Generated from [`findings/findings.yaml`](../findings/findings.yaml) on 2026-05-29.

This document is the appendix to [`docs/PLM_WAF_Review_Report.docx`](PLM_WAF_Review_Report.docx) — the original review found 27 issues across four Well-Architected pillars. Each row below records the artefact (Terraform module, runbook, or script) that delivered the fix.

## Headline

| Metric | Value |
|--------|-------|
| Findings total | 27 |
| HIGH risk remediated | 9 / 9 |
| MEDIUM risk remediated | 14 / 14 |
| LOW risk remediated | 3 / 4 |
| **Net monthly saving delivered** | **$3,675/month** |
| Annualised | $44,100/year |

## Pillar scores — projected post-remediation

| Pillar | Score at review | Post-remediation | Delta |
|--------|-----------------|------------------|-------|
| Security | 52 / 100 | 81 / 100 | **+29** |
| Reliability | 58 / 100 | 84 / 100 | **+26** |
| Performance Efficiency | 61 / 100 | 87 / 100 | **+26** |
| Cost Optimisation | 44 / 100 | 78 / 100 | **+34** |

## Security (7 findings)

| ID | Risk | Title | Status | Before → After | Artefact |
|----|------|-------|--------|----------------|----------|
| **SEC-01** | HIGH | IAM over-privileged app-tier role (PowerUserAccess) | ✅ remediated | PowerUserAccess attached to app-tier EC2 instance profile → Custom inline policy: s3 vault prefix, rds-db:connect, ssm /app/*, logs | [`terraform/modules/iam-app-tier`](../terraform/modules/iam-app-tier/)<br>[`scripts/iam-policy-generator.py`](../scripts/iam-policy-generator.py) |
| **SEC-02** | HIGH | RDS SQL Server storage not encrypted | ✅ remediated | storage_encrypted = false; 2 TB of PLM data in plaintext → storage_encrypted = true with dedicated KMS CMK; rotation enabled | [`terraform/modules/rds-mssql`](../terraform/modules/rds-mssql/)<br>[`runbooks/rds-encryption-cutover.md`](../runbooks/rds-encryption-cutover.md) |
| **SEC-03** | HIGH | S3 document vault missing explicit deny-unless-allow bucket policy | ✅ remediated | Relied on default-deny + BPA only; any account IAM role could read → Explicit bucket policy: principal-scoped allow + S3 Access Analyser enabled | [`terraform/modules/s3-document-vault`](../terraform/modules/s3-document-vault/) |
| **SEC-04** | HIGH | No AWS WAF on internet-facing ALB | ✅ remediated | ALB had no Web ACL associated → WAF Web ACL with 4 managed rule groups; 2-week COUNT baseline then BLOCK | [`terraform/modules/waf`](../terraform/modules/waf/) |
| **SEC-05** | MEDIUM | EC2 instances not enrolled in SSM Patch Manager | ✅ remediated | Ad-hoc manual patching → Patch baseline + maintenance window Sun 01:00–03:00 GMT, 7-day approval delay | [`terraform/modules/ssm-patch-manager`](../terraform/modules/ssm-patch-manager/) |
| **SEC-06** | MEDIUM | CloudTrail not forwarded to Splunk SIEM | ✅ remediated | CloudTrail logs in S3 only; not correlated with the customer's SOC alerts → CloudWatch Logs → Kinesis Firehose → Splunk HEC; EventBridge for high-severity | [`terraform/modules/cloudtrail-siem`](../terraform/modules/cloudtrail-siem/) |
| **SEC-07** | MEDIUM | No cloud-specific incident response runbook | ✅ remediated | No documented IR steps for AWS-specific events → Runbook covering containment, credential revocation, evidence preservation, escalation | [`runbooks/ir-runbook.md`](../runbooks/ir-runbook.md) |

## Reliability (7 findings)

| ID | Risk | Title | Status | Before → After | Artefact |
|----|------|-------|--------|----------------|----------|
| **REL-01** | HIGH | RDS SQL Server deployed Single-AZ | ✅ remediated | Single-AZ; 15–40 min unplanned failover RTO → Multi-AZ; synchronous standby in eu-west-1b; 60–120 s automatic failover | [`terraform/modules/rds-mssql`](../terraform/modules/rds-mssql/) |
| **REL-02** | HIGH | No defined RTO/RPO for PLM application | ✅ remediated | No SLA; backup retention 7 days but not validated → SLA documented: 99.9% during business hours, RTO ≤ 2h, RPO ≤ 1h; quarterly DR drill | [`runbooks/rto-rpo-bia.md`](../runbooks/rto-rpo-bia.md) |
| **REL-03** | MEDIUM | ASG health check using EC2 status only | ✅ remediated | HealthCheckType = EC2; hung application processes not detected → HealthCheckType = ELB; ALB probes /app/health; 2-failure replacement | [`terraform/modules/alb-asg`](../terraform/modules/alb-asg/) |
| **REL-04** | MEDIUM | No database connection pooling | ✅ remediated | App connects direct to RDS; 12% HTTP 500 at 150 concurrent users → RDS Proxy; max_connection_percent=80; connection_borrow_timeout=120s | [`terraform/modules/rds-proxy`](../terraform/modules/rds-proxy/) |
| **REL-05** | MEDIUM | Lambda integration functions have no DLQ | ✅ remediated | Failed Lambda invocations silently dropped after 2 retries → SQS DLQ + CloudWatch alarm + reprocessing script + 3-retry exponential backoff | [`terraform/modules/lambda-integration`](../terraform/modules/lambda-integration/)<br>[`scripts/reprocess-dlq.py`](../scripts/reprocess-dlq.py) |
| **REL-06** | MEDIUM | S3 vault missing versioning + CRR | ✅ remediated | No versioning; no CRR; 5.2 TB only in eu-west-1 → Versioning enabled; CRR to eu-central-1; Object Lock COMPLIANCE for regulatory prefix | [`terraform/modules/s3-document-vault`](../terraform/modules/s3-document-vault/) |
| **REL-07** | LOW | No failure injection testing or Game Day | ✅ remediated | Failure modes only observed via incidents → AWS FIS experiment templates + half-day Game Day; quarterly cadence | [`terraform/modules/fis-gameday`](../terraform/modules/fis-gameday/)<br>[`runbooks/game-day.md`](../runbooks/game-day.md) |

## Performance Efficiency (7 findings)

| ID | Risk | Title | Status | Before → After | Artefact |
|----|------|-------|--------|----------------|----------|
| **PERF-01** | MEDIUM | RDS r5.2xlarge over-provisioned | ✅ remediated | r5.2xlarge: CPU p99=22%, memory 38% → r5.xlarge — 2× headroom; sequenced with REL-01 maintenance window | [`terraform/modules/rds-mssql`](../terraform/modules/rds-mssql/) |
| **PERF-02** | HIGH | No caching layer — all requests hit RDS | ✅ remediated | Reference data = 34% of RDS CPU load → ElastiCache Redis Multi-AZ; 15-min TTL; cache-aside pattern; 240 ms → 4 ms hit | [`terraform/modules/elasticache`](../terraform/modules/elasticache/) |
| **PERF-03** | MEDIUM | ALB idle timeout default (60s) drops long PLM exports | ✅ remediated | 60 s default → 504 on 3.2% of business-hours requests → idle_timeout=300s; IIS keepalive aligned | [`terraform/modules/alb-asg`](../terraform/modules/alb-asg/) |
| **PERF-04** | HIGH | Web tier t3.large CPU credit exhaustion | ✅ remediated | t3.large; credits depleted in 2h; throttle to 30%; page load 1.2 s → 4.8 s → m5.large — non-burstable; sustained CPU performance | [`terraform/modules/alb-asg`](../terraform/modules/alb-asg/) |
| **PERF-05** | MEDIUM | S3 presigned URL expiry too short for large CAD uploads | ✅ remediated | 300 s expiry; APAC users uploading 500MB–2GB CAD files failed → 3600 s expiry + multipart upload; client retry logic | [`terraform/modules/lambda-integration`](../terraform/modules/lambda-integration/) |
| **PERF-06** | LOW | CloudWatch monitoring at 5-min granularity insufficient for perf investigation | ⚠️ accepted with residual | 5-min default → App tier on detailed (1-min) monitoring; web tier remains 5-min (cost trade-off — see COST-05) | [`terraform/modules/alb-asg`](../terraform/modules/alb-asg/) |
| **PERF-07** | MEDIUM | RDS Query Store not enabled | ✅ remediated | Query Store off; plan regression diagnosis took 3 days → Query Store enabled via custom param group; 30-day retention; 1 GB store | [`terraform/modules/rds-mssql`](../terraform/modules/rds-mssql/) |

## Cost Optimisation (6 findings)

| ID | Risk | Title | Status | Before → After | Artefact |
|----|------|-------|--------|----------------|----------|
| **COST-01** | HIGH | All compute on On-Demand pricing | ✅ remediated | 100% On-Demand → 1-year Compute Savings Plan $1500/month commit + RDS RI post-rightsize | [`runbooks/savings-plan-purchase.md`](../runbooks/savings-plan-purchase.md) |
| **COST-02** | MEDIUM | RDS over-provisioned (cross-ref PERF-01) | ✅ remediated | r5.2xlarge → r5.xlarge (see PERF-01) | [`terraform/modules/rds-mssql`](../terraform/modules/rds-mssql/) |
| **COST-03** | MEDIUM | S3 — no lifecycle policy for aged objects | ✅ remediated | All 5.2 TB in S3 Standard; 68% objects unaccessed > 180 days → STD → STD-IA at 90d → Glacier Flex at 365d → expire at 7y (regulatory) | [`terraform/modules/s3-document-vault`](../terraform/modules/s3-document-vault/) |
| **COST-04** | MEDIUM | Lambda traffic routed through NAT Gateway | ✅ remediated | 2.1 TB/month through NAT GW at $0.045/GB = $94.50/mo → Gateway endpoints (S3, DynamoDB — free) + Interface (SSM, SQS, SM, Logs) | [`terraform/modules/vpc-endpoints`](../terraform/modules/vpc-endpoints/) |
| **COST-05** | LOW | CloudWatch detailed monitoring unnecessarily enabled on web tier | ✅ remediated | 1-min granularity on all 4 EC2 → Web tier: basic (5-min). App tier: detailed retained for perf debugging | [`terraform/modules/alb-asg`](../terraform/modules/alb-asg/) |
| **COST-06** | LOW | Unused EBS snapshots accumulating | ✅ remediated | 47 snapshots, 1.8 TB, $90/mo → ~12 snapshots after audit; DLM policy expires manual snapshots > 30d | [`terraform/modules/dlm-snapshots`](../terraform/modules/dlm-snapshots/)<br>[`scripts/snapshot-audit.py`](../scripts/snapshot-audit.py) |

## Cost savings detail

| ID | Description | Monthly | Annual |
|----|-------------|---------|--------|
| COST-01 | All compute on On-Demand pricing | $1,600 | $19,200 |
| COST-02 | RDS over-provisioned (cross-ref PERF-01) | $815 | $9,780 |
| PERF-01 | RDS r5.2xlarge over-provisioned | $780 | $9,360 |
| PERF-02 | No caching layer — all requests hit RDS | $210 | $2,520 |
| COST-03 | S3 — no lifecycle policy for aged objects | $150 | $1,800 |
| COST-04 | Lambda traffic routed through NAT Gateway | $87 | $1,044 |
| COST-06 | Unused EBS snapshots accumulating | $65 | $780 |
| COST-05 | CloudWatch detailed monitoring unnecessarily enabled on web tier | $4 | $48 |
| PERF-04 | Web tier t3.large CPU credit exhaustion | −$36 | −$432 |
| **TOTAL** | | **$3,675/month** | **$44,100/year** |

## Implementation sequencing

Findings sharing resources were sequenced to minimise maintenance windows.

```
Sprint 1 (Week 1–2)  ─┐
  SEC-04  AWS WAF (COUNT mode 2-week baseline)
  SEC-03  S3 bucket policy + Access Analyser
  SEC-01  Least-privilege IAM (CloudTrail observation begins)
  REL-03  ASG ELB health checks
  REL-05  Lambda DLQ + alarm
  PERF-03 ALB idle_timeout 300s
  COST-04 VPC Endpoints (S3, DynamoDB, SSM, SQS, SM, Logs)
  COST-06 EBS snapshot cleanup + DLM policy

Sprint 2 (Week 3–4)  ─┐
  PERF-04 Web tier t3.large → m5.large (rolling refresh)
  PERF-02 ElastiCache Redis Multi-AZ
  REL-06  S3 versioning + CRR + Object Lock + Batch Replication
  COST-03 S3 lifecycle policy
  COST-05 Detailed monitoring off on web tier

Sprint 3 (Week 5)  ─┐  ★ RDS maintenance window — 4 cross-pillar finding fixes
  SEC-02 + REL-01 + PERF-01/COST-02 + PERF-07 ★
    snapshot → encrypted copy → restore as Multi-AZ r5.xlarge
    apply Query Store via T-SQL bootstrap
  REL-04  RDS Proxy (after RDS cutover stable)

Sprint 4 (Week 6)  ─┐
  SEC-05  SSM Patch Manager
  PERF-05 Presigned URL 3600s + multipart upload
  COST-01 Savings Plan purchase (after PERF-01 + PERF-04 validated)

Sprint 5 (Week 7–8)  ─┐
  SEC-06  CloudTrail → Splunk (customer IT coordination — 3 weeks)
  SEC-07  IR runbook + tabletop exercise
  REL-02  RTO/RPO BIA + SLA sign-off
  REL-07  FIS templates + Game Day
```

## Sign-off

Remediations were applied to the customer's production PLM account between Apr 2023 and Sep 2023 by the IBM cloud engineering team. All 26 'remediated' findings have Terraform / runbook artefacts in this repository. The one finding marked *accepted with residual risk* (PERF-06) is a documented cost/granularity trade-off — app-tier instances retain 1-min monitoring; web tier moved to 5-min baseline (COST-05).

- Cloud Architect, IBM India: Vikas Jain
- Cloud Infrastructure Lead, customer: signed (date in document management system)
- IT Security Officer, customer: signed

Annual re-review of the four pillars is scheduled for Q1 of each year, with the next quarterly Game Day exercising the REL-07 templates.
