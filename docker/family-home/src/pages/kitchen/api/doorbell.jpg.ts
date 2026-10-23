import type { APIRoute } from "astro";
import { doorbellSnapshot } from "../../../integrations/homeassistant";

export const GET: APIRoute = async () => {
  const res = await doorbellSnapshot()?.catch(() => undefined);
  if (!res?.ok) return new Response(null, { status: 404 });
  return new Response(res.body, { headers: { "Content-Type": "image/jpeg", "Cache-Control": "no-store" } });
};
