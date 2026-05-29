region          = "eu-west-1"
replica_region  = "eu-central-1"

# Placeholders — populate after first apply of the original ARAS migration project.
vpc_id                            = "vpc-replace-me"
private_subnet_ids                = ["subnet-app-a", "subnet-app-b"]
private_route_table_ids           = ["rtb-app-a", "rtb-app-b"]
isolated_subnet_ids               = ["subnet-db-a", "subnet-db-b"]
public_subnet_ids                 = ["subnet-pub-a", "subnet-pub-b"]
rds_security_group_ids            = ["sg-rds"]
rds_proxy_security_group_ids      = ["sg-rds-proxy"]
elasticache_security_group_ids    = ["sg-elasticache"]
alb_sg_id                         = "sg-alb"
web_sg_id                         = "sg-web"
app_sg_id                         = "sg-app"
lambda_sg_ids                     = ["sg-lambda"]
rds_resource_id                   = "db-XXXXXXXXXXXXXXXX"
certificate_arn                   = "arn:aws:acm:eu-west-1:000000000000:certificate/REPLACE"
web_ami_id                        = "ami-REPLACE-windows-web"
app_ami_id                        = "ami-REPLACE-windows-app"
access_log_bucket                 = "plm-access-logs"
firehose_failure_bucket_arn       = "arn:aws:s3:::plm-firehose-failures"
replication_destination_arn       = "arn:aws:s3:::plm-aras-documents-replica"
replication_destination_kms_arn   = "arn:aws:kms:eu-central-1:000000000000:key/REPLACE"

email_subscribers     = []
enable_waf_block_mode = false   # flip after 2-week count baseline
