import type { APIRoute } from "astro";
import { updateShopping } from "../../../integrations/homeassistant";

export const POST: APIRoute = async ({ request }) => {
  const { add, done } = await request.json().catch(() => ({}));
  const text = typeof add === "string" ? add.trim().slice(0, 100) : undefined;
  if (!text && typeof done !== "string") return new Response(null, { status: 400 });
  const ok = await updateShopping(text ? { add: text } : { done }).catch(() => false);
  return new Response(null, { status: ok ? 204 : 502 });
};
