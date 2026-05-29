# RDS encryption cutover — SEC-02

Encrypts the running RDS SQL Server PLM database. AWS RDS cannot enable
storage encryption on a live instance — the only path is **snapshot →
encrypted copy → restore → application cutover**.

## Pre-flight (T-72h)

| Check | Owner | Evidence |
|-------|-------|----------|
| Backup window confirmed (Sat 22:00 GMT → Sun 02:00 GMT) | DBA Lead | Change ticket approved |
| Staging environment validates encrypted instance with app | DBA + App | 24h staging soak passes |
| KMS key `alias/rds-plm-prod` exists with rotation enabled | Cloud Eng | `aws kms describe-key` |
| Aurora target sized identical (db.r5.xlarge per PERF-01) | DBA Lead | Terraform plan diff |
| the application connection string change tested in staging | App Team | UAT pass |

## Cutover sequence (4-hour window)

### T-0:00 — Open window
- App team drains the ALB (graceful 60s connection drain).
- Confirm zero active the application sessions.

### T-0:05 — Final snapshot of source
```bash
aws rds create-db-snapshot \
    --db-instance-identifier plm-mssql-prod \
    --db-snapshot-identifier plm-mssql-prod-final-pre-encrypt
aws rds wait db-snapshot-available \
    --db-snapshot-identifier plm-mssql-prod-final-pre-encrypt
```

### T-0:30 — Copy snapshot with encryption
```bash
aws rds copy-db-snapshot \
    --source-db-snapshot-identifier plm-mssql-prod-final-pre-encrypt \
    --target-db-snapshot-identifier plm-mssql-prod-final-encrypted \
    --kms-key-id alias/rds-plm-prod \
    --copy-tags
aws rds wait db-snapshot-completed \
    --db-snapshot-identifier plm-mssql-prod-final-encrypted
```

### T-1:00 — Restore as a new instance
The Terraform module `terraform/modules/rds-mssql` defines the target state
(Multi-AZ, encrypted, right-sized). Apply with the
`restore_from_snapshot_identifier` variable temporarily set:

```bash
cd terraform/environments/prod
terraform apply -var='rds_restore_from_snapshot=plm-mssql-prod-final-encrypted'
```

Wait for `Status=available`. Validate from a bastion that the new instance
accepts SQL connections.

### T-2:00 — Application cutover
1. Update the application connection string SSM parameter to point at the new endpoint:
   ```bash
   aws ssm put-parameter --name /app/db/endpoint \
       --value plm-mssql-prod-encrypted.cluster-xxxx.eu-west-1.rds.amazonaws.com \
       --type String --overwrite
   ```
2. Restart the application services on web/app tier (rolling, one instance at a time).
3. Run the application smoke tests:
   - Login + dashboard render
   - Product structure query
   - Document upload (with the new presigned URL — see PERF-05)
   - Reference data lookup (verifies the ElastiCache cache layer per PERF-02)

### T-3:00 — Re-open LB
- Re-attach app servers to ALB.
- Monitor CloudWatch + Splunk for 30 min: error rate, p99 latency, RDS connections.

### T-3:30 — Cutover confirmed
- Send success comms.
- Tag the old unencrypted instance: `DeleteAfter=T+48h`.

## T+48h — Decommission old instance
After 48-hour validation with no rollback request:

```bash
aws rds delete-db-instance \
    --db-instance-identifier plm-mssql-prod \
    --skip-final-snapshot
```
(The final-pre-encrypt snapshot we took at T-0:05 is retained for forensic use.)

## Rollback (any time before T-3:30)

The original unencrypted instance is **untouched** during this cutover —
only the application connection string moves. Revert the SSM parameter,
restart the application services, re-open the LB to the original endpoint. The
encrypted copy and snapshot remain available for a future attempt.

## Acceptance criteria

- `aws rds describe-db-instances` shows `StorageEncrypted=true` and the
  expected KMS key ARN.
- `aws rds describe-db-instances` shows `MultiAZ=true` (REL-01 combined).
- the application smoke tests pass within 30 min.
- No P1 application incident in the 48 h post-cutover.
