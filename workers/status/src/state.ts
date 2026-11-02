import type { Badge, Graph, Series, Snapshot } from "./kromgo";

/**
 * How old a snapshot may be before the page stops presenting it as current.
 * The scheduled handler refreshes every minute, so anything past this means
 * several refreshes in a row failed - i.e. the cluster or the path to it is
 * down, which is precisely when a status page must not show green.
 */
export const STALE_AFTER_MS = 5 * 60 * 1000;

export type Level = "operational" | "degraded" | "outage" | "unknown";

export interface TierState {
  id: string;
  label: string;
  blurb: string;
  level: Level;
  /** Rendered percentage, or "unknown" when the badge is missing or sentinel. */
  value: string;
  ratio: number | null;
}

export interface PageState {
  level: Level;
  headline: string;
  detail: string;
  fetchedAt: number;
  ageSeconds: number;
  stale: boolean;
  notes: string[];
}

/**
 * kromgo emits -1 as an explicit "no series" sentinel (see the `or on()
 * vector(-1)` guard on every status query). Without it an absent metric and a
 * genuine zero are indistinguishable, and the page would render a dead
 * exporter as a dead service.
 */
function reading(badge: Badge | undefined): number | null {
  if (!badge) return null;
  if (!Number.isFinite(badge.result) || badge.result < 0) return null;
  return badge.result;
}

/**
 * Floors rather than rounds below 100. Rounding lets 99.78% render as "100%"
 * next to an amber dot, which reads as a bug in the page rather than as the
 * degradation it is. Only an exact 100 may print as 100%.
 */
export function formatRatio(ratio: number): string {
  return ratio >= 100 ? "100%" : `${Math.floor(ratio)}%`;
}

function ratioLevel(ratio: number | null): Level {
  if (ratio === null) return "unknown";
  if (ratio >= 100) return "operational";
  if (ratio > 0) return "degraded";
  return "outage";
}

export function tierStates(
  snapshot: Snapshot,
  tiers: { id: string; label: string; blurb: string }[],
): TierState[] {
  return tiers.map((tier) => {
    const ratio = reading(snapshot.badges[tier.id]);
    return {
      ...tier,
      ratio,
      level: ratioLevel(ratio),
      value: ratio === null ? "unknown" : formatRatio(ratio),
    };
  });
}

export function pageState(snapshot: Snapshot, now: number): PageState {
  const ageSeconds = Math.max(0, Math.round((now - snapshot.fetchedAt) / 1000));
  const stale = now - snapshot.fetchedAt > STALE_AFTER_MS;

  const publicRatio = reading(snapshot.badges.status_public);
  const health = reading(snapshot.badges.status_health);
  const down = reading(snapshot.badges.status_down);
  const degraded = reading(snapshot.badges.status_degraded);
  const staleSignals = reading(snapshot.badges.status_stale);

  const notes: string[] = [];
  if (down !== null && down > 0) {
    notes.push(`${down} component${down === 1 ? "" : "s"} down`);
  }
  if (degraded !== null && degraded > 0) {
    notes.push(`${degraded} component${degraded === 1 ? "" : "s"} degraded`);
  }
  // Deliberately does not change the level. Missing evidence is not evidence of
  // failure, but a page claiming "all operational" while blind in four places
  // is lying by omission, so it is always said out loud.
  if (staleSignals !== null && staleSignals > 0) {
    notes.push(`${staleSignals} signal${staleSignals === 1 ? "" : "s"} missing`);
  }

  if (stale) {
    return {
      level: "unknown",
      headline: "Status unknown",
      detail:
        "The status page has not been able to reach the cluster. Everything below is the last known good reading.",
      fetchedAt: snapshot.fetchedAt,
      ageSeconds,
      stale,
      notes,
    };
  }

  // The public ratio leads because this page answers "can I reach it from the
  // internet". It comes only from the probe running outside the house, so it
  // is the one number that has actually crossed the tunnel.
  let level = ratioLevel(publicRatio);
  let headline: string;
  let detail: string;

  if (publicRatio === null) {
    level = "unknown";
    headline = "Public availability unknown";
    detail = "The external vantage is not reporting, so internet reachability is untested.";
  } else if (level === "operational") {
    headline = "All systems operational";
    detail = "Every public service answered from outside the network.";
  } else if (level === "degraded") {
    headline = "Partial outage";
    detail = `${formatRatio(publicRatio)} of public services answered from outside the network.`;
  } else {
    headline = "Major outage";
    detail = "No public service answered from outside the network.";
  }

  // Internal health is min() across every non-application tier, so it is a
  // strict signal: it can be degraded while everything a visitor touches is
  // fine. It can lower the level but never raise it.
  if (health !== null && health < 1 && level === "operational") {
    level = "degraded";
    headline = "Operational with degraded internals";
    detail = "Public services are reachable, but a supporting component is not healthy.";
  }

  return { level, headline, detail, fetchedAt: snapshot.fetchedAt, ageSeconds, stale, notes };
}

