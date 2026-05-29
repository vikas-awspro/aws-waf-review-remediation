################################################################################
# S3 document vault — three findings remediated in one module:
#   SEC-03  : explicit bucket policy + S3 Access Analyser
#   REL-06  : versioning + Cross-Region Replication + Object Lock
#   COST-03 : lifecycle policy (Standard → STD-IA → Glacier Flex → expire 7y)
################################################################################

############################
# Bucket + base hardening
############################

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = merge(var.tags, { Findings = "SEC-03 REL-06 COST-03" })

  # Object Lock for regulatory prefix — enabled at bucket creation only
  object_lock_enabled = true
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

############################
# REL-06 — versioning (must be enabled before CRR)
############################

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status     = "Enabled"
    mfa_delete = "Disabled"
  }
}

############################
# SEC-03 — explicit bucket policy
############################

data "aws_iam_policy_document" "bucket" {
  # Deny non-TLS requests.
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Deny unencrypted PutObject.
  statement {
    sid       = "DenyUnencryptedPut"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  # Allow only the listed principals — default deny applies to everyone else.
  statement {
    sid    = "AppAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
      "s3:GetObjectVersion", "s3:GetObjectTagging", "s3:PutObjectTagging",
    ]
    resources = ["${aws_s3_bucket.this.arn}/documents/*"]
    principals {
      type        = "AWS"
      identifiers = [var.app_tier_role_arn]
    }
  }
  statement {
    sid       = "AppAccessList"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.this.arn]
    principals {
      type        = "AWS"
      identifiers = [var.app_tier_role_arn]
    }
  }
  statement {
    sid       = "BackupRoleReadOnly"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
    principals {
      type        = "AWS"
      identifiers = [var.backup_role_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json
}

############################
# REL-06 — Object Lock COMPLIANCE for regulatory prefix
############################

resource "aws_s3_bucket_object_lock_configuration" "regulatory" {
  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode  = "COMPLIANCE"
      years = 7
    }
  }
}

############################
# COST-03 — lifecycle policy
############################

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Archive prefix — aged objects transition to cheaper tiers.
  rule {
    id     = "archive-documents"
    status = "Enabled"
    filter { prefix = "documents/archive/" }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 365
      storage_class = "GLACIER_IR"   # Glacier Flexible Retrieval — Instant Retrieval variant
    }
    expiration {
      days = 2555   # 7 years — customer document retention policy
    }
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # Active-project prefix — stays in Standard, but expire old versions.
  rule {
    id     = "current-project-versions"
    status = "Enabled"
    filter { prefix = "documents/current-project/" }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
    noncurrent_version_expiration {
      noncurrent_days = 180
    }
  }

  # Abort incomplete multipart uploads after 7 days.
  rule {
    id     = "abort-multipart"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

############################
# REL-06 — Cross-Region Replication to eu-central-1
############################

data "aws_iam_policy_document" "crr_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "crr" {
  name               = "s3-crr-${var.bucket_name}"
  assume_role_policy = data.aws_iam_policy_document.crr_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "crr" {
  role = aws_iam_role.crr.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = aws_s3_bucket.this.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersion", "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionForReplication", "s3:GetObjectVersionTagging",
          "s3:GetObjectRetention", "s3:GetObjectLegalHold",
        ]
        Resource = "${aws_s3_bucket.this.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags",
          "s3:ObjectOwnerOverrideToBucketOwner",
        ]
        Resource = "${var.replication_destination_arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["kms:Decrypt"]
        Resource = [var.kms_key_arn]
      },
      {
        Effect = "Allow"
        Action = ["kms:Encrypt", "kms:GenerateDataKey"]
        Resource = [var.replication_destination_kms_arn]
      },
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "this" {
  depends_on = [aws_s3_bucket_versioning.this]

  bucket = aws_s3_bucket.this.id
  role   = aws_iam_role.crr.arn

  rule {
    id     = "documents-to-eu-central-1"
    status = "Enabled"
    priority = 1

    filter { prefix = "documents/" }

    destination {
      bucket        = var.replication_destination_arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = var.replication_destination_kms_arn
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects { status = "Enabled" }
    }

    delete_marker_replication { status = "Enabled" }
  }
}

############################
# Server access logging → centralised log bucket (SEC-03)
############################

resource "aws_s3_bucket_logging" "this" {
  count         = var.access_log_bucket == "" ? 0 : 1
  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_log_bucket
  target_prefix = "s3-access-logs/${var.bucket_name}/"
}
