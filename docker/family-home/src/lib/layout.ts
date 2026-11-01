import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { isWidget, type WidgetId } from "./widgets";

export type Page = { id: string; name: string; widgets: WidgetId[] };
export type Layout = { pages: Page[] };

const dir = process.env.DATA_DIR ?? "./data";
const file = join(dir, "layout.json");

export const fallback: Layout = {
  pages: [
    { id: "home", name: "Home", widgets: ["dinner", "shopping", "lights", "calendar"] },
    { id: "media", name: "Media", widgets: ["coming", "photos"] },
    { id: "meals", name: "Meals", widgets: ["meals"] },
  ],
};

// Each widget appears at most once, since widgets carry fixed element ids.
export function parseLayout(value: unknown): Layout | undefined {
  const pages = (value as Layout | null)?.pages;
  if (!Array.isArray(pages) || !pages.length || pages.length > 8) return undefined;
  const ids = new Set<string>();
  const placed = new Set<string>();
  const clean: Page[] = [];
  for (const page of pages) {
    const { id, widgets } = page ?? {};
    const name = typeof page?.name === "string" ? page.name.trim() : "";
    if (typeof id !== "string" || !/^[\w-]{1,32}$/.test(id) || ids.has(id)) return undefined;
    if (!name || name.length > 24 || !Array.isArray(widgets)) return undefined;
    for (const w of widgets) {
      if (!isWidget(w) || placed.has(w)) return undefined;
      placed.add(w);
    }
    ids.add(id);
    clean.push({ id, name, widgets });
  }
  return { pages: clean };
}

export async function loadLayout() {
  try {
    return parseLayout(JSON.parse(await readFile(file, "utf8"))) ?? fallback;
  } catch {
    return fallback;
  }
}

export async function saveLayout(layout: Layout) {
  await mkdir(dir, { recursive: true });
  const temp = `${file}.${process.pid}.${Date.now()}.tmp`;
  await writeFile(temp, JSON.stringify(layout, null, 2));
  await rename(temp, file);
}
