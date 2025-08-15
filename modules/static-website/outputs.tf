output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.website_cdn.domain_name
}

output "bucket_name" {
  value = aws_s3_bucket.static_website_bucket.id
}
