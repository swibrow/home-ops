import { cached, forget, getJson } from "../lib/cache";
import { config, env } from "../lib/config";

type State = { entity_id: string; state: string; attributes: Record<string, any> };
type Forecast = { condition: string; temperature: number; templow?: number; precipitation?: number };

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

const forecast = () =>
  cached("ha:forecast", 1800, async () => {
    const res = await callService("weather", "get_forecasts", { entity_id: ha.weather, type: "daily" }, true);
    if (!res.ok) throw new Error(`weather.get_forecasts returned ${res.status}`);
    const body = (await res.json()) as { service_response: Record<string, { forecast: Forecast[] }> };
    return body.service_response[ha.weather]?.forecast[0];
  });

export const loadHome = () =>
  url && token
    ? cached("ha:states", 20, async () => {
        const [states, today] = await Promise.all([
          getJson<State[]>(`${url}/api/states`, { headers }),
          forecast().catch(() => undefined),
        ]);
        const byId = new Map(states.map((s) => [s.entity_id, s]));
        const weather = byId.get(ha.weather);
        const sun = byId.get(ha.sun);
        return {
          weather: weather && {
            condition: conditions[weather.state] ?? weather.state,
            temperature: Math.round(weather.attributes.temperature),
            high: today && Math.round(today.temperature),
            low: today?.templow !== undefined ? Math.round(today.templow) : undefined,
            rain: today?.precipitation,
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
