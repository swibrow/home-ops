import type { APIRoute } from "astro";
import { addEvent } from "../../../integrations/homeassistant";

export const POST: APIRoute = async ({ request }) => {
  const { summary, date, time } = await request.json().catch(() => ({}));
  const title = typeof summary === "string" ? summary.trim().slice(0, 100) : "";
  if (!title || !/^\d{4}-\d{2}-\d{2}$/.test(date) || (time && !/^\d{2}:\d{2}$/.test(time))) return new Response(null, { status: 400 });
  const ok = await addEvent({ summary: title, date, time: time || undefined }).catch(() => false);
  return new Response(null, { status: ok ? 204 : 502 });
};
