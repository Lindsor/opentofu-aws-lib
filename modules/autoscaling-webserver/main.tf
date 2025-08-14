provider "aws" {
  region = var.aws_region
}

# Latest Ubuntu image
data "aws_ami" "webserver_ami" {
  most_recent = true

  filter {
    name = "name"
    values = [
      "ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*"
    ]
  }

  filter {
    name = "virtualization-type"
    values = [
      "hvm"
    ]
  }

  filter {
    name = "root-device-type"
    values = [
      "ebs"
    ]
  }
}

resource "aws_vpc" "webserver_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_security_group" "webserver_public_access_sg" {
  name        = "webserver-security-group"
  description = "Public security group allowing incoming HTTP access"

  vpc_id = aws_vpc.webserver_vpc.id

  # In the case of recreation make sure the new security group is created before destroy
  lifecycle {
    create_before_destroy = true
  }

  # TODO: This should probably be only on LB security group
  ingress {
    description      = "Allow HTTP access"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow SSH access"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.webserver_ssh_access_ipv4_cidr_blocks
    ipv6_cidr_blocks = var.webserver_ssh_access_ipv6_cidr_blocks
  }

  egress {
    description      = "Allow all traffic out of webserver. This is needed for installing deps"
    from_port        = 0
    to_port          = 0
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_launch_template" "webserver_launch_template" {
  name                   = "webserver"
  image_id               = data.aws_ami.webserver_ami.id
  instance_type          = var.webserver_instance_size
  vpc_security_group_ids = [aws_security_group.webserver_public_access_sg.id]

  key_name  = var.webserver_key_name
  user_data = var.webserver_user_data
}

resource "aws_autoscaling_group" "webserver_autoscale" {
  name                 = "webserver_autoscale"
  min_size             = var.webserver_min_instances
  max_size             = var.webserver_max_instances
  desired_capacity     = var.webserver_desired_instances
  termination_policies = ["OldestInstance"]

  launch_template {
    id      = aws_launch_template.webserver_launch_template.id
    version = "$Latest"
  }
}
