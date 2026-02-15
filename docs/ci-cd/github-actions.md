# GitHub Actions

GitHub Actions workflows for linting, Docker builds, and documentation deployment.

---

## Workflows

| Workflow | File | Trigger |
|:---------|:-----|:--------|
| Lint | `.github/workflows/lint.yaml` | Pull requests to `main` |
| Build Docker Images | `.github/workflows/build-docker-images.yaml` | Push to `main` (docker/**) or manual dispatch |
| Deploy Docs | `.github/workflows/deploy-docs.yml` | Push to `main` (docs/** or mkdocs.yml) |

---

## Lint Workflow

Runs on every pull request targeting the `main` branch. Validates code quality before merge.

```yaml title=".github/workflows/lint.yaml"
name: Linter

on:
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - run: |
          echo "Linting..."
```

!!! tip "Extending the Linter"
    This is a minimal linting skeleton. Add steps for YAML validation, Helm template checks, or shellcheck as needed.

---

## Build Docker Images Workflow

Automatically discovers changed Dockerfiles, extracts versions, and builds multi-architecture images. See [Docker Builds](docker-builds.md) for detailed documentation.

### Trigger

```yaml
on:
  push:
    branches: [main]
    paths:
      - docker/**
  workflow_dispatch:
```

- **Push**: Only triggers when files under `docker/` change on `main`
- **Manual dispatch**: Rebuilds all images regardless of changes

### Discovery Job

The `discover` job identifies which images need to be built:

```yaml
discover:
  runs-on: ubuntu-latest
  outputs:
    images: ${{ steps.set-matrix.outputs.images }}
  steps:
    - uses: actions/checkout@v4

    - id: changed
      if: github.event_name == 'push'
      uses: tj-actions/changed-files@v47
      with:
        dir_names: "true"
        dir_names_max_depth: "2"
        files: docker/**
        json: "true"
        escape_json: "false"

    - id: set-matrix
      run: |
        if [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
          echo "images=$(ls -d docker/*/ | xargs -I{} basename {} | \
            jq -R -s -c 'split("\n") | map(select(length > 0))')" >> "$GITHUB_OUTPUT"
        else
          echo "images=$(echo '${{ steps.changed.outputs.all_changed_files }}' | \
            jq -c '[.[] | ltrimstr("docker/")]')" >> "$GITHUB_OUTPUT"
        fi
```

**On push**: Uses `tj-actions/changed-files` to detect which `docker/` subdirectories have changed, producing a JSON array like `["app1", "app2"]`.

**On manual dispatch**: Lists all directories under `docker/`, building everything.

### Build Job

Uses a matrix strategy to build each discovered image in parallel:

```yaml
build:
  needs: discover
  if: needs.discover.outputs.images != '[]'
  runs-on: ubuntu-latest
  permissions:
    contents: read
    packages: write
  strategy:
    matrix:
      image: ${{ fromJson(needs.discover.outputs.images) }}
```

Key build steps:

1. **QEMU setup** -- Enables cross-architecture emulation for ARM64 builds
2. **Buildx setup** -- Configures Docker Buildx for multi-platform builds
3. **Registry login** -- Authenticates to ghcr.io using the GitHub token
4. **Version extraction** -- Reads the version from `ARG *_VERSION=` in the Dockerfile
5. **Build and push** -- Builds for `linux/amd64` and `linux/arm64`, tags with version and `latest`

### Version Extraction

```yaml
- id: version
  run: |
    version=$(grep -oP 'ARG \w+_VERSION=\K.+' docker/${{ matrix.image }}/Dockerfile | head -1)
    echo "tag=${version:-${{ github.sha }}}" >> "$GITHUB_OUTPUT"
```

The version tag is extracted from the first `ARG *_VERSION=` line in the Dockerfile. If no version ARG is found, it falls back to the Git commit SHA.

### Image Tags

Each image is tagged twice:

```
ghcr.io/swibrow/<image>:<version>
ghcr.io/swibrow/<image>:latest
```

---

## Deploy Docs Workflow

Builds and deploys the MkDocs Material documentation site to GitHub Pages.

```yaml title=".github/workflows/deploy-docs.yml"
name: Deploy Docs

on:
  push:
    branches: [main]
    paths:
      - "docs/**"
      - "mkdocs.yml"
      - "requirements.txt"
  workflow_dispatch:

permissions:
  contents: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: pip

      - run: pip install -r requirements.txt

      - run: mkdocs gh-deploy --force
```

- Triggered when docs, mkdocs config, or Python requirements change
- Uses `fetch-depth: 0` for the git-revision-date-localized plugin
- Deploys to the `gh-pages` branch
