provider "aws" {
  region = "eu-west-1" # Your default region for other resources
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1" # This provider is specifically for ACM in us-east-1
}

# S3 Bucket for Frontend
resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "me-frontend-bucket"
}

# Versioning on the S3 bucket to prevent accidental deletions
resource "aws_s3_bucket_versioning" "frontend_bucket_versioning" {
  bucket = aws_s3_bucket.frontend_bucket.bucket

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket for CloudFront Logs (in eu-west-1)
resource "aws_s3_bucket" "cloudfront_logs_bucket" {
  bucket = "me-frontend-cloudfront-logs"
}

# Apply the ACL using aws_s3_bucket_acl
resource "aws_s3_bucket_acl" "cloudfront_logs_acl" {
  bucket = aws_s3_bucket.cloudfront_logs_bucket.id
  acl    = "log-delivery-write"
}

# CloudFront Origin Access Identity (OAI)
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Access identity for S3 bucket"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id   = "S3-Frontend-Origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = ["www.jackmusajo.it"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Frontend-Origin"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.www_certificate.arn # Use ACM certificate ARN directly
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    bucket = aws_s3_bucket.cloudfront_logs_bucket.bucket_domain_name
    include_cookies = false
    prefix = "frontend-logs/"
  }

  depends_on = [aws_acm_certificate_validation.www_certificate] # Ensure validation is complete first
}

# S3 Bucket Policy for CloudFront OAI
resource "aws_s3_bucket_policy" "frontend_bucket_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PublicReadGetObject"
        Effect = "Allow"
        Principal = {
          AWS = "${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend_bucket.arn}/*"
      },
    ]
  })
}

resource "aws_s3_bucket_policy" "cloudfront_logs_bucket_policy" {
  bucket = aws_s3_bucket.cloudfront_logs_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action = "s3:PutObject",
        Resource = "${aws_s3_bucket.cloudfront_logs_bucket.arn}/*"
      }
    ]
  })
}


# Output the CloudFront Distribution URL
output "cloudfront_url" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

# Output the CloudFront Distribution ID
output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.cdn.id
}

# Output for the logs bucket
output "cloudfront_logs_bucket" {
  value = aws_s3_bucket.cloudfront_logs_bucket.bucket_domain_name
}