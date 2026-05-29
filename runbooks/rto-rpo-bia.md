# RTO / RPO and Business Impact Analysis — REL-02

Output of the BIA workshop held with PMI R&D Lead, IT Manager, and
Regulatory Affairs Lead. Documents application SLA and maps each SLA target
to specific AWS architecture controls.

## Approved SLA — ARAS PLM

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Availability** | 99.9% during business hours (07:00–22:00 GMT, Mon–Sat) | CloudWatch synthetic canary every 5 min |
| **Availability — out-of-hours** | 99.5% (maintenance windows accepted) | Same canary |
| **RTO** (Recovery Time Objective) | ≤ 2 hours | DR drill measured time-to-readable |
| **RPO** (Recovery Point Objective) | ≤ 1 hour | Backup interval + replication lag |
| **MTTR** (Mean Time To Resolve) | ≤ 4 hours for P1 | PagerDuty incident timeline |

## Business impact tier

ARAS PLM is rated **Tier 2 — Critical Business System**:

- 500 concurrent users supporting global R&D operations
- Regulatory submissions with statutory deadlines depend on this system
- Down-time directly delays product launch decisions
- Material master synchronisation to SAP depends on this system

## SLA → architecture control mapping

| SLA target | Architectural control | Module / Finding |
|-----------|-----------------------|------------------|
| 99.9% availability | Multi-AZ RDS + Multi-AZ ASG + ALB cross-zone load balancing | [rds-mssql](../terraform/modules/rds-mssql/) (REL-01), [alb-asg](../terraform/modules/alb-asg/) |
| RTO ≤ 2h | Aurora-like RDS Multi-AZ failover (60–120s) + ASG instance replacement (5 min) + RDS Proxy reconnect | REL-01, REL-03, REL-04 |
| RPO ≤ 1h | RDS automated backups (5-min transaction log) + S3 versioning + CRR | REL-06 |
| MTTR ≤ 4h | PagerDuty integration via SNS + IR runbook + dashboards | SEC-07, observability module |

## Quarterly DR drill — procedure

Conducted every quarter to validate the RTO target is still achievable.

### Drill 1 — RDS point-in-time recovery (PITR)
1. Note current timestamp `T0`.
2. Pick a non-production-window slot.
3. Initiate PITR to a test instance for `T0 - 15min`:
   ```bash
   aws rds restore-db-instance-to-point-in-time \
       --source-db-instance-identifier plm-mssql-prod \
       --target-db-instance-identifier plm-mssql-drill-$(date +%Y%m%d) \
       --restore-time "$(date -u -d '15 minutes ago' --iso-8601=seconds)"
   ```
4. Wait for `Available`. Record elapsed time.
5. Connect from a bastion. Run a smoke query against the restored DB.
6. Record total time `T_restore`. **Drill passes if `T_restore ≤ 2h`.**
7. Delete the test instance.

### Drill 2 — Multi-AZ failover
Use the FIS template `rds_failover` (REL-07 module) to force failover.
Validate that ARAS reconnects via RDS Proxy within 90 s.

### Drill 3 — Full regional failover (annual)
Exercise the eu-central-1 CRR replica:
1. Promote eu-central-1 S3 replica to primary.
2. Restore RDS to eu-central-1 from a recent automated backup.
3. Re-deploy ARAS stack via Terraform in eu-central-1.
4. Update Route 53 alias.
5. Measure end-to-end time. Target: ≤ 8 hours (extended RTO for regional).

## Backup retention map

| Resource | Backup | Retention | Frequency |
|----------|--------|-----------|-----------|
| RDS SQL Server | Automated backups | 14 days | Daily + 5-min transaction logs |
| RDS SQL Server | Manual snapshots | 35 days | Pre-deployment |
| S3 document vault | Versioning | 90 days (non-current) | Per-object on write |
| S3 document vault | CRR to eu-central-1 | Indefinite (matches source lifecycle) | Async, ≤ 15 min lag |
| S3 regulatory prefix | Object Lock COMPLIANCE | 7 years | Per-object |
| EBS volumes | DLM lifecycle policy | 30 days (manual snapshots) | Daily 02:00 UTC |

## Sign-offs

- R&D Lead, PMI: __________ (Date: __________)
- IT Manager, PMI: _________ (Date: __________)
- Regulatory Affairs, PMI: __________ (Date: __________)
- Cloud Architect, IBM (Vikas Jain): __________ (Date: __________)
