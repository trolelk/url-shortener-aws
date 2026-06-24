variable "vpc_id" {
  type = string
}
variable "public_subnet_ids" {
  type = list(string)
}
variable "ecr_repository_url" {
  type = string
}
variable "s3_bucket_name" {
  type = string
}