export interface NavPage {
  label: string;
  id: string;
}

export interface NavGroup {
  label: string;
  id?: string;
  items: NavPage[];
}

export interface NavSection {
  label: string;
  id: string;
  items: (NavPage | NavGroup)[];
}

export const home: NavPage = { label: "Home", id: "index" };

export const sections: NavSection[] = [
  {
    label: "Getting Started",
    id: "getting-started",
    items: [
      { label: "Prerequisites", id: "getting-started/prerequisites" },
      { label: "Architecture Overview", id: "getting-started/architecture-overview" },
    ],
  },
  {
    label: "Infrastructure",
    id: "infrastructure",
    items: [
      { label: "Hardware", id: "infrastructure/hardware" },
      { label: "Talos Linux", id: "infrastructure/talos-linux" },
      { label: "Cluster Bootstrap", id: "infrastructure/cluster-bootstrap" },
      { label: "Node Management", id: "infrastructure/node-management" },
      { label: "proxmox-01 Migration", id: "infrastructure/proxmox-01-migration" },
    ],
  },
  {
    label: "Networking",
    id: "networking",
    items: [
      { label: "Cilium CNI", id: "networking/cilium-cni" },
      { label: "Envoy Gateway", id: "networking/envoy-gateway" },
      { label: "DNS Management", id: "networking/dns-management" },
      { label: "External DNS", id: "networking/external-dns" },
      { label: "Towonel Tunnel", id: "networking/towonel-tunnel" },
      { label: "Tailscale", id: "networking/tailscale" },
      { label: "Load Balancers", id: "networking/load-balancers" },
    ],
  },
  {
    label: "GitOps",
    id: "gitops",
    items: [
      { label: "ArgoCD Setup", id: "gitops/argocd-setup" },
      { label: "ApplicationSets", id: "gitops/application-sets" },
      { label: "Sync Policies", id: "gitops/sync-policies" },
      { label: "Adding Apps", id: "gitops/adding-apps" },
    ],
  },
  {
    label: "Storage",
    id: "storage",
    items: [
      { label: "Rook Ceph", id: "storage/rook-ceph" },
      { label: "OpenEBS", id: "storage/openebs" },
      { label: "Garage S3", id: "storage/garage" },
      { label: "Backup & Restore", id: "storage/backup-restore" },
    ],
  },
  {
    label: "Security",
    id: "security",
    items: [
      { label: "Kanidm", id: "security/kanidm" },
      { label: "CrowdSec", id: "security/crowdsec" },
      { label: "External Secrets", id: "security/external-secrets" },
      { label: "OIDC Clients", id: "security/oidc-clients" },
      { label: "SOPS", id: "security/sops" },
      { label: "Cert Manager", id: "security/cert-manager" },
    ],
  },
  {
    label: "Monitoring",
    id: "monitoring",
    items: [
      { label: "Prometheus Stack", id: "monitoring/prometheus-stack" },
      { label: "Status Page", id: "monitoring/status-page" },
      { label: "Grafana", id: "monitoring/grafana" },
      { label: "VictoriaLogs", id: "monitoring/victoria-logs" },
      { label: "Fluent Bit", id: "monitoring/fluent-bit" },
      { label: "OpenTelemetry Collector", id: "monitoring/otel-collector" },
    ],
  },
  {
    label: "Applications",
    id: "applications",
    items: [
      {
        label: "Media Stack",
        id: "applications/media-stack",
        items: [
          { label: "Jellyfin", id: "applications/media-stack/jellyfin" },
          { label: "Arr Stack", id: "applications/media-stack/arr-stack" },
          { label: "Downloaders", id: "applications/media-stack/downloaders" },
        ],
      },
      {
        label: "Home Automation",
        id: "applications/home-automation",
        items: [{ label: "Home Assistant", id: "applications/home-automation/home-assistant" }],
      },
      { label: "Self-Hosted", id: "applications/selfhosted" },
      { label: "Databases", id: "applications/databases" },
    ],
  },
  {
    label: "Operations",
    id: "operations",
    items: [
      { label: "Justfile Recipes", id: "operations/justfile-recipes" },
      { label: "Talos Commands", id: "operations/talos-commands" },
      { label: "Troubleshooting", id: "operations/troubleshooting" },
      { label: "Upgrades", id: "operations/upgrades" },
      { label: "CNPG Consolidation", id: "operations/cnpg-consolidation" },
      { label: "Agent Sandbox v1 Upgrade", id: "operations/agent-sandbox-v1-upgrade" },
      { label: "Grafana Dashboard Data Audit", id: "operations/grafana-dashboard-data-audit" },
    ],
  },
  {
    label: "CI/CD",
    id: "ci-cd",
    items: [
      { label: "GitHub Actions", id: "ci-cd/github-actions" },
      { label: "Docker Builds", id: "ci-cd/docker-builds" },
      { label: "Renovate", id: "ci-cd/renovate" },
    ],
  },
  {
    label: "Development",
    id: "development",
    items: [
      { label: "App Template", id: "development/app-template" },
      { label: "Adding Apps", id: "development/adding-apps" },
    ],
  },
  {
    label: "Reference",
    id: "reference",
    items: [
      { label: "IP Allocation", id: "reference/ip-allocation" },
      { label: "App Catalog", id: "reference/app-catalog" },
    ],
  },
];

export interface FlatPage extends NavPage {
  section?: NavSection;
}

export const pages: FlatPage[] = [
  home,
  ...sections.flatMap((section) => [
    { label: "Overview", id: section.id, section },
    ...section.items.flatMap((item) =>
      "items" in item
        ? [...(item.id ? [{ label: item.label, id: item.id, section }] : []), ...item.items.map((p) => ({ ...p, section }))]
        : [{ ...item, section }],
    ),
  ]),
];

export function findPage(id: string) {
  const index = pages.findIndex((p) => p.id === id);
  return { page: pages[index], prev: pages[index - 1], next: pages[index + 1] };
}
