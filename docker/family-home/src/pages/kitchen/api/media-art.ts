import type { APIRoute } from "astro";
import { speakerArt } from "../../../integrations/homeassistant";

export const GET: APIRoute = async ({ url }) => {
  const res = await speakerArt(url.searchParams.get("id") ?? "")?.catch(() => undefined);
  if (!res?.ok) return new Response(null, { status: 404 });
  return new Response(res.body, { headers: { "Content-Type": res.headers.get("Content-Type") ?? "image/jpeg", "Cache-Control": "max-age=3600" } });
};
