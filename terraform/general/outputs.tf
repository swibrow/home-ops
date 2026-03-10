################################################################################
# VolSync
################################################################################

output "volsync_bucket_name" {
  description = "S3 bucket name for VolSync backups"
  value       = aws_s3_bucket.volsync.id
}

output "volsync_bucket_region" {
  description = "S3 bucket region for VolSync backups"
  value       = aws_s3_bucket.volsync.region
}

output "volsync_access_key_id" {
  description = "Access key ID for VolSync IAM user"
  value       = aws_iam_access_key.volsync.id
  sensitive   = true
}

output "volsync_secret_access_key" {
  description = "Secret access key for VolSync IAM user"
  value       = aws_iam_access_key.volsync.secret
  sensitive   = true
}
