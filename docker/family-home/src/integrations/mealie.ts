import { cached, forget, getJson } from "../lib/cache";
import { config, env } from "../lib/config";
import { addDays, isoDay } from "../lib/time";

type Entry = { id: number; date: string; entryType: string; title: string; text: string; recipe?: { id: string; name: string; slug: string } | null };
type Ingredient = { display?: string; note?: string; food?: { name: string; householdsWithIngredientFood?: string[] } | null };

const api = env("MEALIE_URL");
const token = env("MEALIE_TOKEN");
const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
const order = ["breakfast", "lunch", "dinner", "side", "dessert", "snack", "drink"];
export const mealTypes = ["breakfast", "lunch", "dinner"] as const;

// Category slugs offered for each meal. Recipes without a category show for every meal.
const courses: Record<string, string[]> = { breakfast: ["breakfast"], lunch: ["main", "side", "snack"], dinner: ["main"] };

export type Meal = { id: number; date: string; type: string; name: string; slug?: string; href?: string; image?: string };
// Season tag slugs by month, January first. Recipes without a season tag suit the whole year.
const seasons = ["winter", "winter", "spring", "spring", "spring", "summer", "summer", "summer", "autumn", "autumn", "autumn", "winter"];

export type Recipe = { id: string; name: string; image: string; courses: string[]; seasons: string[] };

export const suits = (recipe: Recipe, type: string) => !recipe.courses.length || recipe.courses.some((c) => courses[type]?.includes(c));
export const inSeason = (recipe: Recipe, date: string) => !recipe.seasons.length || recipe.seasons.includes(seasons[Number(date.slice(5, 7)) - 1]);

const image = (recipeId: string) => `${config.mealie.url}/api/media/recipes/${recipeId}/images/min-original.webp`;

const plan = (start: string, end: string) =>
  cached(`mealie:plan:${start}`, 300, async () => {
    const res = await getJson<{ items: Entry[] }>(`${api}/api/households/mealplans?start_date=${start}&end_date=${end}&perPage=100`, { headers });
    const { url, group } = config.mealie;
    return res.items
      .map(
        (e): Meal => ({
          id: e.id,
          date: e.date,
          type: e.entryType,
          name: e.recipe?.name ?? e.title,
          slug: e.recipe?.slug,
          href: e.recipe ? `${url}/g/${group}/r/${e.recipe.slug}` : undefined,
          image: e.recipe ? image(e.recipe.id) : undefined,
        }),
      )
      .sort((a, b) => a.date.localeCompare(b.date) || order.indexOf(a.type) - order.indexOf(b.type));
  });

export const loadMeals = () => (api && token ? plan(isoDay(), isoDay(addDays(new Date(), 6))) : undefined);

export const weekDays = (offset: number) => {
  const today = new Date(`${isoDay()}T12:00:00Z`);
  const monday = addDays(today, 7 * offset - ((today.getUTCDay() + 6) % 7));
  return Array.from({ length: 7 }, (_, i) => addDays(monday, i).toISOString().slice(0, 10));
};

export const loadWeek = (offset: number) => {
  if (!api || !token) return undefined;
  const days = weekDays(offset);
  return plan(days[0], days[6]);
};

export const loadRecipes = () =>
  api && token
    ? cached("mealie:recipes", 300, async () => {
        const res = await getJson<{ items: { id: string; name: string; recipeCategory: { slug: string }[]; tags: { slug: string }[] }[] }>(
          `${api}/api/recipes?perPage=-1&orderBy=name&orderDirection=asc`,
          { headers },
        );
        return res.items.map(
          (r): Recipe => ({
            id: r.id,
            name: r.name,
            image: image(r.id),
            courses: r.recipeCategory.map((c) => c.slug),
            seasons: r.tags.map((t) => t.slug).filter((t) => seasons.includes(t)),
          }),
        );
      })
    : undefined;

const forgetPlans = () => {
  forget(`mealie:plan:${isoDay()}`);
  for (const offset of [0, 1]) forget(`mealie:plan:${weekDays(offset)[0]}`);
};

export async function changeMeal(change: { add: { date: string; type: string; recipeId?: string; title?: string } } | { random: { date: string; type: string } } | { remove: number }) {
  if (!api || !token) return false;
  if ("random" in change) {
    const { date, type } = change.random;
    const choices = (await loadRecipes()!).filter((r) => suits(r, type) && inSeason(r, date));
    if (!choices.length) return false;
    change = { add: { date, type, recipeId: choices[Math.floor(Math.random() * choices.length)].id } };
  }
  const res =
    "add" in change
      ? await fetch(`${api}/api/households/mealplans`, {
          method: "POST",
          headers,
          body: JSON.stringify({ date: change.add.date, entryType: change.add.type, recipeId: change.add.recipeId, title: change.add.title ?? "" }),
          signal: AbortSignal.timeout(5000),
        })
      : await fetch(`${api}/api/households/mealplans/${change.remove}`, { method: "DELETE", headers, signal: AbortSignal.timeout(5000) });
  forgetPlans();
  return res.ok;
}

const ingredients = (slug: string) =>
  cached(`mealie:recipe:${slug}`, 900, async () => {
    const recipe = await getJson<{ recipeIngredient: Ingredient[] }>(`${api}/api/recipes/${slug}`, { headers });
    return recipe.recipeIngredient;
  });

// Parsed ingredients collapse to the food name so two recipes needing onions add one item;
// unparsed ones keep their text. Foods marked as on hand in Mealie are left out.
export async function weekShopping(meals: Meal[]) {
  const slugs = [...new Set(meals.flatMap((m) => (m.slug ? [m.slug] : [])))];
  const lists = await Promise.all(slugs.map((slug) => ingredients(slug).catch(() => [])));
  const items = new Map<string, string>();
  for (const ingredient of lists.flat()) {
    if (ingredient.food?.householdsWithIngredientFood?.length) continue;
    const text = (ingredient.food?.name ?? ingredient.display ?? ingredient.note ?? "").trim();
    if (text) items.set(text.toLowerCase(), text.charAt(0).toUpperCase() + text.slice(1));
  }
  return [...items.values()];
}
