import { version } from "../../lib/version";

export const GET = () => new Response(version, { headers: { "Cache-Control": "no-store" } });
