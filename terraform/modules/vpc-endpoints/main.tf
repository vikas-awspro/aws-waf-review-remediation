################################################################################
# VPC Endpoints — COST-04 — eliminates NAT GW data-processing charges for
# Lambda → AWS service traffic. Gateway endpoints (S3 + DynamoDB) are free;
# Interface endpoints (SSM, Secrets Manager, SQS, Logs) cost ~$0.01/hr each
# but eliminate the $94/month NAT charges.
################################################################################

############################
# Gateway endpoints — free, attached to private route tables
############################

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids
  tags              = merge(var.tags, { Finding = "COST-04" })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids
  tags              = merge(var.tags, { Finding = "COST-04" })
}

############################
# Interface endpoints (placed in private subnets where Lambda runs)
############################

resource "aws_security_group" "endpoint" {
  name        = "vpc-endpoint-${var.environment}"
  description = "HTTPS from Lambda + EC2 SGs to AWS service interface endpoints"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = var.client_sg_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Finding = "COST-04" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset([
    "ssm", "ssmmessages", "ec2messages",
    "secretsmanager",
    "sqs", "sns", "events",
    "logs", "monitoring",
    "kms",
    "sts",
  ])

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Finding = "COST-04", Service = each.value })
}
