# Lets terraform run locally against the S3 state backend without an AWS SSO
# login. A cluster ServiceAccount token is exchanged for temporary credentials
# through the OIDC provider in aws_iam_roles.tf - the same IRSA path the ACK and
# toolhive roles use, except the token is minted by `kubectl create token`
# instead of projected into a pod. The local credential is therefore the Talos
# admin client cert already in the kubeconfig; no AWS access key exists on disk.
#
# The Kubernetes side is kubernetes/apps/pitower/system/terraform-state/.
# Wire it up with scripts/aws-oidc-credential-process.sh.

locals {
  # Only the stacks that use no AWS provider. `terraform/proxmox` and
  # `terraform/unifi` touch AWS purely as a state backend, so state access is
  # all they need to run start to finish. `bootstrap`, `general`, `alexa` and
  # `loadtest` manage real AWS resources and are deliberately NOT covered -
  # granting those would hand every cluster-admin the god-mode policy below.
  terraform_state_keys = ["proxmox.tfstate", "unifi.tfstate"]
}

data "aws_iam_policy_document" "terraform_state_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.kubernetes_oidc.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${aws_iam_openid_connect_provider.kubernetes_oidc.url}:sub"
      values   = ["system:serviceaccount:system:terraform-state"]
    }

    # Pinning aud matters as much as sub here: without it any token this
    # issuer signs for any audience would satisfy the trust policy.
    condition {
      test     = "StringEquals"
      variable = "${aws_iam_openid_connect_provider.kubernetes_oidc.url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "terraform_state" {
  name               = "${local.name}-terraform-state"
  description        = "Local terraform state access via cluster OIDC, no SSO"
  assume_role_policy = data.aws_iam_policy_document.terraform_state_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "terraform_state" {
  # The s3 backend lists the bucket to discover workspaces. Metadata only.
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  # The trailing wildcard covers `<key>.tflock`, which is where `use_lockfile`
  # takes the state lock - without it every plan fails at lock acquisition
  # rather than at read.
  statement {
    sid    = "ReadWriteOwnState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      for key in local.terraform_state_keys :
      "${aws_s3_bucket.state.arn}/${key}*"
    ]
  }
}

resource "aws_iam_role_policy" "terraform_state" {
  name   = "${local.name}-terraform-state"
  role   = aws_iam_role.terraform_state.id
  policy = data.aws_iam_policy_document.terraform_state.json
}

output "terraform_state_role_arn" {
  description = "Role ARN for scripts/aws-oidc-credential-process.sh"
  value       = aws_iam_role.terraform_state.arn
}
