import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { isSize, isWidget, widgets as registry, type Size, type WidgetId } from "./widgets";

export type Page = { id: string; name: string; widgets: WidgetId[] };
export type Layout = { pages: Page[]; sizes?: Partial<Record<WidgetId, Size>> };

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
  const sizes = Object.fromEntries(
    Object.entries((value as Layout).sizes ?? {}).filter(([id, size]) => placed.has(id) && isSize(size)),
  );
  return { pages: clean, sizes };
}

export const sizeOf = (layout: Layout, id: WidgetId) => layout.sizes?.[id] ?? registry.find((w) => w.id === id)!.size;

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

export type Area = { col: number; row: number; cols: number; rows: number };

// Packs widgets onto the 3 by 3 page in order: each takes the first free cell,
// shrinks to the space left there, and then widgets grow into any gaps so the
// page is always filled, the last widget first since it borders the gaps. A
// widget with no free cell left gets no area.
export function arrange(requested: Size[]): (Area | undefined)[] {
  const taken = Array.from({ length: 3 }, () => [false, false, false]);
  const free = ({ col, row, cols, rows }: Area) => {
    for (let r = row; r < row + rows; r++)
      for (let c = col; c < col + cols; c++) if (r > 2 || c > 2 || r < 0 || c < 0 || taken[r][c]) return false;
    return true;
  };
  const mark = ({ col, row, cols, rows }: Area) => {
    for (let r = row; r < row + rows; r++) for (let c = col; c < col + cols; c++) taken[r][c] = true;
  };

  const areas = requested.map((size) => {
    const [wantCols, wantRows] = size.split("x").map(Number);
    for (let i = 0; i < 9; i++) {
      const row = Math.floor(i / 3);
      const col = i % 3;
      if (taken[row][col]) continue;
      let best: Area | undefined;
      for (let cols = wantCols; cols > 0; cols--)
        for (let rows = wantRows; rows > 0; rows--) {
          const area = { col, row, cols, rows };
          if (free(area) && cols * rows > (best ? best.cols * best.rows : 0)) best = area;
        }
      mark(best!);
      return best;
    }
  });

  const grows = (a: Area): Area[] => [
    { ...a, cols: a.cols + 1 },
    { ...a, rows: a.rows + 1 },
    { ...a, col: a.col - 1, cols: a.cols + 1 },
    { ...a, row: a.row - 1, rows: a.rows + 1 },
  ];
  const strip = (a: Area, b: Area): Area => ({
    col: b.col < a.col ? b.col : b.cols > a.cols ? a.col + a.cols : a.col,
    row: b.row < a.row ? b.row : b.rows > a.rows ? a.row + a.rows : a.row,
    cols: b.cols > a.cols ? 1 : a.cols,
    rows: b.rows > a.rows ? 1 : a.rows,
  });
  for (let grew = true; grew; ) {
    grew = false;
    for (let i = areas.length - 1; i >= 0; i--) {
      const area = areas[i];
      if (!area) continue;
      const next = grows(area).find((b) => free(strip(area, b)));
      if (!next) continue;
      mark(strip(area, next));
      areas[i] = next;
      grew = true;
    }
  }
  return areas;
}
