import { cached, getJson } from "../lib/cache";
import { config, env } from "../lib/config";

type Result = { metric: { name: string }; value: [number, string] };

const url = env("PROMETHEUS_URL");

export const loadStatus = () =>
  url
    ? cached("status", 60, async () => {
        const res = await getJson<{ data: { result: Result[] } }>(
          `${url}/api/v1/query?query=${encodeURIComponent("max by (name) (gatus_results_endpoint_success)")}`,
        );
        const up = new Map(res.data.result.map((r) => [r.metric.name, r.value[1] === "1"]));
        return config.categories.flatMap((c) => c.apps).filter((a) => a.status && up.get(a.status) === false);
      })
    : undefined;
