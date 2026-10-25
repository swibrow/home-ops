import { config, env } from "./config";

export type Viewer = { username?: string; name?: string; groups: string[] };

// Kanidm names users and groups by SPN (sam@idm.wibrow.dev); config uses the short name.
const short = (spn: unknown) => String(spn).split("@")[0];

// Envoy Gateway sets x-id-token after the Kanidm login and replaces any value the client sent.
export function viewer(headers: Headers): Viewer {
  const token = headers.get("x-id-token");
  if (!token) return { username: env("DEV_USER"), name: env("DEV_NAME"), groups: env("DEV_GROUPS")?.split(",") ?? [] };
  try {
    const claims = JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString());
    return {
      username: claims.preferred_username && short(claims.preferred_username),
      name: String(claims.name ?? short(claims.preferred_username)).split(" ")[0],
      groups: Array.isArray(claims.groups) ? claims.groups.map(short) : [],
    };
  } catch {
    return { groups: [] };
  }
}

export const canSee = (v: Viewer, item: { groups?: string[] }) => !item.groups || item.groups.some((g) => v.groups.includes(g));

export const personFor = (v: Viewer) => (v.username ? config.people?.[v.username] : undefined);
