variable "default_tags" {
  type = map(string)
  default = {
    "user:Generator" = "lindsor/opentofu"
  }

}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      var.global_tags,
      var.default_tags
    )
  }
}

# AWS certificates must be created in us-east-1 to work
provider "aws" {
  alias  = "us_east_1_provider"
  region = "us-east-1"
}

resource "aws_s3_bucket" "static_website_bucket" {
  bucket = var.bucket_name

  force_destroy = var.should_force_destroy

  tags = {}
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "static-website-oac"
  description                       = "OAC for static website"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "default_response_header" {
  name = "DefaultResponseHeaderBehavior"

  custom_headers_config {
    items {
      header   = "X-Robots-Tag"
      value    = var.allow_seo_index ? "index,follow" : "noindex,nofollow"
      override = true
    }
  }
}

# TODO: Add cache headers
resource "aws_cloudfront_distribution" "website_cdn" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = var.public_domains

  origin {
    domain_name              = aws_s3_bucket.static_website_bucket.bucket_regional_domain_name
    origin_id                = "s3-static-website-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  #  Because of angular routing we throw 200 status even on error so angular routing can take effect
  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 300
  }

  #  Because of angular routing we throw 200 status even on error so angular routing can take effect
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 300
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-static-website-origin"

    viewer_protocol_policy = "redirect-to-https"

    response_headers_policy_id = aws_cloudfront_response_headers_policy.default_response_header.id

    forwarded_values {
      query_string = "false"

      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cloudfront_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {}

  # We need to wait for the certificates to be valid before updating cloudfront
  depends_on = [aws_acm_certificate_validation.cloudfront_cert_validation]
}


resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.static_website_bucket.id

  policy = core::jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Cloudfront read access for website serving
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly",
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action   = "s3:GetObject",
        Resource = "${aws_s3_bucket.static_website_bucket.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website_cdn.arn
          }
        }
      },
      # IAM user/role upload access
      # TODO: use IAM policy instead to allow upload
      {
        Sid    = "AllowUserUpload",
        Effect = "Allow",
        Principal = {
          AWS = var.uploader_arn,
        },
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
        ],
        Resource = "${aws_s3_bucket.static_website_bucket.arn}/*",
      }
    ]
  })
}

resource "aws_acm_certificate" "cloudfront_cert" {
  provider                  = aws.us_east_1_provider
  domain_name               = var.public_domains[0]
  validation_method         = "DNS"
  subject_alternative_names = slice(var.public_domains, 1, length(var.public_domains))

  lifecycle {
    create_before_destroy = true
  }
}

# Waits for all the cert validations so cloudfront doesnt fail
resource "aws_acm_certificate_validation" "cloudfront_cert_validation" {
  provider        = aws.us_east_1_provider
  certificate_arn = aws_acm_certificate.cloudfront_cert.arn
  validation_record_fqdns = [
    for dvo in aws_acm_certificate.cloudfront_cert.domain_validation_options : dvo.resource_record_name
  ]
}
