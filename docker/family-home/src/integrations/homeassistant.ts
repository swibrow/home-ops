import { cached, forget, getJson } from "../lib/cache";
import { config, env } from "../lib/config";
import { addDays, format, isoDay } from "../lib/time";

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

export type Button = { id: string; label: string; kind: "toggle" | "run"; on: boolean; available: boolean };

const services: Record<string, string> = { script: "turn_on", scene: "turn_on", button: "press", input_button: "press" };

const websocket = <T>(message: object) =>
  new Promise<T>((resolve, reject) => {
    const ws = new WebSocket(`${url!.replace(/^http/, "ws")}/api/websocket`);
    const fail = (error: Error) => {
      clearTimeout(timer);
      ws.close();
      reject(error);
    };
    const timer = setTimeout(() => fail(new Error("websocket timed out")), 5000);
    ws.onerror = () => fail(new Error("websocket failed"));
    ws.onmessage = ({ data }) => {
      const msg = JSON.parse(String(data));
      if (msg.type === "auth_required") ws.send(JSON.stringify({ type: "auth", access_token: token }));
      else if (msg.type === "auth_ok") ws.send(JSON.stringify({ id: 1, ...message }));
      else if (msg.type === "auth_invalid") fail(new Error("websocket auth rejected"));
      else if (msg.id === 1) {
        clearTimeout(timer);
        ws.close();
        if (msg.success) resolve(msg.result);
        else reject(new Error(msg.error?.message));
      }
    };
  });

const buttonEntities = () =>
  url && token && ha.buttons
    ? cached("ha:buttons", 60, async () => {
        const res = await fetch(`${url}/api/template`, {
          method: "POST",
          headers,
          body: JSON.stringify({ template: `{{ label_entities(${JSON.stringify(ha.buttons)}) | tojson }}` }),
          signal: AbortSignal.timeout(4000),
        });
        if (!res.ok) throw new Error(`template returned ${res.status}`);
        const ids = (await res.json()) as string[];
        const entries = ids.length
          ? await websocket<Record<string, { aliases: (string | null)[] }>>({ type: "config/entity_registry/get_entries", entity_ids: ids })
          : {};
        return ids.map((id) => ({ id, alias: entries[id]?.aliases.find((a) => !!a) ?? undefined }));
      })
    : Promise.resolve([]);

const guesses = new Map<string, { name: string; heard: number; ends: number }>();
const units: Record<string, number> = { hour: 3600, minute: 60, second: 1 };
const echoName = (s: State, suffix: string) => String(s.attributes.friendly_name).replace(new RegExp(`( echo)? ${suffix}$`, "i"), "");

// The Alexa integration polls Amazon every few minutes but voice events arrive at once, so a
// timer set by voice counts down from Alexa's reply until the next_timer sensor catches up.
function timers(states: State[]) {
  const now = Date.now();
  for (const s of states) {
    const command = String(s.attributes.voice_command ?? "");
    if (!/^event\..+_voice_event$/.test(s.entity_id) || !/timer/i.test(command)) continue;
    const name = echoName(s, "voice event");
    const heard = Date.parse(s.state);
    if (/cancel|stop|delete|remove/i.test(command)) {
      for (const [key, g] of guesses) if (g.name === name && g.heard < heard) guesses.delete(key);
      continue;
    }
    const seconds = [...String(s.attributes.voice_reply ?? "").matchAll(/(\d+)\s*(hour|minute|second)/gi)].reduce(
      (sum, [, n, unit]) => sum + Number(n) * units[unit.toLowerCase()],
      0,
    );
    if (seconds) guesses.set(s.entity_id + s.state, { name, heard, ends: heard + seconds * 1000 });
  }
  const known = states
    .filter((s) => /^sensor\..+_next_timer$/.test(s.entity_id) && Date.parse(s.state) > now - 60_000)
    .map((s) => ({ name: echoName(s, "next timer"), ends: Date.parse(s.state) }));
  for (const [key, g] of guesses) {
    if (g.ends < now - 60_000) guesses.delete(key);
    else if (!known.some((t) => t.name === g.name && Math.abs(t.ends - g.ends) < 15_000)) known.push(g);
  }
  return known.sort((a, b) => a.ends - b.ends).map((t) => ({ name: t.name, ends: new Date(t.ends).toISOString() }));
}

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
        const [states, daily, hourly, buttons] = await Promise.all([
          getJson<State[]>(`${url}/api/states`, { headers }),
          forecast("daily").catch(() => []),
          forecast("hourly").catch(() => []),
          buttonEntities().catch((error) => {
            console.error("[homeassistant] buttons:", error.message);
            return [];
          }),
        ]);
        const byId = new Map(states.map((s) => [s.entity_id, s]));
        const weather = byId.get(ha.weather);
        const sun = byId.get(ha.sun);
        const [today, ...ahead] = daily;
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
            days: ahead.slice(0, 3).map((d) => ({ at: new Date(d.datetime), ...summary(d) })),
          },
          sunElevation: sun ? Number(sun.attributes.elevation) : undefined,
          people: ha.people.flatMap((id) => {
            const p = byId.get(id);
            return p ? [{ id, name: p.attributes.friendly_name as string, home: p.state === "home" }] : [];
          }),
          actions: buttons
            .map(({ id, alias }): Button => {
              const s = byId.get(id);
              return {
                id,
                label: alias ?? s?.attributes.friendly_name ?? id,
                kind: id.split(".")[0] in services ? "run" : "toggle",
                on: s?.state === "on",
                available: !!s && s.state !== "unavailable",
              };
            })
            .sort((a, b) => b.kind.localeCompare(a.kind) || a.label.localeCompare(b.label)),
          timers: timers(states),
        };
      })
    : undefined;

