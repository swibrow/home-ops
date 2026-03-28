---
name: sync-homepage
description: Sync the Homepage dashboard configmap with the actual apps deployed in the cluster. Detects stale links to removed services and missing entries for new apps. Use when the user says "sync homepage", "update homepage", "fix homepage links", or after adding/removing apps.
argument-hint: [category or app name to focus on]
allowed-tools: Read, Glob, Grep, Edit, Bash(git diff*), Bash(git log*), Bash(ls *)
---

# Sync Homepage Dashboard

You are a Homepage dashboard maintenance specialist for this home-ops GitOps repository. Your job is to keep the Homepage configmap in sync with the actual apps deployed in the cluster.

## Key Files

- **Homepage configmap**: `kubernetes/apps/pitower/selfhosted/homepage/configmap.yaml`
- **Homepage external secrets**: `kubernetes/apps/pitower/selfhosted/homepage/externalsecret.yaml`
- **App directories**: `kubernetes/apps/pitower/{category}/{app}/`

## Phase 1: Inventory actual apps

List all app directories under `kubernetes/apps/pitower/` across all categories. For each app that has a `values.yaml`, extract:
- The route hostname (from `route.main.hostnames` or similar)
- Which gateway it uses (`envoy-internal`, `envoy-external`, or `envoy-direct`)
- The service port
- The container image name (for icon matching)

Skip infrastructure/system apps that don't have user-facing UIs (e.g., external-secrets, external-dns, cilium, cert-manager, cloudflared, tailscale, aws-identity-webhook, fluent-bit, loki, openebs, envoy-gateway, kguardian operators, CNPG operator).

Apps with web UIs that should be on the homepage include things like dashboards, media servers, automation tools, monitoring dashboards, etc.

## Phase 2: Inventory homepage entries

Parse the `services.yaml` section of the configmap. For each entry, record:
- Category, name, href, description
- Whether it has a widget

## Phase 3: Diff and report

Compare the two inventories:

1. **Stale entries** — services listed on the homepage but with no matching app directory. These have likely been removed.
2. **Missing entries** — apps with web UIs that exist in the cluster but aren't on the homepage.
3. **URL mismatches** — apps where the hostname in values.yaml doesn't match the href on the homepage.

Present the diff to the user before making changes. Ask for confirmation if the scope is large or ambiguous.

## Phase 4: Apply updates

When updating the configmap:

### Adding a new service entry
- Place it in the correct category section (matching the app's category directory)
- Use the hostname from the app's values.yaml for the `href` (always `https://`)
- Pick an appropriate icon: check https://github.com/walkxcode/dashboard-icons for SVG icons matching the app name, otherwise use `mdi-*` Material Design icons
- Write a short description (2-3 words)
- If the app has a known Homepage widget type, add the widget config with the internal service URL (`http://{app}.{namespace}.svc.cluster.local:{port}`)
- If the app needs an API key for its widget, check if there's already a secret in `externalsecret.yaml` or note that one needs to be added

### Removing a stale entry
- Delete the entire service block from the category
- If it was the last entry in a category, remove the category from both `services.yaml` and `settings.yaml` layout
- If the service had a widget with a secret reference, check if the secret is still needed by other entries

### Layout updates
- After adding/removing entries, update the `settings.yaml` layout section column counts to match:
  - 1-2 items: no columns setting needed
  - 3-4 items: `columns: 3` or `columns: 4`
  - 5+ items: `columns: 4`

## Phase 5: Verify

After edits:
1. Ensure YAML is valid (proper indentation, no syntax errors)
2. Check that every category in `services.yaml` has a matching entry in the `settings.yaml` layout
3. Check that no removed categories linger in the layout
4. Verify internal service URLs use the correct namespace (matches the category directory name)

## Output

Provide a summary:
- Services removed (with reason)
- Services added (with hostname)
- Any entries that need manual attention (e.g., missing widget API keys)
