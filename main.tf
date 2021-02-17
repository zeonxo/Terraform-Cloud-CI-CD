provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available"      {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.64.0"

  name = "main-vpc"
  cidr = var.vpc_cidr_block

  azs             = data.aws_availability_zones.available.names
  private_subnets = slice(var.private_subnet_cidr_blocks, 0, var.private_subnet_count)
  public_subnets  = slice(var.public_subnet_cidr_blocks, 0, var.public_subnet_count)

  enable_nat_gateway = false
  enable_vpn_gateway = var.enable_vpn_gateway
}

module "app_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.17.0"

  name        = "web-sg"
  description = "Security group for web-servers with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  
  ingress_cidr_blocks = ["0.0.0.0/0"]
}

module "lb_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.17.0"

  name        = "lb-sg"
  description = "Security group for load balancer with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_instance" "demoapp" {
  count = 3

  ami                    = "ami-a0cfeed8"
  instance_type          = "r6g.4xlarge"
  #instance_type          = "t3.micro"
  #instance_type          = "t2.micro"
  subnet_id              = module.vpc.public_subnets[count.index % length(module.vpc.public_subnets)]
  vpc_security_group_ids = [module.app_security_group.this_security_group_id]
  user_data = templatefile("${path.module}/user_data.sh", {
    file_content = "Demo App V1"
  })

  tags = {
    Name = "Demo App ${count.index + 1}"
  }
}

resource "aws_lb_target_group" "demoapp" {
  name     = "demoapp-lb"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    port     = 80
    protocol = "HTTP"
    timeout  = 5
    interval = 10
  }
}

resource "aws_lb_target_group_attachment" "demoapp" {
  count            = length(aws_instance.demoapp)
  target_group_arn = aws_lb_target_group.demoapp.arn
  target_id        = aws_instance.demoapp[count.index].id
  port             = 80
}

resource "aws_lb" "demoapp" {
  name               = "main-app-hashicorp-demo-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [module.lb_security_group.this_security_group_id]
}

resource "aws_lb_listener" "demoapp" {
  load_balancer_arn = aws_lb.demoapp.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn    = aws_lb_target_group.demoapp.arn
           
  }
}
