################################################################################
# Shared IRSA role for the AWS Controllers for Kubernetes (ACK) controllers.
#
# A single "admin-ish" role assumed by every ACK controller running in the
# `ack-system` namespace on pitower (deployed via the ack-chart umbrella at
# kubernetes/apps/pitower/ack-system/ack-controllers). Each controller's
# ServiceAccount is named `ack-<service>-controller`; the trust policy below
# uses a StringLike on the OIDC `sub` so ONLY those controller ServiceAccounts
# can assume the role — nothing else in the cluster, and no human/GitHub path.
#
# The OIDC provider is created in terraform/bootstrap and looked up via the
# shared data source in volsync.tf.
#
# BLAST RADIUS: the permissions policy is broad (service-wildcard on the set of
# services we run controllers for, INCLUDING iam:*). iam:* means a compromised
# iam-controller could create privileged roles. This is the price of running the
# ACK iam-controller; tighten to specific actions/resources if that tradeoff
# stops being acceptable.
################################################################################

resource "aws_iam_role" "ack_controllers" {
  name = "${local.name}-ack-controllers"
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
            "${replace(data.aws_iam_openid_connect_provider.kubernetes.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${replace(data.aws_iam_openid_connect_provider.kubernetes.url, "https://", "")}:sub" = "system:serviceaccount:ack-system:ack-*-controller"
          }
        }
      },
    ]
  })
}

# Broad, service-scoped permissions for the controllers we enable. This is
# deliberately wide ("create most things") but limited to the AWS services we
# actually run controllers for, rather than AdministratorAccess.
resource "aws_iam_role_policy" "ack_controllers" {
  name = "${local.name}-ack-controllers"
  role = aws_iam_role.ack_controllers.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AckServiceAccess"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "route53:*",
          "iam:*",
          "s3:*",
          "dynamodb:*",
          "rds:*",
          "cloudfront:*",
          "acm:*",
          "elasticloadbalancing:*",
          "sqs:*",
          "sns:*",
          "secretsmanager:*",
          "kms:*",
        ]
        Resource = "*"
      },
      {
        Sid    = "AckTagging"
        Effect = "Allow"
        Action = [
          "tag:GetResources",
          "tag:TagResources",
          "tag:UntagResources",
        ]
        Resource = "*"
      },
    ]
  })
}

output "ack_controllers_role_arn" {
  value = aws_iam_role.ack_controllers.arn
}
