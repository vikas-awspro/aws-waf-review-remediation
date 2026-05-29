# Compute Savings Plan purchase — COST-01

## Why a Savings Plan, not Reserved Instances

The PLM workload is stable and 24/7 — both options apply. We chose Compute
Savings Plan over RIs for one reason: **flexibility during the remediation
window**. PERF-01 / COST-02 right-sizes RDS, and PERF-04 changes the web
tier from t3 to m5. Buying RIs at the pre-remediation sizes would lock in
the wrong instance type for a year. A Compute Savings Plan covers EC2 +
Fargate + Lambda + (separately) the RDS RI we'll buy *after* rightsizing.

## Sequencing

| Order | Action | Owner | Timing |
|-------|--------|-------|--------|
| 1 | Apply PERF-04 (web tier m5.large) and validate 1 week | Cloud Eng | Sprint 1 |
| 2 | Purchase Compute Savings Plan (covers EC2) | Finance + Cloud Eng | Sprint 1 end |
| 3 | Apply PERF-01 (RDS r5.xlarge) during maintenance window + validate 2 weeks | DBA + Cloud Eng | Sprint 2 |
| 4 | Purchase RDS Reserved Instance at r5.xlarge | Finance + DBA | Sprint 3 |

## Sizing — Compute Savings Plan

Read the recommendation from Cost Explorer:

```bash
aws ce get-savings-plans-purchase-recommendation \
    --savings-plans-type COMPUTE_SP \
    --term-in-years ONE_YEAR \
    --payment-option NO_UPFRONT \
    --lookback-period-in-days SIXTY_DAYS \
    --query 'SavingsPlansPurchaseRecommendation.SavingsPlansPurchaseRecommendationDetails[0]'
```

Recommended commitment from the review: **$1,500/month**. This represents
~85% of current On-Demand EC2 spend — leaves headroom for organic growth
and the Lambda integration layer.

## Purchase steps

1. **Finance approval** — open PR/ticket with customer procurement. Expected
   2–3 business days.
2. **Cost Explorer → Savings Plans → Purchase**.
3. Select:
   - Type: **Compute Savings Plans**
   - Term: **1 year**
   - Payment: **No Upfront**
   - Hourly commitment: **$2.00/hour** ($1,500/month ÷ 730 hours)
4. **Review** — expected savings vs On-Demand displayed (target 40–50%).
5. **Purchase**.

## Validation

24 hours after purchase:

```bash
# Confirm coverage > 95% of On-Demand compute spend
aws ce get-savings-plans-coverage \
    --time-period "Start=$(date -u -d '24 hours ago' +%F),End=$(date -u +%F)" \
    --granularity DAILY \
    --metrics SpendCoveredBySavingsPlans
```

## RDS RI — buy after PERF-01

After PERF-01 has been running 2 weeks at r5.xlarge:

```bash
# Get the eu-west-1 r5.xlarge SQL Server SE offering ID
aws rds describe-reserved-db-instances-offerings \
    --db-instance-class db.r5.xlarge \
    --product-description "sqlserver-se(li)" \
    --duration 31536000 \
    --offering-type "No Upfront"

# Purchase
aws rds purchase-reserved-db-instances-offering \
    --reserved-db-instances-offering-id <id-from-above> \
    --reserved-db-instance-id plm-mssql-prod-ri-2026
```

## Acceptance criteria

- Savings Plans coverage ≥ 95% of compute spend within 1 week of purchase.
- Effective rate visible in Cost Explorer drops by ≥ 40% on EC2 cost line.
- After RDS RI: combined monthly compute spend down by $1,400–1,800 vs
  pre-remediation baseline.

## Annual review

Re-evaluate commitment level annually. If a workload doubles, increase the
commitment proactively (still cheaper than On-Demand for the new baseline).
If a workload shrinks, do **not** cancel the existing commitment — let it
expire naturally; cancellation is not supported.
