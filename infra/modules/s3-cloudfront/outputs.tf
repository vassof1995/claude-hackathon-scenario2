output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution (use this as the public URL for the SPA)"
  value       = aws_cloudfront_distribution.web.domain_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution (used for cache invalidations)"
  value       = aws_cloudfront_distribution.web.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution (referenced in the S3 bucket policy OAC condition)"
  value       = aws_cloudfront_distribution.web.arn
}

output "frontend_bucket_name" {
  description = "Name (id) of the S3 bucket that hosts the Vue SPA assets"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  description = "ARN of the frontend S3 bucket"
  value       = aws_s3_bucket.frontend.arn
}

output "assets_bucket_name" {
  description = "Name (id) of the assets S3 bucket (provisioned empty for future use)"
  value       = aws_s3_bucket.assets.id
}

output "assets_bucket_arn" {
  description = "ARN of the assets S3 bucket"
  value       = aws_s3_bucket.assets.arn
}
