---
title: LLDAP
---

# LLDAP

[LLDAP](https://github.com/lldap/lldap) is a lightweight LDAP server that provides the user directory for the cluster. It serves as the authentication backend for Authelia and any other service that needs to look up users and groups.

## Architecture

```mermaid
flowchart LR
    AUTH[Authelia\nSSO Portal] -->|LDAP bind\nport 5389| LLDAP[LLDAP\n2 replicas]
    LLDAP -->|User/group data| PG[(PostgreSQL\nCloudNativePG)]
    ADMIN((Admin)) -->|HTTPS\nlldap.example.com| LLDAP
    OP[1Password\nvia ExternalSecret] -->|JWT, password, key seed| LLDAP
    INF[Infisical\nvia ClusterSecretStore] -->|DB credentials| LLDAP
```

## Deployment

LLDAP is deployed via the [app-template](https://github.com/bjw-s-labs/helm-charts) Helm chart (v4.6.2) in the `security` namespace:

| Setting | Value |
|:--------|:------|
| Image | `ghcr.io/lldap/lldap:v0.6.2` |
| Replicas | 2 |
| Strategy | RollingUpdate |
| HTTP port | 8080 |
| LDAP port | 5389 |
| Base DN | `dc=example,dc=com` |
| Timezone | `Europe/Zurich` |

### High Availability

LLDAP runs with 2 replicas and a topology spread constraint to ensure pods land on different nodes:

```yaml
defaultPodOptions:
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app.kubernetes.io/name: lldap
```

## Network Access

LLDAP is exposed in two ways:

### LoadBalancer Service

A Cilium L2-announced LoadBalancer provides direct LDAP access on the network:

```yaml
service:
  app:
    type: LoadBalancer
    annotations:
      external-dns.alpha.kubernetes.io/hostname: lldap.example.com
      lbipam.cilium.io/ips: "192.168.0.222"
    ports:
      http:
        port: 8080
      ldap:
        port: 5389
```

| Protocol | Address | Port | Purpose |
|:---------|:--------|:-----|:--------|
| LDAP | 192.168.0.222 | 5389 | LDAP queries from Authelia and other services |
| HTTP | 192.168.0.222 | 8080 | Web admin UI |

### Internal Gateway

The web admin interface is also available via the internal Envoy gateway at `https://lldap.example.com`:

```yaml
route:
  app:
    hostnames:
      - lldap.example.com
    parentRefs:
      - name: envoy-internal
        namespace: networking
        sectionName: https
```

## Database

LLDAP uses PostgreSQL (via CloudNativePG) as its persistent backend, replacing the default SQLite:

```
LLDAP_DATABASE_URL: postgres://user:password@host.cloudnative-pg.svc.cluster.local/lldap
```

Database credentials are sourced from the `cnpg-secrets` ClusterSecretStore via an ExternalSecret:

```yaml title="externalsecret.yaml (database credentials)"
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: lldap-db
spec:
  secretStoreRef:
    name: cnpg-secrets
    kind: ClusterSecretStore
  target:
    name: lldap-db
    template:
      data:
        LLDAP_DATABASE_URL: >-
          postgres://{{ index . "user" }}:{{ index . "password" }}@
          {{ index . "host" }}.cloudnative-pg.svc.cluster.local/lldap
  dataFrom:
    - extract:
        key: lldap-superuser
```

## LDAP Schema

LLDAP uses a simplified LDAP schema with the following structure:

```
dc=example,dc=com
├── ou=people          # User entries
│   ├── uid=admin
│   ├── uid=user1
│   └── uid=user2
└── ou=groups          # Group entries
    ├── cn=auth_users
    └── cn=admin_group
```

### Key Attributes

| Attribute | Description |
|:----------|:------------|
| `uid` | Username (login identifier) |
| `displayName` | Full display name |
| `mail` | Email address |
| `memberOf` | Groups the user belongs to |
| `cn` | Group common name |

## Secrets

LLDAP receives secrets from two sources:

| Secret | Source | Contains |
|:-------|:-------|:---------|
| `lldap-secret` | 1Password (via ExternalSecret) | JWT secret, admin password, server key seed |
| `lldap-db` | CloudNativePG (via ClusterSecretStore) | PostgreSQL connection string |

```yaml title="externalsecret.yaml (application secrets)"
spec:
  target:
    name: lldap-secret
    template:
      data:
        LLDAP_JWT_SECRET: "{{ .lldap_jwt_secret }}"
        LLDAP_LDAP_USER_PASS: "{{ .lldap_password }}"
        LLDAP_KEY_SEED: "{{ .lldap_server_key_seed }}"
  dataFrom:
    - extract:
        key: lldap
```

## Integration with Authelia

Authelia connects to LLDAP using the following configuration (see [Authelia docs](authelia.md#ldap-backend) for full details):

| Setting | Value |
|:--------|:------|
| Address | `ldap://lldap.security.svc.cluster.local:5389` |
| Base DN | `dc=example,dc=com` |
| Users DN | `ou=people` |
| Groups DN | `ou=groups` |
| Users filter | `(&({username_attribute}={input})(objectClass=person))` |
| Groups filter | `(member={dn})` |

## Administration

Access the LLDAP web UI at `https://lldap.example.com` to manage users and groups.

!!! tip "Common tasks"
    - **Add a user**: Navigate to Users, click Create, fill in username/email/display name, set a password
    - **Add to group**: Navigate to Groups, select the group, add the user as a member
    - **Reset password**: Select the user, use the password reset option (or set `LLDAP_FORCE_LDAP_USER_PASS_RESET: "true"` to force reset on next login)
