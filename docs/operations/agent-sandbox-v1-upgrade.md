---
title: Agent Sandbox v1.0.0 Upgrade
---

# Agent Sandbox v1.0.0 Upgrade

`kubernetes-sigs/agent-sandbox` v1.0.0 removes the `v1alpha1` API and the
conversion webhook that backed it. The CRDs now serve `v1beta1` only.

Two consequences drive this runbook:

- The kube-apiserver refuses to remove a version that still appears in a CRD's
  `status.storedVersions`. Every agent-sandbox CRD in `pitower` still lists
  `v1alpha1` there, so applying the v1.0.0 CRDs **fails** until the stored
  records are rewritten and the list pruned.
- Clients that write `v1alpha1` object shapes break. `SandboxClaim` is not
  field-compatible (`sandboxTemplateRef` + `warmpool` became `warmPoolRef`), and
  `Sandbox.spec.replicas` became `Sandbox.spec.operatingMode`. Without the
  webhook nothing rewrites them; unknown fields are pruned and required fields
  come up missing.

## Order of operations

The client repos ship first, then the storage migration runs, then the operator
manifests merge. Argo CD auto-syncs `pitower-ai-agent-sandbox`, so merging the
home-ops PR is the point of no return.

1. Ship and deploy [flickerd](#flickerd) and [garrison](#garrison) on
   `v1beta1`. Both keep working against the v0.5.6 controller, which serves
   `v1beta1` already.
2. Run the [storage migration](#storage-migration) against the live cluster.
3. Merge the home-ops PR and let Argo CD sync.
4. Run the [post-upgrade cleanup](#post-upgrade-cleanup).

## Storage migration

Back up every CR first:

```shell
kubectl --context=admin@pitower get \
  sandboxes,sandboxclaims,sandboxtemplates,sandboxwarmpools \
  -A -o yaml > agent-sandbox-backup-$(date -u +%Y%m%dT%H%M%SZ).yaml
```

The `bootstrap` phase of upstream's `migrate.sh` does not apply here: it exists
to pre-create shadow warm pools *before* upgrading to v0.5.2, and pitower has
been on v0.5.x since v0.5.0. Only the rewrite phase is needed.

Rewriting means touching each object so the apiserver re-serialises it in
`v1beta1` form. Upstream's script stamps
`agents.x-k8s.io/storage-migrated-at`; the same annotation by hand works:

```shell
STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for kind in sandboxes.agents.x-k8s.io \
            sandboxclaims.extensions.agents.x-k8s.io \
            sandboxtemplates.extensions.agents.x-k8s.io \
            sandboxwarmpools.extensions.agents.x-k8s.io; do
  kubectl --context=admin@pitower annotate "${kind}" -A --all --overwrite \
    "agents.x-k8s.io/storage-migrated-at=${STAMP}"
done
```

Confirm nothing was missed, then prune `v1alpha1` from each CRD's
`storedVersions`:

```shell
kubectl --context=admin@pitower get \
  sandboxes,sandboxclaims,sandboxtemplates,sandboxwarmpools -A -o json \
  | jq -r '.items[] | select(.metadata.annotations["agents.x-k8s.io/storage-migrated-at"] == null)
      | "UNMIGRATED \(.kind) \(.metadata.namespace)/\(.metadata.name)"'

for crd in sandboxes.agents.x-k8s.io \
           sandboxclaims.extensions.agents.x-k8s.io \
           sandboxtemplates.extensions.agents.x-k8s.io \
           sandboxwarmpools.extensions.agents.x-k8s.io; do
  kubectl --context=admin@pitower patch crd "${crd}" \
    --subresource=status --type=merge \
    -p '{"status":{"storedVersions":["v1beta1"]}}'
done
```

Every CRD must report exactly `["v1beta1"]` before the home-ops PR merges:

```shell
kubectl --context=admin@pitower get crd \
  sandboxes.agents.x-k8s.io sandboxclaims.extensions.agents.x-k8s.io \
  sandboxtemplates.extensions.agents.x-k8s.io sandboxwarmpools.extensions.agents.x-k8s.io \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.storedVersions}{"\n"}{end}'
```

!!! warning "Prune only after the rewrite"
    Pruning `storedVersions` while a `v1alpha1`-serialised record is still in
    etcd makes that record unreadable. The unmigrated-object query above is the
    gate, not a formality.

## Post-upgrade cleanup

The webhook `Service`, `Role` and `RoleBinding` left the vendored manifests in
the same bump, so Argo CD prunes them. `Secret/agent-sandbox-webhook-certs` was
created by the controller, is not tracked in git, and outlives the sync:

```shell
kubectl --context=admin@pitower delete -n agent-sandbox-system \
  secret/agent-sandbox-webhook-certs --ignore-not-found
```

Three orphaned `SandboxClaim` objects sit in the `ai` namespace in
`InvalidMetadata` from a retired flickerd deployment. They predate the move of
flickerd into its own namespace and can go:

```shell
kubectl --context=admin@pitower delete sandboxclaims.extensions.agents.x-k8s.io -n ai --all
```

## Client changes

### flickerd

`src/generator/k8s.ts` created claims in the v1alpha1 shape and leaned on the
conversion webhook to rewrite them:

```yaml
spec:
  sandboxTemplateRef: { name: flickerd }   # gone in v1beta1
  warmpool: flickerd                       # gone in v1beta1
```

`v1beta1` requires `spec.warmPoolRef.name`. Both fields are now pruned on
write, so an unported flickerd creates claims that fail validation and every
generation job stalls waiting for a pod that never binds. The template is still
referenced — by `SandboxWarmPool.spec.sandboxTemplateRef` in
`kubernetes/apps/pitower/flickerd/flickerd/warmpool.yaml`, not by the claim.

### garrison

`packages/keep/src/` writes `Sandbox` CRs directly and defaults
`sandboxVersion` to `v1alpha1`. Hibernate, resume, shutdown and rez all patch
`spec.replicas` 0/1, which `v1beta1` replaces with
`spec.operatingMode: Suspended|Running`. `KEEP_SANDBOX_VERSION` can override the
group version at runtime, but the `replicas` patches are hardcoded, so the
override alone is not enough.

## Reference

- [v1.0.0 release notes](https://github.com/kubernetes-sigs/agent-sandbox/releases/tag/v1.0.0)
- [v1.0.0 API migration guide](https://github.com/kubernetes-sigs/agent-sandbox/blob/v1.0.0/docs/api-migration-guide.md)
- [v0.5.x API migration guide](https://github.com/kubernetes-sigs/agent-sandbox/blob/v0.5.6/docs/api-migration-guide.md)
