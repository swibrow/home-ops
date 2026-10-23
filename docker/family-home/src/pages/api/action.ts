import type { APIRoute } from "astro";
import { runAction } from "../../integrations/homeassistant";

export const POST: APIRoute = async ({ request }) => {
  const { id } = await request.json().catch(() => ({}));
  const ok = typeof id === "string" ? await runAction(id).catch(() => false) : undefined;
  return new Response(null, { status: ok === undefined ? 404 : ok ? 204 : 502 });
};
