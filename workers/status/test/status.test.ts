import { afterEach, describe, expect, test } from "bun:test";
import { BADGE_IDS, fetchSnapshot, TIERS, type Badge, type Snapshot } from "../src/kromgo";
import { renderPage } from "../src/render";
import { formatRatio, pageState, relativeAge, STALE_AFTER_MS, tierStates } from "../src/state";

const NOW = 1_760_000_000_000;

function badge(id: string, result: number, value = String(result)): Badge {
  return { id, title: id, value, color: "green", result };
}

function snapshot(results: Record<string, number>, fetchedAt = NOW): Snapshot {
  const badges: Record<string, Badge> = {};
  for (const [id, result] of Object.entries(results)) badges[id] = badge(id, result);
  return { fetchedAt, badges };
}

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

function stubFetch(handler: (id: string) => Response | Promise<Response>): void {
  globalThis.fetch = ((input: RequestInfo | URL) => {
    const id = new URL(String(input)).pathname.split("/").pop() ?? "";
    return Promise.resolve(handler(id));
  }) as typeof fetch;
}

describe("fetchSnapshot", () => {
  test("returns null when nothing answers, so the caller keeps last known good", async () => {
    stubFetch(() => {
      throw new Error("tunnel down");
    });
    expect(await fetchSnapshot("https://kromgo.example", NOW)).toBeNull();
  });

  test("omits badges that fail rather than carrying a stale value into a fresh snapshot", async () => {
    stubFetch((id) =>
      id === "tier_power"
        ? new Response("not found", { status: 404 })
        : Response.json({ id, title: id, value: "100%", color: "green", result: 100 }),
    );
    const result = await fetchSnapshot("https://kromgo.example", NOW);
    expect(result).not.toBeNull();
    expect(Object.keys(result!.badges)).toHaveLength(BADGE_IDS.length - 1);
    expect(result!.badges.tier_power).toBeUndefined();
    expect(result!.fetchedAt).toBe(NOW);
  });

  test("rejects a malformed body instead of rendering NaN", async () => {
    stubFetch(() => Response.json({ id: "x", value: 100, result: "100" }));
    expect(await fetchSnapshot("https://kromgo.example", NOW)).toBeNull();
  });
});

describe("pageState", () => {
  test("all public services reachable reads as operational", () => {
    const state = pageState(snapshot({ status_public: 100, status_health: 1 }), NOW);
    expect(state.level).toBe("operational");
    expect(state.headline).toBe("All systems operational");
  });

  test("some public services unreachable reads as a partial outage", () => {
    const state = pageState(snapshot({ status_public: 50, status_health: 1 }), NOW);
    expect(state.level).toBe("degraded");
    expect(state.headline).toBe("Partial outage");
    expect(state.detail).toContain("50%");
  });

  test("nothing reachable reads as a major outage", () => {
    const state = pageState(snapshot({ status_public: 0, status_health: 1 }), NOW);
    expect(state.level).toBe("outage");
    expect(state.headline).toBe("Major outage");
  });

  test("the -1 sentinel reads as unknown, never as an outage", () => {
    const state = pageState(snapshot({ status_public: -1, status_health: 1 }), NOW);
    expect(state.level).toBe("unknown");
    expect(state.headline).toBe("Public availability unknown");
  });

  test("a missing badge reads as unknown, never as an outage", () => {
    const state = pageState(snapshot({ status_health: 1 }), NOW);
    expect(state.level).toBe("unknown");
  });

  test("degraded internals lower an otherwise operational page", () => {
    const state = pageState(snapshot({ status_public: 100, status_health: 0.98 }), NOW);
    expect(state.level).toBe("degraded");
    expect(state.headline).toBe("Operational with degraded internals");
  });

  test("healthy internals never raise a public outage", () => {
    const state = pageState(snapshot({ status_public: 0, status_health: 1 }), NOW);
    expect(state.level).toBe("outage");
  });

  test("a snapshot older than the stale window reads as unknown, not as the last green value", () => {
    const old = snapshot({ status_public: 100, status_health: 1 }, NOW - STALE_AFTER_MS - 1000);
    const state = pageState(old, NOW);
    expect(state.stale).toBe(true);
    expect(state.level).toBe("unknown");
    expect(state.headline).toBe("Status unknown");
  });

  test("counts are surfaced as notes, and missing signals never flip the level", () => {
    const state = pageState(
      snapshot({ status_public: 100, status_health: 1, status_down: 2, status_degraded: 1, status_stale: 3 }),
      NOW,
    );
    expect(state.level).toBe("operational");
    expect(state.notes).toEqual(["2 components down", "1 component degraded", "3 signals missing"]);
  });

  test("zero counts produce no notes", () => {
    const state = pageState(
      snapshot({ status_public: 100, status_health: 1, status_down: 0, status_degraded: 0, status_stale: 0 }),
      NOW,
    );
    expect(state.notes).toEqual([]);
  });
});

describe("tierStates", () => {
  test("maps ratios to levels and leaves absent tiers unknown", () => {
    const states = tierStates(snapshot({ tier_edge: 100, tier_app: 85, tier_node: 0 }), TIERS);
    const byId = Object.fromEntries(states.map((s) => [s.id, s]));
    expect(byId.tier_edge.level).toBe("operational");
    expect(byId.tier_edge.value).toBe("100%");
    expect(byId.tier_app.level).toBe("degraded");
    expect(byId.tier_app.value).toBe("85%");
    expect(byId.tier_node.level).toBe("outage");
    expect(byId.tier_power.level).toBe("unknown");
    expect(byId.tier_power.value).toBe("unknown");
  });

  test("a ratio just under 100 never renders as 100%, which would contradict its own dot", () => {
    const [edge] = tierStates(snapshot({ tier_edge: 99.78 }), [TIERS[0]]);
    expect(edge.level).toBe("degraded");
    expect(edge.value).toBe("99%");
  });
});

describe("formatRatio", () => {
  test.each([
    [100, "100%"],
    [99.999, "99%"],
    [84.93, "84%"],
    [0, "0%"],
  ])("%d renders as %s", (ratio, expected) => {
    expect(formatRatio(ratio as number)).toBe(expected);
  });
});

describe("relativeAge", () => {
  test.each([
    [12, "12s ago"],
    [300, "5m ago"],
    [7200, "2h ago"],
    [172_800, "2d ago"],
  ])("%i seconds reads as %s", (seconds, expected) => {
    expect(relativeAge(seconds as number)).toBe(expected);
  });
});

describe("renderPage", () => {
  test("renders the headline, every tier and the last-reading line", () => {
    const html = renderPage(snapshot({ status_public: 100, status_health: 1 }), NOW + 30_000);
    expect(html).toContain("All systems operational");
    expect(html).toContain("30s ago");
    for (const tier of TIERS) expect(html).toContain(tier.label);
  });

  test("says so when it is serving a last-known-good reading", () => {
    const old = snapshot({ status_public: 100, status_health: 1 }, NOW - STALE_AFTER_MS - 1000);
    const html = renderPage(old, NOW);
    expect(html).toContain("serving last known good");
    expect(html).not.toContain("All systems operational");
  });

  test("escapes values that reach the page from kromgo", () => {
    const evil = snapshot({ status_public: 100, status_health: 1 });
    evil.badges.status_down = { ...badge("status_down", 1), value: "<script>x</script>" };
    const html = renderPage(evil, NOW);
    expect(html).not.toContain("<script>");
  });
});
