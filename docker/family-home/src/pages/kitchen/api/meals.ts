import type { APIRoute } from "astro";
import { changeMeal, mealTypes } from "../../../integrations/mealie";

const isDate = (value: unknown): value is string => typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value);
const isType = (value: unknown): value is string => mealTypes.includes(value as (typeof mealTypes)[number]);

export const POST: APIRoute = async ({ request }) => {
  const { add, random, remove } = await request.json().catch(() => ({}));
  let change: Parameters<typeof changeMeal>[0] | undefined;
  if (add && isDate(add.date) && isType(add.type)) {
    const title = typeof add.title === "string" ? add.title.trim().slice(0, 60) : "";
    const recipeId = typeof add.recipeId === "string" ? add.recipeId : undefined;
    if (recipeId || title) change = { add: { date: add.date, type: add.type, recipeId, title: recipeId ? undefined : title } };
  } else if (random && isDate(random.date) && isType(random.type)) {
    change = { random: { date: random.date, type: random.type } };
  } else if (Number.isInteger(remove)) {
    change = { remove };
  }
  if (!change) return new Response(null, { status: 400 });
  const ok = await changeMeal(change).catch(() => false);
  return new Response(null, { status: ok ? 204 : 502 });
};
