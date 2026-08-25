import { fetchSnapshot, type Snapshot } from "./kromgo";
import { renderJson, renderPage } from "./render";

export interface Env {
  /** Last-known-good snapshot. The only reason this page survives an outage. */
  STATUS_SNAPSHOT: KVNamespace;
  /** kromgo origin, e.g. https://kromgo.wibrow.dev. */
  KROMGO_ORIGIN: string;
}

const KEY = "snapshot:v1";

/**
 * How long a stored snapshot is served without touching kromgo. The scheduled
 * handler refreshes every minute, so on a healthy day no visitor request ever
 * hits the cluster at all.
 */
const FRESH_FOR_MS = 60 * 1000;

async function readSnapshot(env: Env): Promise<Snapshot | null> {
  return await env.STATUS_SNAPSHOT.get<Snapshot>(KEY, "json");
}

async function refresh(env: Env, now: number): Promise<Snapshot | null> {
  const snapshot = await fetchSnapshot(env.KROMGO_ORIGIN, now);
  // Only a successful fetch is ever written. A failed one must leave the
  // stored snapshot alone - overwriting it with nothing is how a status page
  // ends up blank at the exact moment it matters.
  if (snapshot) await env.STATUS_SNAPSHOT.put(KEY, JSON.stringify(snapshot));
  return snapshot;
}

function html(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      // Short enough that the displayed age stays roughly honest, long enough
      // to absorb a burst of traffic without re-rendering per request.
      "cache-control": "public, max-age=15",
    },
  });
}

const NO_DATA_PAGE = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Status unavailable — pitower status</title>
<style>body{margin:0;padding:4rem 1.5rem;background:#121211;color:#eceae5;
font:16px/1.6 ui-sans-serif,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:32rem;margin:0 auto}h1{font-size:1.35rem}p{color:#9b9b95}</style>
</head><body><main>
<h1>Status unavailable</h1>
<p>This page has never managed to collect a reading, so it has nothing to show -
not even a stale one. That is itself a signal: the monitoring path is down.</p>
</main></body></html>
`;

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const now = Date.now();

    let snapshot = await readSnapshot(env);

    if (!snapshot) {
      // Cold start with nothing stored: this is the one path that must block
      // on kromgo, because there is no last-known-good to fall back to.
      snapshot = await refresh(env, now);
    } else if (now - snapshot.fetchedAt > FRESH_FOR_MS) {
      // Stale-while-revalidate. The visitor gets the stored reading straight
      // away and the refresh runs after the response, so a slow or dead origin
      // never becomes a slow status page.
      ctx.waitUntil(refresh(env, now));
    }

    if (!snapshot) {
      return url.pathname === "/api/status.json"
        ? Response.json({ error: "no snapshot available" }, { status: 503 })
        : html(NO_DATA_PAGE, 503);
    }

    if (url.pathname === "/api/status.json") {
      return Response.json(renderJson(snapshot, now), {
        headers: { "cache-control": "public, max-age=15" },
      });
    }

    if (url.pathname !== "/") {
      return new Response("Not found", { status: 404 });
    }

    return html(renderPage(snapshot, now));
  },

  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(refresh(env, Date.now()));
  },
};
