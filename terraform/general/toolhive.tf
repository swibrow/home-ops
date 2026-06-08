################################################################################
# IRSA role for the ToolHive AWS API MCP server (read-only).
#
# The MCPServer "aws-api" (namespace "ai", ServiceAccount "toolhive-aws-ro")
# runs the awslabs aws-api-mcp-server, which executes AWS CLI commands. It
# assumes this role via the amazon-eks-pod-identity-webhook using the cluster
# OIDC provider (created in terraform/bootstrap, looked up in volsync.tf).
#
# Read-only is enforced in two layers: READ_OPERATIONS_ONLY=true on the server
# (tool layer) AND the AWS-managed ReadOnlyAccess policy here (IAM layer). A
# future write endpoint would be a second role with write permissions bound to
# a different ServiceAccount.
################################################################################

resource "aws_iam_role" "toolhive_aws_ro" {
  name = "${local.name}-toolhive-aws-ro"
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
            "${replace(data.aws_iam_openid_connect_provider.kubernetes.url, "https://", "")}:sub" = "system:serviceaccount:ai:toolhive-aws-ro"
            "${replace(data.aws_iam_openid_connect_provider.kubernetes.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      },
    ]
  })
}

# Broad read-only across services. Swap for ViewOnlyAccess (metadata only, no
# object/data reads) or a scoped inline policy to tighten.
resource "aws_iam_role_policy_attachment" "toolhive_aws_ro" {
  role       = aws_iam_role.toolhive_aws_ro.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

output "toolhive_aws_ro_role_arn" {
  value = aws_iam_role.toolhive_aws_ro.arn
}
