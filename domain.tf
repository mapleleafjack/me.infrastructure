resource "aws_route53_zone" "main_zone" {
  name = "jackmusajo.it"
}

resource "aws_route53_record" "www_frontend" {
  zone_id = aws_route53_zone.main_zone.zone_id
  name    = "www.jackmusajo.it"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }

  depends_on = [aws_cloudfront_distribution.cdn]
}

resource "aws_route53_record" "backend" {
  zone_id = aws_route53_zone.main_zone.zone_id
  name    = "backend.jackmusajo.it"
  type    = "A"

  alias {
    name                   = aws_lb.backend_lb.dns_name
    zone_id                = aws_lb.backend_lb.zone_id
    evaluate_target_health = false
  }

  depends_on = [aws_lb.backend_lb]
}

resource "aws_acm_certificate" "www_certificate" {
  provider          = aws.us_east_1 # Use the us-east-1 provider alias
  domain_name       = "www.jackmusajo.it"
  validation_method = "DNS"

  tags = {
    Name = "www.jackmusajo.it SSL Certificate"
  }
}

resource "aws_route53_record" "www_certificate_validation" {
  for_each = {
    for dvo in aws_acm_certificate.www_certificate.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.main_zone.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "www_certificate" {
  provider                = aws.us_east_1 # Explicitly use us-east-1
  certificate_arn         = aws_acm_certificate.www_certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.www_certificate_validation : record.fqdn]

  depends_on = [aws_acm_certificate.www_certificate, aws_route53_record.www_certificate_validation] # Ensures validation happens after certificate creation and DNS record creation
}

output "acm_certificate_arn" {
  value = aws_acm_certificate.www_certificate.arn
}