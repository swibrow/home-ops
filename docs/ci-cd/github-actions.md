# GitHub Actions

GitHub Actions workflows in `.github/workflows/`. Third-party actions are pinned to commit SHAs, and Renovate keeps the pins current.

---

## Workflows

| Workflow | File | Trigger | Runner |
|:---------|:-----|:--------|:-------|
| Checks | `checks.yaml` | Every PR to `main` | `home-ops` |
| ArgoCD Diff | `argocd-diff.yaml` | PR touching `kubernetes/**` | `home-ops` |
| Talos Diff | `talos-diff.yaml` | PR touching `talos/**` | `home-ops` |
| Talos Apply | `talos-apply.yaml` | Push to `main` touching `talos/**`, or manual | `home-ops` |
| Terraform Plan | `terraform-plan.yaml` | PR touching `terraform/{alexa,garrison-alexa,bootstrap,general}/**` | `ubuntu-latest` |
| Terraform Apply | `terraform-apply.yaml` | Push to `main` touching the same stacks | `home-ops` |
| Terraform UniFi | `terraform-unifi.yaml` | PR or push touching `terraform/unifi/**`, or manual | `home-ops` |
| Build Docker Images | `build-docker-images.yaml` | Push to `main` touching `docker/**`, or manual | `home-ops`, `home-ops-arm64` |
| Deploy Docs | `deploy-docs.yml` | Push to `main` touching `docs/**`, `site/**`, `images/**` or the workflow, or manual | `home-ops` |
| krr-rightsize | `krr-rightsize.yaml` | Mondays 06:00 UTC, or manual | `home-ops` |
| rightsize-report | `rightsize-report.yaml` | Tuesdays 07:00 UTC, or manual | `home-ops` |
| Deploy Status Worker | `deploy-status-worker.yaml` | Manual only | `home-ops` |

---

## Runners

