import { cached, getJson } from "../lib/cache";
import { env } from "../lib/config";
import { isoDay } from "../lib/time";

type Memory = { type: string; data: { year: number }; assets: { id: string; type: string }[] };

const url = env("IMMICH_URL");
const key = env("IMMICH_API_KEY");

const memories = () =>
  cached("immich", 3600, () =>
    getJson<Memory[]>(`${url}/api/memories?for=${isoDay()}&type=on_this_day`, { headers: { "x-api-key": key! } }),
  );

const images = (memory: Memory) => memory.assets.filter((a) => a.type === "IMAGE").map((a) => a.id);

export const loadMemory = () =>
  url && key
    ? memories().then((list) => {
        const memory = list.find((m) => images(m).length);
        return memory && { year: memory.data.year, photos: images(memory).slice(0, 3) };
      })
    : undefined;

// A few photos from each year, newest year first, for the kitchen photo frame.
export const loadOnThisDay = () =>
  url && key
    ? memories().then((list) => list.flatMap((m) => images(m).slice(0, 4).map((id) => ({ id, year: m.data.year }))))
    : undefined;

export async function photo(id: string) {
  if (!url || !key) return undefined;
  const list = await memories();
  if (!list.some((m) => images(m).includes(id))) return undefined;
  return fetch(`${url}/api/assets/${id}/thumbnail?size=preview`, {
    headers: { "x-api-key": key },
    signal: AbortSignal.timeout(8000),
  });
}
