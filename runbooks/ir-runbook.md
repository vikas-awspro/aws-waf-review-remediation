# Cloud incident response runbook — SEC-07

PLM AWS account incident response playbook. Validated via tabletop exercise
with PMI IT Security on T+8w post-WAF review.

## Severity classification

| Severity | Examples | Initial response time |
|----------|----------|------------------------|
| **P0** | Confirmed data exfiltration, ransomware, hostile takeover | ≤ 15 min |
| **P1** | Credential compromise, privilege escalation, suspected breach | ≤ 30 min |
| **P2** | Anomalous IAM activity, suspicious EC2 outbound traffic | ≤ 4 h |
| **P3** | Low-confidence anomaly, requires investigation | next business day |

## Phase 1 — Initial containment (T+0 to T+30 min)

### 1.1 Isolate compromised EC2 instances
```bash
# Move the instance into a quarantine SG (deny-all ingress, allow only IR jump host).
aws ec2 modify-instance-attribute \
    --instance-id i-xxxxx \
    --groups sg-quarantine-prod

# Optionally detach from ASG so it isn't auto-replaced.
aws autoscaling detach-instances \
    --auto-scaling-group-name plm-aras-app-prod \
    --instance-ids i-xxxxx --no-should-decrement-desired-capacity
```

### 1.2 Revoke suspected credentials
```bash
# IAM user (if present)
aws iam list-access-keys --user-name <user>
aws iam update-access-key --access-key-id AKIA... --status Inactive

# Assumed-role sessions — invalidate all current STS tokens by attaching a
# deny-all policy with a creation-time condition.
aws iam put-role-policy --role-name <role> \
    --policy-name DenyAllAfterIncident \
    --policy-document file://deny-after-now.json
```

### 1.3 Disable suspected EventBridge rules / Lambda triggers
Stop the bleed before investigation begins.

## Phase 2 — Evidence preservation (T+30 to T+2h)

### 2.1 Capture EC2 memory + disk
```bash
# AMI snapshot (disk forensics)
aws ec2 create-image --instance-id i-xxxxx \
    --name "ir-evidence-$(date +%Y%m%dT%H%M%S)-${i-xxxxx}" \
    --no-reboot

# EBS snapshot of each attached volume
for v in $(aws ec2 describe-instance-attribute --instance-id i-xxxxx \
            --attribute blockDeviceMapping \
            --query 'BlockDeviceMappings[*].Ebs.VolumeId' --output text); do
    aws ec2 create-snapshot --volume-id "$v" \
        --description "IR evidence — instance i-xxxxx — incident $INCIDENT_ID" \
        --tag-specifications "ResourceType=snapshot,Tags=[{Key=IncidentId,Value=$INCIDENT_ID},{Key=RetainForever,Value=true}]"
done

# Memory dump (requires SSM Session Manager + WinDbg/LiME)
aws ssm send-command --instance-ids i-xxxxx \
    --document-name "AWS-RunPowerShellScript" \
    --parameters commands='Get-Process | Out-File C:\evidence\processes-$(Get-Date -Format yyyyMMddTHHmmss).txt'
```

### 2.2 S3 legal hold on logs
```bash
# Apply Object Lock on the CloudTrail S3 bucket prefix for the incident window.
aws s3api put-object-legal-hold \
    --bucket plm-cloudtrail-logs \
    --key AWSLogs/$ACCT/CloudTrail/eu-west-1/2023/03/15/... \
    --legal-hold Status=ON
```

### 2.3 Preserve CloudTrail + Config history
- Export CloudTrail events for the incident window (±24 h) to a dedicated
  evidence S3 bucket with Object Lock COMPLIANCE 7-year retention.
- Snapshot Config history for the affected resources.

## Phase 3 — Investigation (T+2h to T+24h)

Tooling:
- **Splunk** (SOC integration via SEC-06) — search account events for the
  incident window. Saved searches: `cloud_incident_baseline`,
  `cloud_iam_anomaly`, `cloud_s3_data_access`.
- **GuardDuty findings** — correlate with the timeline.
- **VPC Flow Logs** — egress destinations from the suspect instance.
- **CloudTrail Insights** — anomalous API call patterns.

## Phase 4 — Eradication (T+24h)

- Patch / rebuild affected EC2s from a clean golden AMI.
- Rotate all secrets the instance had access to (Secrets Manager + Parameter Store).
- Re-issue Aurora master credentials.
- Re-create any IAM access keys for affected users.

## Phase 5 — Recovery (T+24h to T+1w)

- Restore service from clean instances.
- Increase monitoring sensitivity (lower alarm thresholds for 30 days).
- Re-run the AWS WAF review for the affected pillars.

## Phase 6 — Post-incident (T+1w to T+30d)

- Post-mortem doc (blameless) — root cause, timeline, controls that worked,
  controls that didn't.
- Update runbooks based on what was learned.
- Update the WAF review action plan if new findings were exposed.

## Escalation contacts

| Role | Contact | When |
|------|---------|------|
| PMI CISO | PMI directory | Any confirmed P0/P1 |
| AWS TAM / Support | AWS Console → Support Center | Any P0/P1 needing AWS assistance |
| IBM delivery lead | IBM PM | P0/P1 incidents involving delivered components |
| Legal / privacy | PMI Legal | Confirmed personal-data exposure |
| Regulatory | PMI Regulatory | Personal-data breach affecting > 100 individuals (GDPR) |

## Communication templates

Pre-approved templates in [PMI document management system, ref CLOUD-IR-COMMS-001](#).
Cover: internal exec brief, all-staff notice, regulator notification, customer notice.
