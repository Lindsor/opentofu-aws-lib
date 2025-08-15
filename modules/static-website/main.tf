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

resource "aws_s3_bucket" "static_website_bucket" {
  bucket = var.bucket_name

  tags = {}
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "static-website-oac"
  description                       = "OAC for static website"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "noindex_response_header" {
  count = var.allow_seo_index ? 0 : 1
  name  = "NoIndexHeader"

  custom_headers_config {
    items {
      header   = "X-Robots-Tag"
      value    = "noindex,nofollow"
      override = true
    }
  }
}

resource "aws_cloudfront_distribution" "website_cdn" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

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

    response_headers_policy_id = var.allow_seo_index ? null : aws_cloudfront_response_headers_policy.noindex_response_header[0].id

    forwarded_values {
      query_string = "false"

      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {}
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

