#!/usr/bin/env bash
# Garbage-collect abandoned restic repositories from the volsync S3 bucket.
#
# Each app backs up to its own repo at  s3://$BUCKET/<namespace>/<app>  and,
# while active, writes new objects every hour. So:
#   * the live set = "<namespace>/<name>" for every ReplicationSource, and
#   * an abandoned repo's newest object is frozen at the moment its app was removed.
# A repo is deleted only if it is NOT in the live set AND its newest object is
# older than $GRACE_DAYS. Active repos are therefore structurally safe even if
# their data hasn't changed in months.
#
# DRY_RUN=true (default) only logs what it WOULD delete. Flip to "false" to arm.
set -euo pipefail

BUCKET=${BUCKET:?BUCKET is required}
GRACE_DAYS=${GRACE_DAYS:-7}
DRY_RUN=${DRY_RUN:-true}
KUBECTL=${KUBECTL:-kubectl}

now=$(date -u +%s)
grace_seconds=$((GRACE_DAYS * 86400))

echo "volsync-gc: bucket=$BUCKET grace=${GRACE_DAYS}d dry_run=$DRY_RUN"

# Live repos: "<namespace>/<name>" for every ReplicationSource in the cluster.
active=$("$KUBECTL" get replicationsource --all-namespaces \
  -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' | sort -u)
echo "------ active repositories ------"
echo "${active:-<none>}"
echo "--------------------------------"

# Walk the two-level <category>/<app>/ prefixes that hold restic repos.
mapfile -t categories < <(aws s3api list-objects-v2 --bucket "$BUCKET" --delimiter / \
  --query 'CommonPrefixes[].Prefix' --output text | tr '\t' '\n' | sed '/^$/d')

deleted=0 kept=0
for category in "${categories[@]}"; do
  mapfile -t apps < <(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$category" --delimiter / \
    --query 'CommonPrefixes[].Prefix' --output text | tr '\t' '\n' | sed '/^$/d')
  for app in "${apps[@]}"; do
    repo="${app%/}" # e.g. selfhosted/mealie

    if grep -qxF "$repo" <<<"$active"; then
      echo "KEEP   $repo (active)"
      kept=$((kept + 1))
      continue
    fi

    newest=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$app" \
      --query 'sort_by(Contents,&LastModified)[-1].LastModified' --output text)
    if [ -z "$newest" ] || [ "$newest" = "None" ]; then
      echo "KEEP   $repo (no objects)"
      kept=$((kept + 1))
      continue
    fi

    idle=$((now - $(date -u -d "$newest" +%s)))
    age_days=$((idle / 86400))
    if [ "$idle" -le "$grace_seconds" ]; then
      echo "KEEP   $repo (orphan, only ${age_days}d idle < ${GRACE_DAYS}d grace)"
      kept=$((kept + 1))
      continue
    fi

    if [ "$DRY_RUN" = "true" ]; then
      echo "WOULD DELETE  $repo (orphan, ${age_days}d idle)"
    else
      echo "DELETE $repo (orphan, ${age_days}d idle)"
      aws s3 rm "s3://$BUCKET/$app" --recursive
    fi
    deleted=$((deleted + 1))
  done
done

echo "volsync-gc: done. kept=$kept deleted$([ "$DRY_RUN" = "true" ] && echo "(would)")=$deleted"
