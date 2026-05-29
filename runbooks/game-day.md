# Game Day — REL-07

Half-day structured failure-injection exercise using AWS Fault Injection
Simulator. Validates the remediations landed by REL-01 (Multi-AZ),
REL-03 (ELB health checks), REL-04 (RDS Proxy), REL-05 (Lambda DLQ).

## Pre-flight

- All other REL findings remediated (Multi-AZ, RDS Proxy, DLQ).
- Comms sent: "PLM Game Day Sat 10:00–14:00 GMT; expect alarms; do not page".
- ALB 5xx kill-switch alarm armed (auto-stops experiments if 5xx > 50/min).
- Synthetic monitoring upgraded to 1-min cadence for the window.

## Experiment schedule (4 hours)

| Time | Experiment | Hypothesis | Success criterion |
|------|-----------|------------|-------------------|
| 10:30 | Terminate one web-tier EC2 | ASG replaces within 5 min; ALB health checks (REL-03) drain the dying instance correctly | New instance `InService` within 5 min; zero 5xx during transition |
| 11:00 | RDS Multi-AZ failover | Multi-AZ failover (REL-01) completes ≤ 120 s; RDS Proxy (REL-04) reconnects ARAS without app-side errors | RDS `Available` ≤ 120 s; ARAS app errors zero during window |
| 11:45 | AZ-a subnet network disruption (5 min) | Cross-AZ resilience via ASG + Multi-AZ RDS — service stays available | ALB serves ≥ 95% requests; auto-stops if kill-switch fires |
| 12:30 | Lambda errors (50% inject) | DLQ (REL-05) captures failed events; CloudWatch alarm fires; reprocess script drains DLQ | DLQ message count > 0; alarm fires; `scripts/reprocess-dlq.py` drains queue |
| 13:30 | Debrief + write-up | Team aligns on findings, gaps, follow-ups | One ticket per identified gap |

## Running an experiment

```bash
# Pick the experiment template ID from the FIS module output.
TEMPLATE_ID=$(terraform -chdir=../../terraform/environments/prod \
    output -json fis_experiment_template_ids | jq -r .terminate_ec2)

aws fis start-experiment --experiment-template-id "$TEMPLATE_ID" \
    --tags '[{"key":"GameDay","value":"2026-q2"}]'

# Watch the experiment + the synthetic monitor in parallel.
watch -n 5 'aws fis get-experiment --id $EXPERIMENT_ID --query "experiment.state.status"'
```

## Acceptance + follow-up

After each experiment:

1. **What worked** — confirm the success criterion was met.
2. **What surprised us** — anything unexpected during the experiment.
3. **One ticket per gap** — file in the backlog with the relevant finding ID.

## Cadence

- **Quarterly** — repeat the four experiments above.
- **After major architecture changes** — repeat the affected scenarios.
- **Annually** — extend with new scenarios (cross-region failover, KMS
  rotation, certificate expiry simulation).
