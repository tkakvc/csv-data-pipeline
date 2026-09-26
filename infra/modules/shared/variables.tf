terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "frontend_domain" {
  type = string
}

variable "route53_zone_name" {
  type = string
}

variable "local_dev_origin" {
  type = string
}
