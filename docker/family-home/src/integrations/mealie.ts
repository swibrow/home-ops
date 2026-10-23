import { cached, getJson } from "../lib/cache";
import { config, env } from "../lib/config";
import { addDays, isoDay } from "../lib/time";

type Entry = { date: string; entryType: string; title: string; text: string; recipe?: { id: string; name: string; slug: string } | null };

const api = env("MEALIE_URL");
const token = env("MEALIE_TOKEN");
const order = ["breakfast", "lunch", "dinner", "side", "dessert", "snack", "drink"];

export type Meal = { date: string; type: string; name: string; href?: string; image?: string };

export const loadMeals = () =>
  api && token
    ? cached("mealie", 300, async () => {
        const start = isoDay();
        const end = isoDay(addDays(new Date(), 6));
        const res = await getJson<{ items: Entry[] }>(
          `${api}/api/households/mealplans?start_date=${start}&end_date=${end}&perPage=100`,
          { headers: { Authorization: `Bearer ${token}` } },
        );
        const { url, group } = config.mealie;
        return res.items
          .map(
            (e): Meal => ({
              date: e.date,
              type: e.entryType,
              name: e.recipe?.name ?? e.title,
              href: e.recipe ? `${url}/g/${group}/r/${e.recipe.slug}` : undefined,
              image: e.recipe ? `${url}/api/media/recipes/${e.recipe.id}/images/min-original.webp` : undefined,
            }),
          )
          .sort((a, b) => a.date.localeCompare(b.date) || order.indexOf(a.type) - order.indexOf(b.type));
      })
    : undefined;
