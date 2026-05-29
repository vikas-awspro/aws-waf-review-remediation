terraform {
  required_version = ">= 1.6"

  required_providers {
    aws      = { source = "hashicorp/aws",      version = ">= 5.40" }
    null     = { source = "hashicorp/null",     version = ">= 3.2"  }
  }

  backend "s3" {
    bucket         = "plm-waf-remediation-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "plm-waf-remediation-tfstate-lock"
    encrypt        = true
    kms_key_id     = "alias/plm-waf-remediation-tfstate"
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "plm-waf-remediation"
      Environment = "prod"
      ManagedBy   = "terraform"
      Workload    = "aras-plm"
    }
  }
}

# Secondary provider — for the CRR destination bucket (REL-06).
provider "aws" {
  alias  = "replica"
  region = var.replica_region
  default_tags {
    tags = {
      Project     = "plm-waf-remediation"
      Environment = "prod"
      ManagedBy   = "terraform"
      Workload    = "aras-plm"
      Role        = "dr-replica"
    }
  }
}
