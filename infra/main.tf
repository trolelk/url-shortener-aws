terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket  = "bootstrap-bucket-trolczi"
    key     = "infra/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

module "ecr" {
  source        = "./modules/ecr"
  ecr_repo_name = "url-shortener"
}

module "dynamodb" {
  source = "./modules/dynamodb"
}

module "s3" {
  source         = "./modules/s3"
  s3_bucket_name = "url-shortener-uploads-trolczi"
}

module "sqs" {
  source         = "./modules/sqs"
  sqs_queue_name = "url-shortener-sqs-queue"
}

module "vpc" {
  source = "./modules/vpc"
}

module "ecs" {
  source             = "./modules/ecs"
  public_subnet_ids  = module.vpc.public_subnet_ids
  vpc_id             = module.vpc.vpc_id
  ecr_repository_url = module.ecr.ecr_repository_url
  s3_bucket_name     = module.s3.s3_bucket_name

}

module "lambda" {
  source         = "./modules/lambda"
  s3_bucket_id   = module.s3.s3_bucket_id
  s3_bucket_arn  = module.s3.s3_bucket_arn
  sqs_queue_url  = module.sqs.sqs_queue_url
  sqs_queue_arn  = module.sqs.sqs_queue_arn
  dynamodb_table = "files"
}

module "api_gateway" {
  source       = "./modules/api_gateway"
  alb_dns_name = module.ecs.alb_dns_name
}

