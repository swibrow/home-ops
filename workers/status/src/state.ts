import type { Badge, Snapshot } from "./kromgo";

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
