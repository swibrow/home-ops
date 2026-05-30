# URL must exactly match the kube-apiserver service-account-issuer (Talos
# controlplane.patch) and the static discovery doc published in this repo at
# pitower/kubernetes/.well-known/openid-configuration.
data "tls_certificate" "kubernetes_oidc" {
  url = "https://raw.githubusercontent.com/swibrow/home-ops/main/pitower/kubernetes"
}

resource "aws_iam_openid_connect_provider" "kubernetes_oidc" {
  url             = "https://raw.githubusercontent.com/swibrow/home-ops/main/pitower/kubernetes"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.kubernetes_oidc.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "pitower_test" {
  name = "pitower"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : [
            aws_iam_openid_connect_provider.kubernetes_oidc.arn
          ]
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "${aws_iam_openid_connect_provider.kubernetes_oidc.url}:sub" : "system:serviceaccount:test:pitower-test",
            "${aws_iam_openid_connect_provider.kubernetes_oidc.url}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "pitower_test_policy" {
  name = "pitower-test"
  role = aws_iam_role.pitower_test.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:ListAllMyBuckets"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "pitower_test_attachment" {
  role       = aws_iam_role.pitower_test.name
  policy_arn = aws_iam_policy.additional.arn
}
