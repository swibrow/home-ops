import type { APIRoute } from "astro";
import { doorbellActive } from "../../../integrations/homeassistant";

export const GET: APIRoute = async () => {
  const active = await doorbellActive()?.catch(() => false);
  return Response.json({ active: !!active }, { headers: { "Cache-Control": "no-store" } });
};
