terraform {
  required_version = ">= 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket         = "cost-csv-bucket-tfstate-460677238703-ap-northeast-1-an"
    key            = "terraform.tfstate"
    region         = "ap-northeast-1"
    profile        = "default"
  }
}

provider "aws" {
  region = var.aws_region
}

# CloudFrontで使うACM証明書は必ずus-east-1で発行する必要があるため、証明書発行専用にエイリアスを用意する
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
