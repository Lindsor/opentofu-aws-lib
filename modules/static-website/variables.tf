variable "aws_region" {
  description = "The AWS region to deploy all resources"
  type        = string
}

variable "bucket_name" {
  description = "The globally unique name for the bucket"
  type        = string
}

variable "global_tags" {
  description = "Tags that will be applied to every resource that supports tagging"
  type        = map(string)
  default     = {}
}
