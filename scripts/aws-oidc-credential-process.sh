#!/usr/bin/env bash
# AWS credential_process backed by a Kubernetes ServiceAccount token.
#
# Mints a short-lived SA JWT with `kubectl create token`, trades it for
# temporary AWS credentials through the cluster's IAM OIDC provider, and prints
# them in the credential_process JSON format. No AWS access key is stored
# anywhere; the local credential is the kubeconfig's Talos admin client cert.
#
# ~/.aws/config:
#
#   [profile pitower-tf]
#   credential_process = /path/to/scripts/aws-oidc-credential-process.sh --role-arn arn:aws:iam::<acct>:role/pitower-terraform-state
#   region = eu-central-2
#
# The role ARN is a flag rather than a default in here so this file stays
# account-agnostic. Terraform prints it as `terraform_state_role_arn`.
set -euo pipefail

CONTEXT="admin@pitower"
NAMESPACE="system"
SERVICE_ACCOUNT="terraform-state"
AUDIENCE="sts.amazonaws.com"
SESSION_NAME="local-terraform"
DURATION_SECONDS=3600
ROLE_ARN="${AWS_OIDC_ROLE_ARN:-}"
REGION="${AWS_REGION:-eu-central-2}"

die() {
  echo "aws-oidc-credential-process: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role-arn) ROLE_ARN="${2:-}"; shift 2 ;;
    --context) CONTEXT="${2:-}"; shift 2 ;;
    --namespace) NAMESPACE="${2:-}"; shift 2 ;;
    --service-account) SERVICE_ACCOUNT="${2:-}"; shift 2 ;;
    --session-name) SESSION_NAME="${2:-}"; shift 2 ;;
    --duration-seconds) DURATION_SECONDS="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$ROLE_ARN" ]] || die "no role ARN: pass --role-arn or set AWS_OIDC_ROLE_ARN"

for tool in kubectl aws jq; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not on PATH"
done

# The SA token only has to survive the round trip to STS; the AWS session length
# is set by --duration-seconds and is independent of it.
token=$(kubectl --context="$CONTEXT" create token "$SERVICE_ACCOUNT" \
  --namespace "$NAMESPACE" \
  --audience "$AUDIENCE" \
  --duration 10m) ||
  die "could not mint a token for $NAMESPACE/$SERVICE_ACCOUNT in context $CONTEXT"

# --no-sign-request is load-bearing, not tidiness. AssumeRoleWithWebIdentity is
# an unauthenticated call, but without this flag the CLI still resolves a
# credential chain first - which lands back on this very profile and recurses
# until it fails with a confusing credential error instead of calling STS.
creds=$(aws sts assume-role-with-web-identity \
  --role-arn "$ROLE_ARN" \
  --role-session-name "$SESSION_NAME" \
  --web-identity-token "$token" \
  --duration-seconds "$DURATION_SECONDS" \
  --region "$REGION" \
  --no-sign-request \
  --output json) ||
  die "STS rejected the token (check the role trust policy's sub and aud)"

jq -c '{
  Version: 1,
  AccessKeyId: .Credentials.AccessKeyId,
  SecretAccessKey: .Credentials.SecretAccessKey,
  SessionToken: .Credentials.SessionToken,
  Expiration: .Credentials.Expiration,
}' <<<"$creds"
