output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.website_cdn.domain_name
}

output "bucket_name" {
  value = aws_s3_bucket.static_website_bucket.id
}

# Outputs the CNAMEs you need to add manually to your DNS
output "acm_dns_validation_records" {
  description = "The ACM validation DNS records that must be created for AWS to accept the certificates"
  value = [
    for dvo in aws_acm_certificate.cloudfront_cert.domain_validation_options : {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  ]
}

output "public_domains" {
  value = var.public_domains
}
