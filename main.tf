provider "aws" {
    region = "eu-west-1"
}

resource "aws_s3_bucket" "frontend_bucket" {
    bucket = "me-frontend-bucket"
    acl = "public-read"

    website {
        index_document = "index.html"
        error_document = "index.html"
    }
}


resource "aws_s3_bucket_object" "frontend_app" {
    for_each = fileset("${path.module}/../me.frontend/build", "**/*")

    bucket = aws_s3_bucket.frontend_bucket.bucket
    key = each.value
    source = "${path.module}/../me.frontend/build/${each.value}"
    etag   = filemd5("${path.module}/../me.frontend/build/${each.value}")
    content_type = mime_type(each.value)
}

output "bucket_url" {
  value = aws_s3_bucket.frontend_bucket.website_endpoint
}

resource "aws_cloudfront_distribution" "cdn" {
   origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.frontend_bucket.id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_access_identity.cloudfront_access_identity_path
    }
   }

    enabled             = true
    is_ipv6_enabled     = true
    default_root_object = "index.html"

    default_cache_behavior {
        allowed_methods  = ["GET", "HEAD", "OPTIONS"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = aws_s3_bucket.frontend_bucket.id

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
        cloudfront_default_certificate = true
    }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Access identity for S3 bucket"
}