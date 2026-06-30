locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project
    Workload    = "web-app"
    Owner       = "contoso-team"
    CostCenter  = "infra"
  }
}

# ---------------------------------------------------------------------------
# FRONTEND BUCKET
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "frontend" {
  bucket        = var.frontend_bucket_name
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = var.frontend_bucket_name
  })
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# ASSETS BUCKET (provisioned empty for future use)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "assets" {
  bucket = var.assets_bucket_name

  tags = merge(local.common_tags, {
    Name = var.assets_bucket_name
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# CLOUDFRONT ORIGIN ACCESS CONTROL (OAC)
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "contoso-frontend-oac"
  description                       = "OAC for Contoso frontend S3 bucket — allows CloudFront to read SPA assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------------------------------------------------------------------------
# FRONTEND BUCKET POLICY — allow CloudFront OAC to read objects
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  # Depends on the public-access block being applied first so the policy
  # isn't rejected while the bucket still allows public ACLs.
  depends_on = [aws_s3_bucket_public_access_block.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOACGetObject"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.web.arn
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# CLOUDFRONT DISTRIBUTION
# ---------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  comment             = "Contoso Financial web distribution — ${var.environment}"

  # ------------------------------------------------------------------
  # Origin: frontend S3 bucket (via OAC)
  # ------------------------------------------------------------------
  origin {
    origin_id                = "frontend-s3"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # ------------------------------------------------------------------
  # Origin: API load balancer
  # Coupling C1 resolution: CloudFront /api/* → ALB so the SPA can
  # keep calling /api/* without CORS or frontend code changes even
  # after the SPA is decoupled from the Docker network.
  # ------------------------------------------------------------------
  origin {
    origin_id   = "web-api-alb"
    domain_name = var.alb_dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ------------------------------------------------------------------
  # Default behaviour: serve SPA from S3
  # ------------------------------------------------------------------
  default_cache_behavior {
    target_origin_id       = "frontend-s3"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  # ------------------------------------------------------------------
  # Ordered behaviour: proxy /api/* to ALB with zero caching
  # All headers, cookies and query strings are forwarded so the
  # Spring Boot API receives the full original request.
  # ------------------------------------------------------------------
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "web-api-alb"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0

    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }
  }

  # ------------------------------------------------------------------
  # SPA routing fallback: 403/404 from S3 → 200 /index.html
  # Vue Router history-mode routes are handled client-side; S3 returns
  # 403 (access denied for missing key) or 404, both mapped here.
  # ------------------------------------------------------------------
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.common_tags, {
    Name = "contoso-web-cloudfront-${var.environment}"
  })
}
