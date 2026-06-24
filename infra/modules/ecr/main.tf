resource "aws_ecr_repository" "ecr_repo" {
  name = var.ecr_repo_name
  force_delete = true
}