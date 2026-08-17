import { TIERS, type Snapshot } from "./kromgo";
import { pageState, relativeAge, tierStates, type Level } from "./state";

const LEVEL_LABEL: Record<Level, string> = {
  operational: "Operational",
  degraded: "Degraded",
  outage: "Outage",
  unknown: "Unknown",
};

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

const STYLE = `
:root {
  color-scheme: light dark;
  --bg: #fbfbfa;
  --panel: #ffffff;
  --border: #e4e4e1;
  --text: #1b1b19;
  --muted: #6b6b66;
  --operational: #2f8a4c;
  --degraded: #b5761b;
  --outage: #bb2f2f;
  --unknown: #8a8a85;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #121211;
    --panel: #1b1b19;
    --border: #2e2e2b;
    --text: #eceae5;
    --muted: #9b9b95;
    --operational: #4cbd72;
    --degraded: #d9a441;
    --outage: #e2645f;
    --unknown: #8a8a85;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 3rem 1.25rem 4rem;
  background: var(--bg);
  color: var(--text);
  font: 16px/1.55 ui-sans-serif, -apple-system, "Segoe UI", Roboto, sans-serif;
}
main { max-width: 46rem; margin: 0 auto; }
h1 { font-size: 1.05rem; font-weight: 600; letter-spacing: 0.02em; margin: 0 0 2rem; color: var(--muted); }
.banner {
  border: 1px solid var(--border);
  border-left: 4px solid var(--level);
  background: var(--panel);
  border-radius: 8px;
  padding: 1.25rem 1.5rem;
  margin-bottom: 0.75rem;
}
.banner h2 { margin: 0; font-size: 1.5rem; font-weight: 650; color: var(--level); }
.banner p { margin: 0.4rem 0 0; color: var(--muted); }
.notes { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 0.9rem 0 0; padding: 0; list-style: none; }
.notes li {
  font-size: 0.8rem;
  color: var(--muted);
  border: 1px solid var(--border);
  border-radius: 999px;
  padding: 0.15rem 0.6rem;
}
.updated { color: var(--muted); font-size: 0.8rem; margin: 0 0 2.25rem; }
h3 { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); margin: 0 0 0.75rem; font-weight: 600; }
.tiers { border: 1px solid var(--border); border-radius: 8px; background: var(--panel); overflow: hidden; }
.tier { display: flex; align-items: baseline; gap: 0.85rem; padding: 0.85rem 1.25rem; border-top: 1px solid var(--border); }
.tier:first-child { border-top: 0; }
.dot { width: 0.6rem; height: 0.6rem; border-radius: 50%; background: var(--level); flex: none; }
.tier-name { font-weight: 550; }
.tier-blurb { color: var(--muted); font-size: 0.85rem; flex: 1; }
.tier-value { color: var(--level); font-variant-numeric: tabular-nums; font-size: 0.9rem; }
footer { margin-top: 2.5rem; color: var(--muted); font-size: 0.85rem; }
footer a { color: inherit; }
@media (max-width: 32rem) {
  .tier { flex-wrap: wrap; }
  .tier-blurb { flex-basis: 100%; padding-left: 1.45rem; }
}
`;

export function renderPage(snapshot: Snapshot, now: number): string {
  const state = pageState(snapshot, now);
  const tiers = tierStates(snapshot, TIERS);
  const updated = new Date(state.fetchedAt).toISOString().replace("T", " ").slice(0, 19);

  const notes = state.notes.length
    ? `<ul class="notes">${state.notes.map((n) => `<li>${escapeHtml(n)}</li>`).join("")}</ul>`
    : "";

  const rows = tiers
    .map(
      (tier) => `
      <div class="tier" style="--level: var(--${tier.level})">
        <span class="dot" role="img" aria-label="${LEVEL_LABEL[tier.level]}"></span>
        <span class="tier-name">${escapeHtml(tier.label)}</span>
        <span class="tier-blurb">${escapeHtml(tier.blurb)}</span>
        <span class="tier-value">${escapeHtml(tier.value)}</span>
      </div>`,
    )
    .join("");

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(state.headline)} — pitower status</title>
<meta name="description" content="Live availability of the services running on pitower.">
<meta name="robots" content="noindex">
<style>${STYLE}</style>
</head>
<body>
<main>
  <h1>pitower status</h1>
  <section class="banner" style="--level: var(--${state.level})">
    <h2>${escapeHtml(state.headline)}</h2>
    <p>${escapeHtml(state.detail)}</p>
    ${notes}
  </section>
  <p class="updated">Last reading ${escapeHtml(relativeAge(state.ageSeconds))} · ${escapeHtml(updated)} UTC${
    state.stale ? " · serving last known good" : ""
  }</p>

  <h3>Components</h3>
  <div class="tiers">${rows}
  </div>

  <footer>
    <p>Public availability is measured from a probe outside the network, so it reflects the path a
    visitor actually takes. Per-endpoint detail lives at <a href="https://up.wibrow.dev">up.wibrow.dev</a>.</p>
  </footer>
</main>
</body>
</html>
`;
}

export function renderJson(snapshot: Snapshot, now: number): unknown {
  return {
    ...pageState(snapshot, now),
    tiers: tierStates(snapshot, TIERS),
  };
}
