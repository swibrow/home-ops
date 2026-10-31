import type { APIRoute } from "astro";
import { unlockDoor } from "../../../integrations/homeassistant";

export const POST: APIRoute = async () => {
  const ok = await unlockDoor()?.catch(() => false);
  return new Response(null, { status: ok === undefined ? 404 : ok ? 204 : 409 });
};