export function relativeAge(seconds: number): string {
  if (seconds < 90) return `${seconds}s ago`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 90) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 36) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

export interface Issue {
  tier: string;
  tierLabel: string;
  component: string;
  /** "wan" means the probe crossed the internet; worth saying, since the same name can fail on the LAN only. */
  scope: string;
  level: Level;
  value: string;
  /** Seconds the issue has lasted, measured to the end of the window (current) or to recovery (resolved). */
  durationSeconds: number;
  /** True when the run reaches back to the start of the window, so the duration is a lower bound. */
  durationIsFloor: boolean;
  /** Seconds since recovery; only set on resolved issues. */
  resolvedSecondsAgo?: number;
  details: string[];
}

export interface Issues {
  current: Issue[];
  resolved: Issue[];
  missing: string[];
}

/** Points further apart than this belong to separate runs. */
function gapLimit(graph: Graph): number {
  return graph.step * 2;
}

function isCurrent(series: Series, graph: Graph): boolean {
  const last = series.data.at(-1);
  return last !== undefined && last.t >= graph.end - gapLimit(graph);
}

/** The last contiguous run of points, which is the issue the page talks about. */
function lastRun(series: Series, graph: Graph): { from: number; to: number; value: number } | null {
  const data = series.data;
  if (data.length === 0) return null;
  let i = data.length - 1;
  while (i > 0 && data[i].t - data[i - 1].t <= gapLimit(graph)) i--;
  const last = data[data.length - 1];
  return { from: data[i].t, to: last.t, value: last.v };
}

function stripCluster(name: string): string {
  return name.replace(/^pitower-/, "");
}

/**
 * Some components are rollups whose own value says only "something inside is
 * wrong". These pull the inside from a second graph so the page names it.
 */
const DETAIL_SOURCES: Record<string, { graph: string; describe: (labels: Record<string, string>) => string }> = {
  gitops: {
    graph: "status_gitops",
    describe: (l) => {
      const states = [l.health_status, l.sync_status].filter(
        (s) => s && s !== "Healthy" && s !== "Synced",
      );
      return `${stripCluster(l.name ?? "unknown")}: ${states.join(", ")}`;
    },
  },
  "rook-ceph": {
    graph: "status_ceph",
    describe: (l) => l.name ?? "unknown check",
  },
};

function details(component: string, snapshot: Snapshot): string[] {
  const source = DETAIL_SOURCES[component];
  const graph = source && snapshot.graphs?.[source.graph];
  if (!source || !graph) return [];
  return graph.series
    .filter((s) => isCurrent(s, graph))
    .map((s) => source.describe(s.labels))
    .sort();
}

const LEVEL_ORDER: Record<Level, number> = { outage: 0, degraded: 1, unknown: 2, operational: 3 };

export function issueStates(snapshot: Snapshot, tiers: { id: string; label: string }[]): Issues {
  const tierLabel = (tier: string) => tiers.find((t) => t.id === `tier_${tier}`)?.label ?? tier;
  const tierOrder = (tier: string) => {
    const i = tiers.findIndex((t) => t.id === `tier_${tier}`);
    return i === -1 ? tiers.length : i;
  };

  const current: Issue[] = [];
  const resolved: Issue[] = [];
  const graph = snapshot.graphs?.status_issues;
  for (const series of graph?.series ?? []) {
    const run = graph && lastRun(series, graph);
    if (!graph || !run) continue;
    const { tier = "unknown", component = "unknown", scope = "" } = series.labels;
    const live = isCurrent(series, graph);
    const level: Level = run.value > 0 ? "degraded" : "outage";
    const issue: Issue = {
      tier,
      tierLabel: tierLabel(tier),
      component,
      scope,
      level,
      value: level === "outage" ? "Down" : `Degraded · ${formatRatio(run.value * 100)}`,
      durationSeconds: Math.max(graph.step, (live ? graph.end : run.to) - run.from),
      durationIsFloor: run.from <= graph.start + graph.step,
      details: live ? details(component, snapshot) : [],
    };
    if (live) {
      current.push(issue);
    } else {
      issue.resolvedSecondsAgo = Math.max(0, graph.end - run.to);
      resolved.push(issue);
    }
  }

  current.sort(
    (a, b) =>
      LEVEL_ORDER[a.level] - LEVEL_ORDER[b.level] ||
      tierOrder(a.tier) - tierOrder(b.tier) ||
      a.component.localeCompare(b.component),
  );
  resolved.sort((a, b) => (a.resolvedSecondsAgo ?? 0) - (b.resolvedSecondsAgo ?? 0));

  const missingGraph = snapshot.graphs?.status_missing;
  const missing = (missingGraph?.series ?? [])
    .filter((s) => missingGraph && isCurrent(s, missingGraph))
    .map((s) => s.labels.component ?? "unknown")
    .sort();

  return { current, resolved, missing };
}

export function formatDuration(seconds: number): string {
  if (seconds < 90) return `${seconds}s`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  return `${Math.round(minutes / 60)}h`;
}
