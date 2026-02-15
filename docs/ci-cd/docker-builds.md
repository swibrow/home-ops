# Docker Builds

Automated Docker image builds using GitHub Actions with multi-architecture support and GitHub Container Registry (GHCR).

---

## Overview

Custom Docker images live in the `docker/` directory at the repository root. Each subdirectory contains a `Dockerfile` and any supporting files for a single image.

```
docker/
├── app-one/
│   └── Dockerfile
├── app-two/
│   ├── Dockerfile
│   └── config.yaml
└── app-three/
    └── Dockerfile
```

---

## Auto-Discovery

The build workflow automatically discovers which images need to be built based on the trigger:

### On Push to `main`

When files under `docker/` are changed and pushed to `main`, the workflow uses [tj-actions/changed-files](https://github.com/tj-actions/changed-files) to detect which subdirectories have been modified:

```yaml
- id: changed
  uses: tj-actions/changed-files@v47
  with:
    dir_names: "true"
    dir_names_max_depth: "2"
    files: docker/**
    json: "true"
    escape_json: "false"
```

Only the changed images are built, saving time and compute resources.

### On Manual Dispatch

When manually triggered via `workflow_dispatch`, all images under `docker/` are discovered and built:

```bash
ls -d docker/*/ | xargs -I{} basename {}
```

---

## Version Extraction

Image versions are automatically extracted from the Dockerfile's `ARG` directives:

```dockerfile
# Example Dockerfile
ARG APP_VERSION=1.2.3

FROM ubuntu:22.04
# ...
```

The build step uses a regex to extract the version:

```bash
version=$(grep -oP 'ARG \w+_VERSION=\K.+' docker/${{ matrix.image }}/Dockerfile | head -1)
```

| Scenario | Tag |
|:---------|:----|
| `ARG APP_VERSION=1.2.3` found | `1.2.3` |
| No `*_VERSION` ARG found | Git commit SHA |

!!! tip "Version ARG Naming"
    Any ARG ending in `_VERSION` will be detected. Common patterns:
    ```dockerfile
    ARG APP_VERSION=2.0.0
    ARG TOOL_VERSION=1.5.3
    ARG BASE_VERSION=3.18
    ```

---

## Multi-Platform Builds

All images are built for two architectures using Docker Buildx and QEMU emulation:

| Platform | Architecture | Use Case |
|:---------|:-------------|:---------|
| `linux/amd64` | x86_64 | Intel/AMD worker nodes |
| `linux/arm64` | AArch64 | Raspberry Pi nodes |

```yaml
- uses: docker/setup-qemu-action@v3

- uses: docker/setup-buildx-action@v3

- uses: docker/build-push-action@v6
  with:
    context: docker/${{ matrix.image }}
    platforms: linux/amd64,linux/arm64
    push: true
    tags: |
      ghcr.io/swibrow/${{ matrix.image }}:<version>
      ghcr.io/swibrow/${{ matrix.image }}:latest
```

!!! note "Build Times"
    ARM64 builds on AMD64 runners use QEMU emulation, which is slower than native builds. Expect ARM64 builds to take 2-5x longer than AMD64 builds.

---

## Registry

All images are pushed to the **GitHub Container Registry (GHCR)**:

```
ghcr.io/swibrow/<image-name>:<tag>
```

### Authentication

The workflow authenticates using the built-in `GITHUB_TOKEN`:

```yaml
- uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

### Permissions

The build job requires `packages: write` permission to push images:

```yaml
permissions:
  contents: read
  packages: write
```

---

## Image Tags

Each successful build produces two tags:

| Tag | Purpose |
|:----|:--------|
| `<version>` | Immutable version tag extracted from Dockerfile |
| `latest` | Rolling tag pointing to the most recent build |

Example for an image `rrda` with `ARG RRDA_VERSION=2.1.0`:

```
ghcr.io/swibrow/rrda:2.1.0
ghcr.io/swibrow/rrda:latest
```

---

## Adding a New Docker Image

1. Create a new directory under `docker/`:

    ```bash
    mkdir docker/my-app
    ```

2. Add a `Dockerfile` with a version ARG:

    ```dockerfile
    ARG MY_APP_VERSION=1.0.0

    FROM python:3.12-slim
    # ... build steps
    ```

3. Commit and push to `main`:

    ```bash
    git add docker/my-app/
    git commit -m "feat(docker): add my-app image"
    git push origin main
    ```

4. The build workflow will automatically detect the new directory and build the image.

5. The image will be available at:

    ```
    ghcr.io/swibrow/my-app:1.0.0
    ghcr.io/swibrow/my-app:latest
    ```

---

## Matrix Strategy

The build job uses a matrix strategy to build all discovered images in parallel:

```yaml
strategy:
  matrix:
    image: ${{ fromJson(needs.discover.outputs.images) }}
```

This means if three images change in a single push, three build jobs run concurrently, each handling one image independently.
