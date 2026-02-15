mod gh '.justfiles/gh'
mod k8s '.justfiles/k8s'
mod sops '.justfiles/sops'
mod tf '.justfiles/terraform'
mod talos-ops '.justfiles/talos'
mod pitower 'pitower'

export TERRAFORM_WORKING_DIR := "terraform"
export ENVIRONMENT := "dev"
export SOPS_AGE_KEY_FILE := justfile_directory() / "age.key"
secret_files := `find . -type f -name '*.sops.yaml' ! -name '.sops.yaml'`

# Install pre-commit hooks
pre-commit-init:
    pre-commit install

# Run all pre-commit checks
pre-commit-check:
    pre-commit run -a

# List all secret files
secret-ls:
    @echo "{{ secret_files }}"

# Encrypt all secret files
secret-encrypt:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in {{ secret_files }}; do
        sops -e -i "$f"
    done

# Run all GitHub setup tasks
gh-all:
    just gh::repo
    just gh::update-environment-variables dev
