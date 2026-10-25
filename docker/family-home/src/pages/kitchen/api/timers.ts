import type { APIRoute } from "astro";
import { loadHome } from "../../../integrations/homeassistant";
import { settle } from "../../../lib/cache";

export const GET: APIRoute = async () => {
  const home = await settle("homeassistant", loadHome());
  return Response.json(home?.timers ?? [], { headers: { "Cache-Control": "no-store" } });
};
