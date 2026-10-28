output "org_trail_bucket_name" {
  description = "S3 bucket in log-archive holding the organization CloudTrail logs."
  value       = aws_s3_bucket.org_trail.bucket
}

output "org_trail_arn" {
  description = "ARN of the organization CloudTrail trail."
  value       = aws_cloudtrail.org.arn
}
