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

  # Versioning is suspended, so noncurrent versions and delete markers are pure
  # leftover waste from restic's churn. Expire them quickly, sweep stranded
  # delete markers, and abort incomplete multipart uploads (the volsync mover
  # leaves these behind when a backup fails partway, e.g. on a full cache PVC).
  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
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

################################################################################
# IRSA role for the volsync garbage-collector (CronJob in namespace "system").
# Assumed via the aws-identity-webhook using the cluster OIDC provider, which
# is created in the terraform/bootstrap state and looked up here by URL.
################################################################################

data "aws_iam_openid_connect_provider" "kubernetes" {
  url = "https://raw.githubusercontent.com/swibrow/home-ops/main/pitower/kubernetes"
}

resource "aws_iam_role" "volsync_gc" {
  name = "${local.name}-volsync-gc"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = data.aws_iam_openid_connect_provider.kubernetes.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_iam_openid_connect_provider.kubernetes.url, "https://", "")}:sub" = "system:serviceaccount:system:volsync-gc"
            "${replace(data.aws_iam_openid_connect_provider.kubernetes.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "volsync_gc" {
  name = "${local.name}-volsync-gc"
  role = aws_iam_role.volsync_gc.id

  # GC only needs to enumerate repositories and delete abandoned ones.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.volsync.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:DeleteObject"]
        Resource = "${aws_s3_bucket.volsync.arn}/*"
      },
    ]
  })
}

output "volsync_gc_role_arn" {
  value = aws_iam_role.volsync_gc.arn
}
