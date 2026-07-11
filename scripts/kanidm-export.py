#!/usr/bin/env python3
"""Export the live Kanidm OAuth2 / account-policy state as reproducible `kanidm` CLI commands.

Kanidm's OAuth2 clients and account policy are imperative state that lives only in
the server's SQLite DB on the PVC (plus Volsync backups) — none of it is in git.
This regenerates the `kanidm system oauth2 ...` (and account-policy) commands needed
to rebuild that state on a fresh instance, so the config is reviewable and recoverable.

This is NOT a disaster-recovery backup of secrets/keys — basic secrets and signing
keys are NOT exported (app secrets already live in Infisical; keys are regenerated).
For a complete byte-for-byte restore use `kanidmd database backup` instead.

Usage:
    export KANIDM_URL=https://idm.wibrow.dev
    kanidm login -D idm_admin            # session must be valid
    ./scripts/kanidm-export.py > kanidm-state.sh

Requires: the `kanidm` client on PATH and a valid login session.
"""
from __future__ import annotations

import json
import re
import shlex
import subprocess
import sys

# Groups whose account-policy attributes we emit (extend as needed).
POLICY_GROUPS = ["idm_all_persons"]

# Default values — only emit a command when the live value diverges from the default.
DEFAULTS = {
    "oauth2_strict_redirect_uri": "true",   # strict redirect on by default
    "oauth2_consent_prompt_enable": "true",  # consent prompt on by default
    "oauth2_prefer_short_username": "false",  # spn by default
    "oauth2_jwt_legacy_crypto_enable": "false",
    "oauth2_allow_localhost_redirect": "false",
}


def kanidm_json(*args: str):
    """Run a kanidm CLI command with JSON output and parse it."""
    out = subprocess.run(
        ["kanidm", *args, "-o", "json"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    return json.loads(out) if out else []


def first(attrs: dict, key: str, default=None):
    v = attrs.get(key)
    return v[0] if v else default


def bool_attr(attrs: dict, key: str) -> bool:
    return first(attrs, key, "false") == "true"


_SCOPE_RE = re.compile(r'^(?P<group>[^:]+):\s*\{(?P<scopes>.*)\}$')
_CLAIM_RE = re.compile(r'^(?P<claim>[^:]+):(?P<group>[^:]+):(?P<join>[^:]*):(?P<vals>.*)$')


def parse_scope_map(entry: str):
    """'app_access@realm: {"email", "openid"}' -> ('app_access@realm', ['email','openid'])."""
    m = _SCOPE_RE.match(entry)
    if not m:
        return None
    scopes = re.findall(r'"([^"]+)"', m.group("scopes"))
    return m.group("group").strip(), sorted(scopes)


def parse_claim_map(entry: str):
    """'groups:grp@realm:;:"a","b"' -> (claim, group, join, [a,b])."""
    m = _CLAIM_RE.match(entry)
    if not m:
        return None
    vals = re.findall(r'"([^"]+)"', m.group("vals"))
    return m.group("claim"), m.group("group"), m.group("join"), vals


def emit(line: str = ""):
    print(line)


def export_oauth2():
    clients = kanidm_json("system", "oauth2", "list")
    emit("# ── OAuth2 clients " + "─" * 50)
    emit(f"# {len(clients)} clients. Basic-client secrets are NOT exported (see Infisical).")
    emit("# After recreating a confidential client, re-run show-basic-secret and")
    emit("# reconcile the secret in Infisical, OR reset-basic-secret + update the app.")
    emit()
    for c in sorted(clients, key=lambda c: first(c, "name", "")):
        name = first(c, "name")
        display = first(c, "displayname", name)
        landing = first(c, "oauth2_rs_origin_landing", "")
        is_public = "oauth2_resource_server_public" in c.get("class", [])
        verb = "create-public" if is_public else "create"

        emit(f"# {name} ({'public/PKCE' if is_public else 'confidential'})")
        emit(f"kanidm system oauth2 {verb} {shlex.quote(name)} "
             f"{shlex.quote(display)} {shlex.quote(landing)}")

        # redirect URLs (oauth2_rs_origin is the redirect list)
        for url in c.get("oauth2_rs_origin", []):
            emit(f"kanidm system oauth2 add-redirect-url {shlex.quote(name)} {shlex.quote(url)}")

        # scope maps
        for entry in c.get("oauth2_rs_scope_map", []):
            parsed = parse_scope_map(entry)
            if parsed:
                grp, scopes = parsed
                emit(f"kanidm system oauth2 update-scope-map {shlex.quote(name)} "
                     f"{shlex.quote(grp)} {' '.join(scopes)}")

        # supplemental scope maps
        for entry in c.get("oauth2_rs_sup_scope_map", []):
            parsed = parse_scope_map(entry)
            if parsed:
                grp, scopes = parsed
                emit(f"kanidm system oauth2 update-sup-scope-map {shlex.quote(name)} "
                     f"{shlex.quote(grp)} {' '.join(scopes)}")

        # claim maps
        for entry in c.get("oauth2_rs_claim_map", []):
            parsed = parse_claim_map(entry)
            if parsed:
                claim, grp, join, vals = parsed
                emit(f"kanidm system oauth2 update-claim-map {shlex.quote(name)} "
                     f"{shlex.quote(claim)} {shlex.quote(grp)} {' '.join(vals)}")
                if join:
                    emit(f"#   join char is {join!r} — set with update-claim-map-join "
                         f"(map ';'->ssv, ','->csv as appropriate)")

        # non-default flags
        if bool_attr(c, "oauth2_prefer_short_username"):
            emit(f"kanidm system oauth2 prefer-short-username {shlex.quote(name)}")
        if bool_attr(c, "oauth2_jwt_legacy_crypto_enable"):
            emit(f"kanidm system oauth2 warning-enable-legacy-crypto {shlex.quote(name)}")
        if bool_attr(c, "oauth2_allow_localhost_redirect"):
            emit(f"kanidm system oauth2 enable-localhost-redirects {shlex.quote(name)}")
        if not bool_attr(c, "oauth2_strict_redirect_uri"):
            emit(f"kanidm system oauth2 disable-strict-redirect-url {shlex.quote(name)}")
        if not bool_attr(c, "oauth2_consent_prompt_enable"):
            emit(f"kanidm system oauth2 disable-consent-prompt {shlex.quote(name)}")
        emit()


def export_account_policy():
    emit("# ── Account policy " + "─" * 50)
    for grp in POLICY_GROUPS:
        try:
            res = kanidm_json("group", "get", grp)
        except subprocess.CalledProcessError:
            emit(f"# {grp}: not found")
            continue
        attrs = res[0] if isinstance(res, list) and res else res
        emit(f"# {grp}")
        mapping = [
            ("authsession_expiry", "auth-expiry"),
            ("privilege_expiry", "privilege-expiry"),
            ("credential_type_minimum", "credential-type-minimum"),
            ("auth_password_minimum_length", "password-minimum-length"),
        ]
        for attr, sub in mapping:
            val = first(attrs, attr)
            if val is not None:
                emit(f"kanidm group account-policy {sub} {grp} {shlex.quote(str(val))}")
        emit()


def main():
    emit("#!/usr/bin/env bash")
    emit("# Generated by scripts/kanidm-export.py — reproduces Kanidm imperative state.")
    emit("# Review before running against a fresh instance. Secrets/keys NOT included.")
    emit("set -euo pipefail")
    emit(': "${KANIDM_URL:?set KANIDM_URL and run: kanidm login -D idm_admin}"')
    emit()
    try:
        export_oauth2()
        export_account_policy()
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"kanidm CLI failed: {e.stderr}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
