// The contract between the cluster and this Worker.
//
// Every id here must exist under `config.badges` in
// kubernetes/apps/pitower/networking/kromgo/values.yaml. kromgo only serves
// endpoints it has been configured with, so an id that drifts out of sync
// 404s and shows up on the page as `unknown` rather than as an error - which
// is the intended failure mode, but it does mean the two files have to be
// changed together.

export const HEADLINE_IDS = [
  "status_public",
  "status_health",
  "status_down",
  "status_degraded",
  "status_stale",
] as const;

export interface Tier {
  id: string;
  label: string;
  blurb: string;
}

// Ordered as the page renders them: what a visitor cares about first.
export const TIERS: Tier[] = [
  { id: "tier_edge", label: "Edge", blurb: "Tunnel, gateways, TLS" },
  { id: "tier_app", label: "Applications", blurb: "Self-hosted services" },
  { id: "tier_platform", label: "Platform", blurb: "Kubernetes, etcd, GitOps" },
  { id: "tier_node", label: "Nodes", blurb: "Cluster members" },
  { id: "tier_storage", label: "Storage", blurb: "Databases and object store" },
  { id: "tier_backup", label: "Backups", blurb: "Snapshot and WAL archives" },
  { id: "tier_network", label: "Network", blurb: "Gateway, switching, uplink" },
  { id: "tier_dns", label: "DNS", blurb: "Resolution" },
  { id: "tier_host", label: "Hosts", blurb: "Hypervisors" },
  { id: "tier_service", label: "Services", blurb: "Internal endpoints" },
  { id: "tier_power", label: "Power", blurb: "UPS" },
  { id: "tier_domain", label: "Domains", blurb: "Registration and certificates" },
];

export const BADGE_IDS: string[] = [...HEADLINE_IDS, ...TIERS.map((t) => t.id)];

export interface Badge {
  id: string;
  title: string;
  value: string;
  color: string;
  result: number;
}

export interface Snapshot {
  /** Unix milliseconds at which the fetch that produced this ran. */
  fetchedAt: number;
  /** Missing entries mean kromgo did not answer for that id on this pass. */
  badges: Record<string, Badge>;
}

const FETCH_TIMEOUT_MS = 5000;

async function fetchBadge(origin: string, id: string): Promise<Badge | null> {
  try {
    const res = await fetch(`${origin}/badges/${id}?format=json`, {
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      headers: { accept: "application/json" },
    });
    if (!res.ok) return null;
    const body = (await res.json()) as Partial<Badge>;
    if (typeof body.value !== "string" || typeof body.result !== "number") return null;
    return {
      id,
      title: typeof body.title === "string" ? body.title : id,
      value: body.value,
      color: typeof body.color === "string" ? body.color : "lightgrey",
      result: body.result,
    };
  } catch {
    // Timeout, DNS failure, TLS failure, tunnel down - all the same to us.
    return null;
  }
}

/**
 * Collect every badge in one pass.
 *
 * A badge that fails is simply absent from the result, and the page renders it
 * as `unknown`. Carrying the previous snapshot's value forward per-badge would
 * be worse: it would mix ages inside something labelled with a single
 * timestamp. The whole-snapshot fallback to last-known-good is the caller's
 * job, and it only applies when nothing at all could be fetched.
 *
 * Returns null when every request failed, which is what an outage looks like.
 */
export async function fetchSnapshot(origin: string, now: number): Promise<Snapshot | null> {
  const results = await Promise.all(BADGE_IDS.map((id) => fetchBadge(origin, id)));
  const badges: Record<string, Badge> = {};
  for (const badge of results) {
    if (badge) badges[badge.id] = badge;
  }
  if (Object.keys(badges).length === 0) return null;
  return { fetchedAt: now, badges };
}
