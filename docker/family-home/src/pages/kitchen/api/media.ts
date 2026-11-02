import type { APIRoute } from "astro";
import { controlSpeaker, isMediaCommand, loadPlaying } from "../../../integrations/homeassistant";
import { settle } from "../../../lib/cache";

export const GET: APIRoute = async () =>
  Response.json((await settle("music", loadPlaying())) ?? null, { headers: { "Cache-Control": "no-store" } });

export const POST: APIRoute = async ({ request }) => {
  const { id, command, volume } = (await request.json().catch(() => ({}))) as { id?: string; command?: unknown; volume?: number };
  if (typeof id !== "string" || !isMediaCommand(command)) return new Response(null, { status: 400 });
  if (command === "volume" && !(typeof volume === "number" && volume >= 0 && volume <= 1)) return new Response(null, { status: 400 });
  const ok = await controlSpeaker(id, command, volume).catch(() => false);
  return new Response(null, { status: ok === undefined ? 404 : ok ? 204 : 502 });
};
