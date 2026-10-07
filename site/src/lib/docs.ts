import { execFileSync } from "node:child_process";
import { getCollection, type CollectionEntry } from "astro:content";
import { pages } from "../nav.ts";

export type Doc = CollectionEntry<"docs">;

export async function loadDocs() {
  const docs = await getCollection("docs");
  const ids = new Set(docs.map((d) => d.id));
  const navIds = new Set(pages.map((p) => p.id));
  const missingFiles = [...navIds].filter((id) => !ids.has(id));
  const missingNav = [...ids].filter((id) => !navIds.has(id));
  if (missingFiles.length || missingNav.length) {
    throw new Error(
      `Nav and docs/ are out of sync. In nav without a file: ${missingFiles.join(", ") || "none"}. ` +
        `Files missing from nav: ${missingNav.join(", ") || "none"}.`,
    );
  }
  return docs;
}

export function docTitle(doc: Doc, fallback: string) {
  const headings = doc.rendered?.metadata?.headings as { depth: number; text: string }[] | undefined;
  return headings?.find((h) => h.depth === 1)?.text ?? fallback;
}

export function lastUpdated(filePath: string | undefined): Date | undefined {
  if (!filePath) return undefined;
  try {
    const out = execFileSync("git", ["log", "-1", "--format=%cI", "--", filePath], { encoding: "utf8" }).trim();
    return out ? new Date(out) : undefined;
  } catch {
    return undefined;
  }
}
