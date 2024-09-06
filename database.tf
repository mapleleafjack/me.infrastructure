# Create a Subnet Group for the RDS Database
resource "aws_db_subnet_group" "backend_db_subnet_group" {
  name       = "backend-db-subnet-group"
  subnet_ids = aws_subnet.public[*].id

  tags = {
    Name = "backend-db-subnet-group"
  }
}

# Create a Security Group for PostgreSQL Database
resource "aws_security_group" "postgresql_sg" {
  name        = "me-postgresql-sg"
  description = "Allow PostgreSQL traffic from backend"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_sg.id] # Only allow traffic from backend security group
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a PostgreSQL RDS Instance
resource "aws_db_instance" "postgresql" {
  allocated_storage      = 20 # Adjust storage size as per your requirements
  engine                 = "postgres"
  engine_version         = "16.4"        # Adjust version as needed
  instance_class         = "db.t3.micro" # Adjust instance type as needed
  db_name                = "backenddb"
  username               = var.db_username
  password               = var.db_password # Use variable instead of hardcoded password
  parameter_group_name   = "default.postgres16"
  db_subnet_group_name   = aws_db_subnet_group.backend_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.postgresql_sg.id]

  skip_final_snapshot = true

  tags = {
    Name = "backend-postgresql"
  }
}

# Output the Database Endpoint
output "postgresql_db_endpoint" {
  value = aws_db_instance.postgresql.address
}
