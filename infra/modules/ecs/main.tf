resource "aws_security_group" "alb_sg_shortener" {
  name = "sg alb inbound port 80"
  description = "Allow port 80 inbound connection for alb"
  vpc_id = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_ingress" {
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 80
  to_port = 80
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.alb_sg_shortener.id
}

resource "aws_vpc_security_group_egress_rule" "alb_all_egress" {
  cidr_ipv4 = "0.0.0.0/0"
  ip_protocol       = "-1"
  security_group_id = aws_security_group.alb_sg_shortener.id
}

resource "aws_security_group" "ecs_sg" {
  name = "sg ecs"
  vpc_id = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "ecs_app_ingress" {
  referenced_security_group_id = aws_security_group.alb_sg_shortener.id
  security_group_id = aws_security_group.ecs_sg.id
  ip_protocol = "tcp"
  from_port = 8000
  to_port   = 8000
}

resource "aws_vpc_security_group_egress_rule" "ecs_all_egress" {
  cidr_ipv4 = "0.0.0.0/0"
  ip_protocol       = "-1"
  security_group_id = aws_security_group.ecs_sg.id
}

resource "aws_lb" "alb_url_shortener" {
  name = "url-shortener-alb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb_sg_shortener.id]
  subnets = var.public_subnet_ids
}

resource "aws_lb_target_group" "alb_tg_shortener" {
  name = "alb-tg-url-shortener"
  port = 8000
  protocol = "HTTP"
  vpc_id = var.vpc_id
  target_type = "ip"

  health_check {
    path = "/health"
  }
}

resource "aws_lb_listener" "alb_listener_http" {
  load_balancer_arn = aws_lb.alb_url_shortener.arn
  port = 80
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.alb_tg_shortener.arn
  }
}

resource "aws_iam_role" "ecs_exec_role" {
  name = "ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_role_policy" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "ecs-task-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:Scan"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "url-shortener"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/url-shortener"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = "url-shortener-tasks"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name  = "url-shortener"
    image = var.ecr_repository_url
    portMappings = [{
      containerPort = 8000
      hostPort      = 8000
    }]
    environment = [
      { name = "S3_BUCKET",      value = var.s3_bucket_name },
      { name = "DYNAMODB_TABLE", value = "urls" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/url-shortener"
        awslogs-region        = "eu-central-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "ecs_service_shortener" {
  name = "aws_ecs_services"
  cluster = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count = 1
  launch_type = "FARGATE"
  network_configuration {
    subnets = var.public_subnet_ids
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.alb_tg_shortener.arn
    container_name = "url-shortener"
    container_port = 8000
  }
}