`home-ops` and `home-ops-arm64` are [Actions Runner Controller](https://github.com/actions/actions-runner-controller) scale sets defined in `kubernetes/apps/pitower/arc/runners/` (controller in `arc/controller/`). The same file defines scale sets for other personal repositories.

| Scale set | Nodes | Image | Notes |
|:----------|:------|:------|:------|
| `home-ops` | worker-07 (`wibrow.dev/compute: "true"`) | `ghcr.io/cloudsnacks/actions-runner` | Ships actionlint, tflint and other CLIs via mise; Docker-in-Docker sidecar; work volumes on `openebs-hostpath-runners` |
| `home-ops-arm64` | Raspberry Pi workers (worker-08/09/10, `kubernetes.io/arch: arm64`) | `ghcr.io/cloudsnacks/actions-runner` | Used only for native linux/arm64 image builds |

Scale sets start at zero runners (`minRunners: 0`) and are capped by `maxRunners`.

> [!WARNING]
> **Runners live on worker-07**
>
> While worker-07 is drained or down, jobs on `home-ops` stay queued. Run `terraform` or `topf` locally instead. Talos Apply runs inside the cluster it is applying to, so a change that reboots worker-07 kills its own job; re-run the workflow or finish with `topf apply` locally.

---

## Checks

The required status check. It has no path filter so it reports on every PR.

1. `actionlint`
2. `pre-commit/action` with the hooks in `.pre-commit-config.yaml`: end-of-file-fixer, trailing-whitespace, yamllint, terraform_fmt and terraform_tflint. `terraform_validate` is skipped because it needs `terraform init` per stack, which the Terraform workflows already do.

`MISE_IGNORED_CONFIG_PATHS` is set so the runner's mise shims do not try to decrypt the repo's age-encrypted `[env]` values.

---

## ArgoCD Diff

Uses [drydock](https://github.com/sholdee/drydock)'s `pr-action` to render the Kustomize/Helm output of changed apps under `kubernetes/` on both the PR head and the base branch, and comments the diff on the PR. Changes only to `.github/**`, `terraform/**`, `docs/**` or `*.md` do not trigger a full render.

---

## Talos Diff and Talos Apply

Both detect which `talos/<cluster>/` directories changed and run a matrix over them:

1. Install [topf](https://github.com/postfinance/topf) and sops (versions pinned with Renovate annotations).
2. Write the `AGE_SECRET_KEY` secret to a temp file and export `SOPS_AGE_KEY_FILE`.
3. **Diff**: `topf apply --dry-run --redact`; exit code 2 means changes are pending. The output is posted as a sticky PR comment (one per cluster, found by an HTML marker).
4. **Apply**: `topf apply --redact` with `TOPF_CONFIRM=false`, serialised per cluster with a concurrency group. A manual run can pass an explicit JSON list of clusters.

`--redact` keeps secret values out of logs and comments, since the repository is public.

---

## Terraform

**Terraform Plan** and **Terraform Apply** run a matrix over the `alexa`, `garrison-alexa`, `bootstrap` and `general` stacks with [dflook/terraform-plan](https://github.com/dflook/terraform-github-actions) and `terraform-apply` (`auto_approve: true`). AWS credentials come from OIDC (`AWS_OIDC_ROLE_ARN`, region `eu-central-2`).

**Terraform UniFi** is separate because the UniFi provider talks to the gateway's local API, which only the in-cluster runner can reach. It:

- decrypts `UNIFI_*` credentials from `terraform/mise.toml` with mise and the age key,
- checks the UniFi API is reachable before planning,
- plans on PRs, applies on push to `main`,
- offers a manual `unlock` action to release a stale S3 state lock left by a killed run.

Plans and applies share one concurrency group (`terraform-unifi`) because they share the state lock.

---

## Build Docker Images

See [Docker Builds](docker-builds.md).

---

## Deploy Docs

```yaml title=".github/workflows/deploy-docs.yml (abridged)"
jobs:
  build:
    runs-on: home-ops
    defaults:
      run:
        working-directory: site
    steps:
      - uses: actions/checkout@<sha> # v7.0.1
        with:
          fetch-depth: 0
      - uses: oven-sh/setup-bun@<sha> # v2.2.0
      - run: bun install --frozen-lockfile
      - run: bun run build
      - uses: actions/upload-pages-artifact@<sha> # v5.0.0
        with:
          path: site/dist
  deploy:
    needs: build
    runs-on: home-ops
    permissions:
      pages: write
      id-token: write
    environment: github-pages
    steps:
      - uses: actions/deploy-pages@<sha> # v5.0.1
```

- `bun run build` runs `astro build`, indexes the output with Pagefind, then fails on any internal link or anchor that does not resolve
- `fetch-depth: 0` gives each page its "last updated" date from git
- `actions/deploy-pages` publishes the artifact; the repository's Pages source is "GitHub Actions"

---

## krr-rightsize

Weekly right-sizing PR:

1. Runs [KRR](https://github.com/robusta-dev/krr) `simple` against the in-cluster Prometheus with `--cpu_percentile 50`.
2. `scripts/krr_rightsize.py` writes CPU requests at p50 and memory requests at the trailing average working set into `kubernetes/apps/pitower`. Limits are not touched.
3. Force-pushes the result to the long-lived `bot/krr-rightsize` branch and opens a PR labelled `automation` if none is open.

app-template values are matched automatically; other charts are only patched where a `# krr: <workload>/<container>` marker annotates the resources block.

---

## rightsize-report

Runs `scripts/rightsize_report.py` weekly and upserts a single open issue labelled `rightsize-report` ("Cluster right-sizing report").

---

## Deploy Status Worker

Builds, tests and deploys the Cloudflare Worker in `workers/status` (`status.wibrow.dev`) with Bun and Wrangler. It is manual only, deliberately: the Worker route cannot bind the hostname while external-dns still owns a record for it.
