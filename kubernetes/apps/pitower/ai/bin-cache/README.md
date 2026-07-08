# bin-cache

Read-only, multi-pod binary cache for agent-sandbox pods, backed by the existing NFS export
`data:/volume1/nfs`. Holds a versioned matrix of arm64 CLI tools (`kubectl`, `helm`, `k9s`,
`argocd`, `kustomize`) laid out in mise's native `installs/<tool>/<version>/bin/<tool>` format,
dispatched at runtime by mise shims baked into the sandbox image. `tmux` is not served from here
— it's apt-installed directly in sandbox images (not a clean static binary, see
`docker/agent-sandbox-base/Dockerfile`).

## Populate vs. consume

- **Populate** (`cronjob-populate.yaml`): the only place with write access to the NFS share and
  the only place with egress. Two triggers running the identical logic (`mise install` against
  the committed `mise.toml`/`mise.lock`, verifying every download's checksum before writing):
  - `bin-cache-populate-postsync` — an ArgoCD `PostSync` hook `Job`, fires on **every sync**.
  - `bin-cache-populate` — a weekly `CronJob`, a redundant self-heal in case the NFS data is
    lost or the share gets re-provisioned without a corresponding git change.
- **Consume**: sandbox pods (e.g. `kubernetes/apps/pitower/ai/claude-code/sandbox.yaml`) mount
  the same NFS export **read-only** (`readOnly: true` on both the pod's `nfs` volume source —
  there is no PV/PVC here, see below) at `/mnt/nfs`, with `MISE_DATA_DIR=/mnt/nfs/bin-cache`.
  mise shims baked into the sandbox image at build time dispatch to whatever version is present
  under that directory — they never write to it.

## Adding a tool or version

1. Edit `mise.toml` in this directory (add a version to an existing tool's array, or add a new
   tool key).
2. Regenerate `mise.lock` locally: `mise lock -p linux-arm64` from this directory (requires
   network access to the tools' release endpoints — this is the one place checksums get
   fetched from upstream, kept out of the cluster).
3. Commit both files and push. ArgoCD syncs → the `PostSync` hook Job reruns → the new
   version lands on the NFS share. **No image rebuild.** Sandbox pods pick it up on their next
   pod start (mise resolves the version from the mounted `mise.toml` at runtime, not something
   baked into the image).
4. **Exception**: adding a version of a **brand-new tool name** (not already in the matrix)
   does need a sandbox image rebuild, because the image only has PATH shims (symlinks to the
   `mise` binary) pre-generated for the tool names present in the matrix at build time. A new
   patch/minor version of an *existing* tool never needs this.

## Why no PV/PVC

This repo has no NFS CSI driver and no static PV/PVC precedent anywhere — every existing NFS
mount (frigate/jellyfin/qbittorrent/radarr/sabnzbd/sonarr, via the bjw-s `app-template` chart's
`persistence.<name>.type: nfs`) is a plain inline pod-level `volumes[].nfs{server,path,readOnly}`
source, no PV/PVC/StorageClass involved. Since these are raw pod specs (agent-sandbox
`Sandbox`/`SandboxTemplate` CRDs), this app mirrors that same convention directly rather than
introducing PV/PVC machinery this repo has never used. `ReadOnlyMany`/`ReadWriteMany` access
modes don't apply here (they're a PVC-only concept) — the read-only guarantee comes entirely
from `readOnly: true` on the pod's own `nfs` volume source, which is why it must be set
explicitly on every consumer, not inherited from anything.

## exec / read-only invariants

- The mount is NFS, which is `exec` by default — no `noexec` mount option is ever added.
  `docker/agent-sandbox-base/verify-exec-mount.sh` (baked into sandbox images) fails loudly at
  container start if `mount | grep /mnt/nfs` ever shows `noexec`.
- Binaries are never staged through `emptyDir`/tmpfs or an OCI image volume (KEP-4639) — both
  are commonly mounted `noexec` and cannot execute binaries reliably.
- `MISE_CACHE_DIR`/`MISE_STATE_DIR` point at a tmpfs (`emptyDir: {}` in the populate Job;
  sandbox pods should use `emptyDir: {medium: Memory}`) since mise needs *some* writable
  scratch space even when `MISE_DATA_DIR` is read-only. Sandbox pods additionally set
  `MISE_NOT_FOUND_AUTO_INSTALL=false` so mise only ever *selects* an already-present version —
  it never attempts a download on the consume side.

## kubectl version skew

kubectl needs to stay within ±1 minor of whichever API server it's talking to, and the fleet
runs mixed minors (pitower `1.36.1`; auth/controller/pistack `1.35.5` as of 2026-07-08) — a
single pinned kubectl doesn't work fleet-wide. `docker/agent-sandbox-base/kubectl-wrapper.sh`
resolves the active kube-context's server minor and execs the matching cached binary, caching
the resolution per-context under `$MISE_CACHE_DIR` (tmpfs) so it costs one API round-trip per
context, not per invocation.

## Bootstrap note

`docker/agent-sandbox-base` is a new standalone image — on the very first push introducing it
alongside changes to another `docker/*` image that would want to `FROM` it, the build matrix
runs in parallel with no cross-job ordering, so a dependent image's build could fail if
`agent-sandbox-base`'s tag isn't published yet. None of the images in this app depend on each
other via `FROM` today (`claude-code-sandbox` has the same setup steps duplicated in, not
layered from, `agent-sandbox-base`) specifically to avoid this — keep it that way unless you
also split the rollout across two pushes.
