import type { APIRoute } from "astro";
import { loadLayout, parseLayout, saveLayout } from "../../../lib/layout";

export const GET: APIRoute = async () => Response.json(await loadLayout(), { headers: { "Cache-Control": "no-store" } });

export const PUT: APIRoute = async ({ request }) => {
  const layout = parseLayout(await request.json().catch(() => undefined));
  if (!layout) return new Response(null, { status: 400 });
  await saveLayout(layout);
  return Response.json(layout);
};
