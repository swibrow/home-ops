import type { APIRoute } from "astro";
import { config, env } from "../../../../lib/config";

const frigate = env("FRIGATE_URL");
const cameras = config.frigate?.cameras ?? [];
// Each camera's full stream, and its smaller _sub stream for the tiles.
const streams = new Set(cameras.flatMap((c) => [c, `${c}_sub`]));

// Relays a WebRTC offer to Frigate's go2rtc and returns its answer; the video then flows
// straight from Frigate to the display.
export const POST: APIRoute = async ({ params, request }) => {
  const stream = params.stream ?? "";
  if (!frigate || !streams.has(stream)) return new Response(null, { status: 404 });
  const { sdp } = (await request.json().catch(() => ({}))) as { sdp?: string };
  if (typeof sdp !== "string") return new Response(null, { status: 400 });
  const res = await fetch(`${frigate}/api/go2rtc/webrtc?src=${encodeURIComponent(stream)}`, {
    method: "POST",
    body: sdp,
    signal: AbortSignal.timeout(10_000),
  }).catch(() => undefined);
  if (!res?.ok) return new Response(null, { status: 502 });
  return new Response(await res.text(), { headers: { "Content-Type": "application/sdp", "Cache-Control": "no-store" } });
};
