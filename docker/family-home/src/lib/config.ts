import { readFileSync } from "node:fs";
import { parse } from "yaml";

export type App = { name: string; description: string; url: string; icon?: string; status?: string };
export type Category = { name: string; namespace: string; apps: App[] };

export type Config = {
  household: string;
  timezone: string;
  currency: string;
  analyticsSiteId?: string;
  homeAssistant: {
    weather: string;
    sun: string;
    people: string[];
    buttons?: string;
    shoppingList?: string;
    doorbell?: { sensor: string; camera: string };
  };
  jellyfin: { url: string; userId: string };
  immich: { url: string };
  mealie: { url: string; group: string };
  categories: Category[];
};

export const config: Config = parse(
  readFileSync(process.env.CONFIG_PATH ?? "../../kubernetes/apps/pitower/selfhosted/family-home/config.yaml", "utf8"),
);

export const env = (name: string) => process.env[name] || undefined;
