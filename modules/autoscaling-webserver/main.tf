provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Generator = "lindsor/opentofu"
    }
  }
}

data "aws_availability_zones" "availability_zones" {
  state = "available"
}

# Latest Ubuntu image
data "aws_ami" "webserver_ami" {
  most_recent = true

  # Only grab ubuntu images from the official "ubuntu" owner
  owners = ["099720109477"]

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

# Create a subnet for each availability zone in the region
resource "aws_subnet" "webserver_subnet" {
  for_each = toset(data.aws_availability_zones.availability_zones.names)

  vpc_id            = aws_vpc.webserver_vpc.id
  cidr_block        = cidrsubnet("10.0.0.0/16", 8, index(data.aws_availability_zones.availability_zones.names, each.key))
  availability_zone = each.key
}

# Create a route table association to allow traffic through
resource "aws_internet_gateway" "webserver_igw" {
  vpc_id = aws_vpc.webserver_vpc.id
}

resource "aws_route_table" "webserver_public_rt" {
  vpc_id = aws_vpc.webserver_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.webserver_igw.id
  }
}

resource "aws_route_table_association" "webserver_subnet_association" {
  for_each = aws_subnet.webserver_subnet

  subnet_id      = each.value.id
  route_table_id = aws_route_table.webserver_public_rt.id

  depends_on = [aws_route_table.webserver_public_rt, aws_subnet.webserver_subnet]
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
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_launch_template" "webserver_launch_template" {
  # Hash of the user data needs to be in name to cause refresh on data change.
  name_prefix   = "webserver-${substr(sha256(var.webserver_user_data), 0, 8)}"
  image_id      = data.aws_ami.webserver_ami.id
  instance_type = var.webserver_instance_size
  key_name      = var.webserver_key_name
  user_data     = base64encode(var.webserver_user_data)

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.webserver_public_access_sg.id]
  }

  monitoring {
    enabled = true
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_security_group.webserver_public_access_sg]

  metadata_options {
    http_tokens   = "required" # Enforce IMDSv2
    http_endpoint = "enabled"
  }
}

resource "aws_autoscaling_group" "webserver_autoscale" {
  name                 = "webserver_autoscale"
  min_size             = var.webserver_min_instances
  max_size             = var.webserver_max_instances
  desired_capacity     = var.webserver_desired_instances
  termination_policies = ["OldestInstance"]

  vpc_zone_identifier = [
    for s in aws_subnet.webserver_subnet : s.id
  ]

  # Do not regenerate the instances based on desired capacity
  lifecycle {
    ignore_changes        = [desired_capacity]
    create_before_destroy = true
  }

  launch_template {
    id      = aws_launch_template.webserver_launch_template.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
  }
}

resource "aws_autoscaling_policy" "webserver_scale_down_policy" {
  name                   = "webserver_scale_down_policy"
  autoscaling_group_name = aws_autoscaling_group.webserver_autoscale.name

  adjustment_type    = "ChangeInCapacity"
  scaling_adjustment = -1
  cooldown           = 120
}

resource "aws_cloudwatch_metric_alarm" "webserver_scale_down_alarm" {
  alarm_description = "Checks if CPU utilization is below a threshold to trigger the autoscale down policy"
  alarm_actions     = [aws_autoscaling_policy.webserver_scale_down_policy.arn]
  alarm_name        = "webserver_scale_down_alarm"

  comparison_operator = "LessThanOrEqualToThreshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  threshold           = "25"
  evaluation_periods  = "5"
  period              = "30"
  statistic           = "Average"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.webserver_autoscale.name
  }
}

resource "aws_autoscaling_policy" "webserver_scale_up_policy" {
  name                   = "webserver_scale_up_policy"
  autoscaling_group_name = aws_autoscaling_group.webserver_autoscale.name

  adjustment_type    = "ChangeInCapacity"
  scaling_adjustment = 1
  cooldown           = 120
}

resource "aws_cloudwatch_metric_alarm" "webserver_scale_up_alarm" {
  alarm_description = "Checks if CPU utilization is below a threshold to trigger the autoscale up policy"
  alarm_actions     = [aws_autoscaling_policy.webserver_scale_up_policy.arn]
  alarm_name        = "webserver_scale_up_alarm"

  comparison_operator = "GreaterThanOrEqualToThreshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  threshold           = "75"
  evaluation_periods  = "5"
  period              = "30"
  statistic           = "Average"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.webserver_autoscale.name
  }
}

# TODO: Attach conditional access logs based on input variable
