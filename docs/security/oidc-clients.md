---
title: OIDC Clients
---

# OIDC Clients

[Kanidm](https://kanidm.com/) at `idm.wibrow.dev` is the identity provider for browser logins. Each app that uses SSO is a confidential OAuth2 client in Kanidm; the client secret goes to Infisical and reaches the cluster through an ExternalSecret. Kanidm clients are not managed in Git, so registering one is a manual step, wrapped by the `kanidm` just module.

Two shapes exist:

- **App-native OIDC**: the app implements the login itself (Headlamp, Forgejo, LiteLLM, Open WebUI, ...). The redirect URL and secret format are whatever the app expects.
- **Gateway-enforced OIDC**: the app has no login of its own, so an Envoy Gateway `SecurityPolicy` on its `HTTPRoute` does it. The callback is always `https://<host>/oauth2/callback`, the Secret key is always `client-secret`, and Envoy authenticates to the token endpoint with HTTP Basic and PKCE S256, which is what Kanidm requires by default.

## Registering a client

```bash
just kanidm ls                                   # existing clients, redirect URLs, scope maps
just kanidm oidc-client <name> <landing-url> [callback-url] [group]
just kanidm oidc-secret <name> <infisical-path> <SECRET_KEY>
```

`oidc-client` creates the client if it does not exist, adds the redirect URL (default `<landing-url>/oauth2/callback`, the Envoy Gateway one; app-native clients pass their own), and maps the group (default `app_access`, the group every app uses) to the `openid profile email` scopes. It is safe to re-run. `oidc-secret` pipes `kanidm system oauth2 show-basic-secret` straight into `just infisical set`, so the secret never lands on the terminal.

## Worked example: the agentgateway UI

The agentgateway proxy serves a read-only UI on its admin port. The manifests in `kubernetes/apps/pitower/ai/agentgateway/config/` expose it at `agentgateway.wibrow.dev` behind Kanidm:

| File | Role |
|:-----|:-----|
| `parameters.yaml` | `rawConfig.config.adminAddr: 0.0.0.0:15000` so the admin port is reachable from the Service |
| `service.yaml` | `agentgateway-ui`, port 80 -> 15000 on the proxy pods |
| `httproute.yaml` | `agentgateway-ui` route on `envoy-internal` |
| `securitypolicy.yaml` | OIDC: issuer `https://idm.wibrow.dev/oauth2/openid/agentgateway`, client `agentgateway`, secret `agentgateway-ui-oidc` |
| `networkpolicy.yaml` | port 15000 reachable only from the `envoy-internal` pods, since the admin API has no auth of its own |
| `externalsecret.yaml` | `agentgateway-ui-oidc` from Infisical `/ai/agentgateway/UI_OIDC_CLIENT_SECRET` |

The manual half, once:

```bash
just kanidm oidc-client agentgateway https://agentgateway.wibrow.dev
just kanidm oidc-secret agentgateway /ai/agentgateway UI_OIDC_CLIENT_SECRET
just k8s es-sync ai agentgateway-ui-oidc
```

Then open <https://agentgateway.wibrow.dev/ui/>: Envoy redirects to Kanidm, and after login the dashboard shows the models, routes and policies from the live gateway dump.

## Checks

- Issuer discovery must work from inside the cluster: `curl -s https://idm.wibrow.dev/oauth2/openid/<name>/.well-known/openid-configuration`.
- The `SecurityPolicy` reports `Accepted` in its status; a wrong issuer or missing Secret shows up there before anything reaches the browser.
- `redirect_uri` mismatches are rejected by Kanidm with `oauth2_strict_redirect_uri`; the URL in `just kanidm ls` must match the `redirectURL` in the policy exactly.
