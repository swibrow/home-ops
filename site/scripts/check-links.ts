import { existsSync, readFileSync, statSync } from "node:fs";
import { Glob } from "bun";

const dist = new URL("../dist/", import.meta.url).pathname;
const base = "/home-ops";
const pages = new Map<string, string>();

for (const file of new Glob("**/*.html").scanSync(dist)) {
  pages.set(file, readFileSync(dist + file, "utf8"));
}

function resolveFile(path: string): string | undefined {
  const rel = decodeURIComponent(path.slice(base.length + 1));
  const candidates = rel === "" || rel.endsWith("/") ? [`${rel}index.html`] : [rel, `${rel}/index.html`];
  return candidates.find((c) => existsSync(dist + c) && statSync(dist + c).isFile());
}

const ids = (html: string) => new Set([...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]));
const errors: string[] = [];
let checked = 0;

for (const [file, html] of pages) {
  for (const [, attr, raw] of html.matchAll(/\s(href|src)="([^"]*)"/g)) {
    if (/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(raw)) continue;
    checked++;
    const url = raw.replaceAll("&amp;", "&");
    const [path, hash] = url.split("#", 2);
    if (path === "") {
      if (hash && !ids(html).has(decodeURIComponent(hash))) errors.push(`${file}: missing anchor ${url}`);
      continue;
    }
    if (!path.startsWith(`${base}/`)) {
      errors.push(`${file}: ${attr} without ${base} base: ${url}`);
      continue;
    }
    const target = resolveFile(path);
    if (!target) {
      errors.push(`${file}: broken ${attr} ${url}`);
      continue;
    }
    if (hash && target.endsWith(".html") && !ids(pages.get(target) ?? "").has(decodeURIComponent(hash))) {
      errors.push(`${file}: missing anchor ${url}`);
    }
  }
}

if (errors.length) {
  console.error(errors.join("\n"));
  console.error(`\n${errors.length} broken internal link(s) across ${pages.size} pages`);
  process.exit(1);
}
console.log(`Link check: ${checked} internal links across ${pages.size} pages, all resolve`);
