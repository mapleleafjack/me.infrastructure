# Create a new VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main-vpc"
  }
}

# Create public subnets in the new VPC
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "public-subnet-${count.index}"
  }
}

# Data source to get available AWS zones
data "aws_availability_zones" "available" {}

# Create an Internet Gateway
resource "aws_internet_gateway" "main_gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-gateway"
  }
}

# Create a Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_gw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate Route Table with Subnets
resource "aws_route_table_association" "public_rt_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group for the Backend Service
resource "aws_security_group" "backend_sg" {
  name        = "me-backend-sg"
  description = "Allow traffic to backend"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS Cluster for Backend
resource "aws_ecs_cluster" "backend_cluster" {
  name = "me-backend-cluster"
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECR Repository for Backend
resource "aws_ecr_repository" "backend_repo" {
  name = "me-backend-repo"
}

# ECS Task Definition for Backend
resource "aws_ecs_task_definition" "backend_task" {
  family                   = "me-backend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"   # Adjust based on your backend requirements
  memory                   = "512"   # Adjust based on your backend requirements

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "me-backend-container"
    image     = "${aws_ecr_repository.backend_repo.repository_url}:latest"
    cpu       = 256
    memory    = 512
    essential = true

    portMappings = [{
      containerPort = 5000
      hostPort      = 5000
      protocol      = "tcp"
    }]

    environment = [
      {
        name  = "DB_HOST"
        value = aws_db_instance.postgresql.address
      },
      {
        name  = "DB_PORT"
        value = "5432"
      },
      {
        name  = "DB_USER"
        value = var.db_username
      },
      {
        name  = "DB_PASSWORD"
        value = var.db_password
      },
      {
        name  = "DB_NAME"
        value = "backenddb"
      }
    ]

    # Log configuration to send logs to CloudWatch Logs
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/me-backend-task"
        awslogs-region        = "eu-west-1" # Replace with your AWS region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# ECS Service for Backend
resource "aws_ecs_service" "backend_service" {
  name            = "me-backend-service"
  cluster         = aws_ecs_cluster.backend_cluster.id
  task_definition = aws_ecs_task_definition.backend_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.backend_tg.arn
    container_name   = "me-backend-container"
    container_port   = 5000
  }

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.backend_sg.id]
    assign_public_ip = true
  }

  depends_on = [aws_lb_target_group.backend_tg]
}

# Load Balancer for Backend Service
resource "aws_lb" "backend_lb" {
  name               = "me-backend-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.backend_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "backend-lb"
  }
}

# Target Group for Backend Service
resource "aws_lb_target_group" "backend_tg" {
  name     = "me-backend-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "ip"

    health_check {
        path                = "/"
        protocol            = "HTTP"
        port                = "traffic-port"
        interval            = 30
        timeout             = 5
        unhealthy_threshold = 2
        healthy_threshold   = 2
    }

  tags = {
    Name = "backend-tg"
  }
}

# Listener for Backend Load Balancer
resource "aws_lb_listener" "backend_listener" {
  load_balancer_arn = aws_lb.backend_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_tg.arn
  }
}

# Output the Backend Service URL
output "backend_service_url" {
  value = aws_lb.backend_lb.dns_name
}
