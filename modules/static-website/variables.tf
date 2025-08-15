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

variable "uploader_arn" {
  description = "The ARN of the user allowed to upload to the S3 bucket"
  type        = string
}

variable "allow_seo_index" {
  description = "Whether the site should be indexable by SEO bots"
  type        = bool
}

variable "should_force_destroy" {
  description = "Whether to force detroy the stack. This will delete bucket even if theres items in it."
  type        = bool
  default     = false
}
