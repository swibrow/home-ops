import type { APIRoute } from "astro";
import { photo } from "../../../integrations/immich";

export const GET: APIRoute = async ({ params }) => {
  const res = await photo(params.id!).catch(() => undefined);
  if (!res?.ok) return new Response(null, { status: 404 });
  return new Response(res.body, {
    headers: { "Content-Type": res.headers.get("content-type") ?? "image/jpeg", "Cache-Control": "private, max-age=86400" },
  });
};
