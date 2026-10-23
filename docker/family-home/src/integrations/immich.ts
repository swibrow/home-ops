import { cached, getJson } from "../lib/cache";
import { env } from "../lib/config";
import { isoDay } from "../lib/time";

type Memory = { type: string; data: { year: number }; assets: { id: string; type: string }[] };

const url = env("IMMICH_URL");
const key = env("IMMICH_API_KEY");

export const loadMemory = () =>
  url && key
    ? cached("immich", 3600, async () => {
        const memories = await getJson<Memory[]>(`${url}/api/memories?for=${isoDay()}&type=on_this_day`, {
          headers: { "x-api-key": key },
        });
        const memory = memories.find((m) => m.assets.some((a) => a.type === "IMAGE"));
        if (!memory) return undefined;
        return {
          year: memory.data.year,
          photos: memory.assets.filter((a) => a.type === "IMAGE").slice(0, 3).map((a) => a.id),
        };
      })
    : undefined;

export async function photo(id: string) {
  const memory = await loadMemory();
  if (!url || !key || !memory?.photos.includes(id)) return undefined;
  return fetch(`${url}/api/assets/${id}/thumbnail?size=preview`, {
    headers: { "x-api-key": key },
    signal: AbortSignal.timeout(8000),
  });
}
