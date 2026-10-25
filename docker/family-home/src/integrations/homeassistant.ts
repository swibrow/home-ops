import { cached, forget, getJson } from "../lib/cache";
import { config, env } from "../lib/config";

type State = { entity_id: string; state: string; attributes: Record<string, any> };
type Forecast = { datetime: string; condition: string; temperature: number; templow?: number; precipitation?: number };

const url = env("HASS_URL");
const token = env("HASS_TOKEN");
const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
const ha = config.homeAssistant;

const conditions: Record<string, string> = {
  "clear-night": "Clear",
  cloudy: "Cloudy",
  exceptional: "Unusual weather",
  fog: "Foggy",
  hail: "Hail",
  lightning: "Thunderstorms",
  "lightning-rainy": "Thunder and rain",
  partlycloudy: "Partly cloudy",
  pouring: "Heavy rain",
  rainy: "Rain",
  snowy: "Snow",
  "snowy-rainy": "Sleet",
  sunny: "Sunny",
  windy: "Windy",
  "windy-variant": "Windy",
};

const callService = (domain: string, service: string, body: object, response = false) =>
  fetch(`${url}/api/services/${domain}/${service}${response ? "?return_response" : ""}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(5000),
  });

const forecast = (type: "daily" | "hourly") =>
  cached(`ha:forecast:${type}`, type === "daily" ? 1800 : 900, async () => {
    const res = await callService("weather", "get_forecasts", { entity_id: ha.weather, type }, true);
    if (!res.ok) throw new Error(`weather.get_forecasts returned ${res.status}`);
    const body = (await res.json()) as { service_response: Record<string, { forecast: Forecast[] }> };
    return body.service_response[ha.weather]?.forecast ?? [];
  });

const compass = (degrees: number) =>
  ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][Math.round(degrees / 45) % 8];

const summary = (day: Forecast) => ({
  condition: conditions[day.condition] ?? day.condition,
  high: Math.round(day.temperature),
  low: day.templow !== undefined ? Math.round(day.templow) : undefined,
  rain: day.precipitation,
});

export const loadHome = () =>
  url && token
    ? cached("ha:states", 20, async () => {
        const [states, daily, hourly] = await Promise.all([
          getJson<State[]>(`${url}/api/states`, { headers }),
          forecast("daily").catch(() => []),
          forecast("hourly").catch(() => []),
        ]);
        const byId = new Map(states.map((s) => [s.entity_id, s]));
        const weather = byId.get(ha.weather);
        const sun = byId.get(ha.sun);
        const [today, tomorrow] = daily;
        const hours = hourly.filter((h) => Date.parse(h.datetime) > Date.now() - 3_600_000).slice(0, 12);
        const wettest = Math.max(2, ...hours.map((h) => h.precipitation ?? 0));
        return {
          weather: weather && {
            condition: conditions[weather.state] ?? weather.state,
            temperature: Math.round(weather.attributes.temperature),
            high: today && Math.round(today.temperature),
            low: today?.templow !== undefined ? Math.round(today.templow) : undefined,
            rain: today?.precipitation,
            wind: Math.round(weather.attributes.wind_speed),
            windFrom: compass(weather.attributes.wind_bearing),
            humidity: Math.round(weather.attributes.humidity),
            uv: Math.round(weather.attributes.uv_index),
            sun: sun && [
              { label: "Sunrise", at: new Date(sun.attributes.next_rising) },
              { label: "Sunset", at: new Date(sun.attributes.next_setting) },
            ].sort((a, b) => a.at.getTime() - b.at.getTime()),
            hours: hours.map((h) => ({
              at: new Date(h.datetime),
              temperature: Math.round(h.temperature),
              rain: h.precipitation ?? 0,
              share: (h.precipitation ?? 0) / wettest,
            })),
            tomorrow: tomorrow && summary(tomorrow),
          },
          sunElevation: sun ? Number(sun.attributes.elevation) : undefined,
          people: ha.people.flatMap((id) => {
            const p = byId.get(id);
            return p ? [{ name: p.attributes.friendly_name as string, home: p.state === "home" }] : [];
          }),
          actions: ha.actions.map((a) => {
            const s = byId.get(a.entity);
            return { ...a, on: s?.state === "on", available: !!s && s.state !== "unavailable" };
          }),
          timers: states
            .filter((s) => /^sensor\..+_next_timer$/.test(s.entity_id) && Date.parse(s.state) > Date.now() - 60_000)
            .map((s) => ({
              name: String(s.attributes.friendly_name).replace(/( echo)? next timer$/i, ""),
              ends: new Date(s.state).toISOString(),
            }))
            .sort((a, b) => a.ends.localeCompare(b.ends)),
        };
      })
    : undefined;

export async function runAction(id: string) {
  const action = ha.actions.find((a) => a.id === id);
  if (!action || !url || !token) return undefined;
  const [domain] = action.entity.split(".");
  const res = await callService(domain, action.kind === "toggle" ? "toggle" : "turn_on", { entity_id: action.entity });
  forget("ha:states");
  return res.ok;
}

type TodoItem = { uid: string; summary: string; status: string };

export const loadShopping = () =>
  url && token && ha.shoppingList
    ? cached("ha:shopping", 15, async () => {
        const res = await callService("todo", "get_items", { entity_id: ha.shoppingList, status: ["needs_action"] }, true);
        if (!res.ok) throw new Error(`todo.get_items returned ${res.status}`);
        const body = (await res.json()) as { service_response: Record<string, { items: TodoItem[] }> };
        return body.service_response[ha.shoppingList!]?.items.map(({ uid, summary }) => ({ uid, summary })) ?? [];
      })
    : undefined;

export async function updateShopping(change: { add?: string; done?: string }) {
  if (!url || !token || !ha.shoppingList) return false;
  const res = change.add
    ? await callService("todo", "add_item", { entity_id: ha.shoppingList, item: change.add })
    : await callService("todo", "update_item", { entity_id: ha.shoppingList, item: change.done, status: "completed" });
  forget("ha:shopping");
  return res.ok;
}

export const doorbellActive = () =>
  url && token && ha.doorbell
    ? cached("ha:doorbell", 3, async () => {
        const state = await getJson<State>(`${url}/api/states/${ha.doorbell!.sensor}`, { headers });
        return state.state === "on";
      })
    : undefined;

export const doorbellSnapshot = () =>
  url && token && ha.doorbell
    ? fetch(`${url}/api/camera_proxy/${ha.doorbell.camera}`, { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(5000) })
    : undefined;
