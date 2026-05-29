################################################################################
# VolSync Backup Bucket
################################################################################

resource "aws_s3_bucket" "volsync" {
  bucket = "${local.name}-volsync-backups"
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "volsync" {
  bucket = aws_s3_bucket.volsync.id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "volsync" {
  bucket = aws_s3_bucket.volsync.id

  # Move objects into Intelligent-Tiering immediately. AWS then auto-tiers
  # untouched data to cheaper instant-access tiers (Infrequent after 30d,
  # Archive Instant Access after 90d) with no retrieval fees and no
  # early-deletion penalty, so restic's weekly prune stays cheap and safe.
  rule {
    id     = "intelligent-tiering"
    status = "Enabled"

    filter {}

    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }
  }

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "volsync" {
  bucket                  = aws_s3_bucket.volsync.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "volsync" {
  bucket = aws_s3_bucket.volsync.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

################################################################################
# IAM User for VolSync
################################################################################

resource "aws_iam_user" "volsync" {
  name = "${local.name}-volsync"
  tags = local.tags
}

resource "aws_iam_access_key" "volsync" {
  user = aws_iam_user.volsync.name
}

resource "aws_iam_user_policy" "volsync" {
  name = "${local.name}-volsync"
  user = aws_iam_user.volsync.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.volsync.arn,
          "${aws_s3_bucket.volsync.arn}/*",
        ]
      },
    ]
  })
}
