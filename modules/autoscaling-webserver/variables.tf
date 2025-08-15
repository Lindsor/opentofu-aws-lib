variable "aws_region" {
  description = "The AWS region to deploy all resources"
  type        = string
}

variable "webserver_instance_size" {
  description = "The instance size of the webserver EC2"
  type        = string
}

variable "webserver_key_name" {
  description = "The name of the SSH key in AWS console to use for the EC2 instances."
  type        = string
}

variable "webserver_user_data" {
  description = "The user data to be used when initializing the EC2 instances."
  type        = string
}

variable "webserver_ssh_access_ipv4_cidr_blocks" {
  description = "The optional IPv4 CIDR block for ssh access to the webserver instances. Make sure to add /32 to your IP if its a single ip address."
  type        = list(string)
  default     = []
}

variable "webserver_ssh_access_ipv6_cidr_blocks" {
  description = "The optional IPv6 CIDR block for ssh access to the webserver instances"
  type        = list(string)
  default     = []
}

variable "webserver_min_instances" {
  description = "The minimum number of instances in the autoscaling group"
  type        = number
  default     = 1
}

variable "webserver_max_instances" {
  description = "The maximum number of instances in the autoscaling group"
  type        = number
  default     = 1
}

variable "webserver_desired_instances" {
  description = "The desired number of instances in the autoscaling group"
  type        = number
  default     = 1
}

variable "webserver_healthcheck_path" {
  description = "The URL path to hit in the webserver instances for healthcheck"
  type        = string
  default     = "/"
}