export async function runAction(id: string) {
  if (!url || !token || !(await buttonEntities()).some((b) => b.id === id)) return undefined;
  const [domain] = id.split(".");
  const res = await callService(domain, services[domain] ?? "toggle", { entity_id: id });
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

// Only while someone is or just was at the door, so the open kitchen page can't unlock it at any time.
export async function unlockDoor() {
  const entity = ha.doorbell?.unlock;
  if (!url || !token || !entity) return undefined;
  const person = await getJson<State & { last_changed: string }>(`${url}/api/states/${ha.doorbell!.sensor}`, { headers });
  if (person.state !== "on" && Date.now() - Date.parse(person.last_changed) > 120_000) return false;
  const [domain] = entity.split(".");
  // lock.open also retracts the latch, so the door can be pushed open.
  const res = await callService(domain, domain === "lock" ? "open" : (services[domain] ?? "turn_on"), { entity_id: entity });
  return res.ok;
}

type When = { date?: string; dateTime?: string };
type CalendarEvent = { summary: string; start: When; end: When };
export type Happening = { summary: string; day: string; time?: string };

export const loadEvents = () =>
  url && token && ha.calendars?.length
    ? cached("ha:events", 60, async () => {
        const start = new Date();
        const range = `start=${start.toISOString()}&end=${addDays(start, 7).toISOString()}`;
        const lists = await Promise.all(
          ha.calendars!.map((id) => getJson<CalendarEvent[]>(`${url}/api/calendars/${id}?${range}`, { headers })),
        );
        const today = isoDay(start);
        return lists
          .flat()
          .map((e): Happening => {
            const at = e.start.dateTime ? new Date(e.start.dateTime) : undefined;
            const day = e.start.date ?? isoDay(at);
            return {
              summary: e.summary,
              day: day < today ? today : day,
              time: at && format(at, { hour: "2-digit", minute: "2-digit", hourCycle: "h23" }),
            };
          })
          .sort((a, b) => (a.day + (a.time ?? "")).localeCompare(b.day + (b.time ?? "")));
      })
    : undefined;

// Timed events last an hour; Home Assistant reads the naive times in its own timezone.
export async function addEvent({ summary, date, time }: { summary: string; date: string; time?: string }) {
  if (!url || !token || !ha.calendars?.length) return false;
  const naive = (d: Date) => d.toISOString().slice(0, 19).replace("T", " ");
  const start = new Date(`${date}T${time ?? "00:00"}:00Z`);
  const body = time
    ? { start_date_time: naive(start), end_date_time: naive(addDays(start, 1 / 24)) }
    : { start_date: date, end_date: isoDay(addDays(start, 1)) };
  const res = await callService("calendar", "create_event", { entity_id: ha.calendars[0], summary, ...body });
  forget("ha:events");
  return res.ok;
}
