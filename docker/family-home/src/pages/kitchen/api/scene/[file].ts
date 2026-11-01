import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { APIRoute } from "astro";
import { sceneDir } from "../../../../integrations/comfyui";

export const GET: APIRoute = async ({ params }) => {
  const file = params.file ?? "";
  if (!/^[a-z]+-[a-z]+-[0-9a-f]{8}\.png$/.test(file)) return new Response(null, { status: 404 });
  const png = await readFile(join(sceneDir, file)).catch(() => undefined);
  if (!png) return new Response(null, { status: 404 });
  return new Response(png, { headers: { "Content-Type": "image/png", "Cache-Control": "public, max-age=31536000, immutable" } });
};
