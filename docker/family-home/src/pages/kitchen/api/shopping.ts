import type { APIRoute } from "astro";
import { updateShopping } from "../../../integrations/homeassistant";

const clean = (value: unknown) => (typeof value === "string" ? value.trim().slice(0, 100) : "");

export const POST: APIRoute = async ({ request }) => {
  const { add, done } = await request.json().catch(() => ({}));
  const items = (Array.isArray(add) ? add.slice(0, 60) : [add]).map(clean).filter(Boolean);
  if (!items.length && typeof done !== "string") return new Response(null, { status: 400 });
  let ok = true;
  if (items.length) for (const item of items) ok = (await updateShopping({ add: item }).catch(() => false)) && ok;
  else ok = await updateShopping({ done }).catch(() => false);
  return new Response(null, { status: ok ? 204 : 502 });
};
