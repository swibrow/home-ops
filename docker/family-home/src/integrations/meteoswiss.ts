import { createInterface } from "node:readline";
import { Readable } from "node:stream";
import type { ReadableStream } from "node:stream/web";
import { getJson } from "../lib/cache";
import { isoDay } from "../lib/time";

// MeteoSwiss open data local forecast: one CSV per parameter for every point in
// Switzerland, a new run every hour. https://opendatadocs.meteoswiss.ch/e-forecast-data/e4-local-forecast-data
const collection = "https://data.geo.admin.ch/api/stac/v1/collections/ch.meteoschweiz.ogd-local-forecasting";
const points = "https://data.geo.admin.ch/ch.meteoschweiz.ogd-local-forecasting/ogd-local-forecasting_meta_point.csv";

export type Forecast = { datetime: string; condition: string; temperature: number; templow?: number; precipitation?: number };

// MeteoSwiss weather symbols, 1 to 42 by day and 101 to 142 by night, as Home Assistant conditions.
const symbols: [string, number[]][] = [
  ["partlycloudy", [2, 3, 26]],
  ["cloudy", [4, 5, 35]],
  ["fog", [27, 28]],
  ["rainy", [6, 9, 14, 17, 29, 32, 33]],
  ["pouring", [20]],
  ["snowy-rainy", [7, 10, 15, 18, 21, 31]],
  ["snowy", [8, 11, 16, 19, 22, 30, 34]],
  ["lightning-rainy", [12, 13, 23, 24, 25, 36, 37, 38, 39, 40, 41, 42]],
];
const condition = (symbol: number) =>
  symbol % 100 === 1 ? (symbol > 100 ? "clear-night" : "sunny") : (symbols.find(([, s]) => s.includes(symbol % 100))?.[0] ?? "cloudy");

// Timestamps are UTC as YYYYMMDDHHMM.
const parseTime = (t: string) => Date.UTC(+t.slice(0, 4), +t.slice(4, 6) - 1, +t.slice(6, 8), +t.slice(8, 10), +t.slice(10, 12));

// The postal code point closest to the home zone.
async function nearest(lat: number, lon: number) {
  const res = await fetch(points, { signal: AbortSignal.timeout(30_000) });
  if (!res.ok) throw new Error(`${points} returned ${res.status}`);
  const [head, ...rows] = new TextDecoder("latin1").decode(await res.arrayBuffer()).trim().split(/\r?\n/);
  const col = Object.fromEntries(head.split(";").map((name, i) => [name, i]));
  const distance = (r: string[]) =>
    Math.hypot(+r[col.point_coordinates_wgs84_lat] - lat, (+r[col.point_coordinates_wgs84_lon] - lon) * Math.cos((lat * Math.PI) / 180));
  const point = rows
    .map((line) => line.split(";"))
    .filter((r) => r[col.point_type_id] === "2")
    .reduce((a, b) => (distance(b) < distance(a) ? b : a));
  if (!(distance(point) < 0.1)) throw new Error("no MeteoSwiss forecast point near the home zone");
  console.log(`[meteoswiss] forecasting for ${point[col.point_name]}`);
  return point[col.point_id];
}

// The newest run's file for each parameter; runs are filed under their UTC day.
async function latestFiles() {
  const files = new Map<string, string>();
  for (const days of [0, 1]) {
    const day = new Date(Date.now() - days * 86_400_000).toISOString().slice(0, 10).replaceAll("-", "");
    const item = await getJson<{ assets: Record<string, { href: string }> }>(`${collection}/items/${day}-ch`).catch(() => undefined);
    for (const [key, asset] of Object.entries(item?.assets ?? {}).sort(([a], [b]) => b.localeCompare(a))) {
      const parameter = key.split(".").at(-2)!;
      if (!files.has(parameter)) files.set(parameter, asset.href);
    }
    if (files.size) return files;
  }
  throw new Error("no MeteoSwiss local forecast run found");
}

// Hourly files are about 30 MB, so they are streamed and only the point's rows kept.
async function values(href: string | undefined, point: string) {
  if (!href) throw new Error("MeteoSwiss local forecast run is missing a parameter");
  const res = await fetch(href, { signal: AbortSignal.timeout(120_000) });
  if (!res.ok || !res.body) throw new Error(`${href} returned ${res.status}`);
  const prefix = `${point};2;`;
  const found = new Map<number, number>();
  for await (const line of createInterface({ input: Readable.fromWeb(res.body as ReadableStream) })) {
    if (!line.startsWith(prefix)) continue;
    const [, , time, value] = line.split(";");
    if (value !== "") found.set(parseTime(time), Number(value));
  }
  return found;
}

async function load(lat: number, lon: number) {
  const [point, files] = await Promise.all([nearest(lat, lon), latestFiles()]);
  const get = (parameter: string) => values(files.get(parameter), point);
  const temperature = await get("tre200h0");
  const rain = await get("rre150h0");
  const symbol = await get("jww003i0");
  const [high, low, dayRain, pictogram] = await Promise.all(["tre200px", "tre200pn", "rka150p0", "jp2000d0"].map(get));

  // Hourly values cover the hour before their timestamp, and symbols the three hours before.
  const hourly: Forecast[] = [...temperature].flatMap(([end, t]) => {
    const code = symbol.get(end) ?? symbol.get(end + 3_600_000) ?? symbol.get(end + 7_200_000);
    return code === undefined
      ? []
      : [{ datetime: new Date(end - 3_600_000).toISOString(), condition: condition(code), temperature: t, precipitation: rain.get(end) }];
  });
  // Daily values are stamped at midnight of their local day.
  const today = isoDay(new Date());
  const daily: Forecast[] = [...high].flatMap(([day, t]) => {
    const date = new Date(day).toISOString().slice(0, 10);
    const code = pictogram.get(day);
    return date < today || code === undefined
      ? []
      : [{ datetime: `${date}T12:00:00Z`, condition: condition(code), temperature: t, templow: low.get(day), precipitation: dayRain.get(day) }];
  });
  return { hourly, daily };
}

let latest: { at: number; value: Awaited<ReturnType<typeof load>> } | undefined;
let pending: Promise<NonNullable<typeof latest>["value"]> | undefined;
let retryAt = 0;

// Runs land hourly. A stale forecast is served while the next one downloads, so only
// the first load after a restart waits for it.
export function localForecast(lat: number, lon: number) {
  const now = Date.now();
  if (!pending && now > retryAt && (!latest || now - latest.at > 3_600_000)) {
    const started = now;
    pending = load(lat, lon)
      .then((value) => {
        latest = { at: Date.now(), value };
        console.log(`[meteoswiss] loaded ${value.hourly.length} hours and ${value.daily.length} days in ${Math.round((Date.now() - started) / 1000)}s`);
        return value;
      })
      .catch((error) => {
        retryAt = Date.now() + 600_000;
        throw error;
      })
      .finally(() => (pending = undefined));
    if (latest) pending.catch((error) => console.error("[meteoswiss]", error.message));
  }
  return latest ? Promise.resolve(latest.value) : (pending ?? Promise.reject(new Error("MeteoSwiss local forecast unavailable")));
}
