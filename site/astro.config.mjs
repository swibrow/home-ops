import { fileURLToPath } from "node:url";
import { defineConfig } from "astro/config";
import { unified } from "@astrojs/markdown-remark";
import { remarkDocLinks } from "./src/lib/remark-doc-links.ts";
import { remarkGithubAlerts } from "./src/lib/remark-github-alerts.ts";
import { shikiCodeTitle } from "./src/lib/shiki-code-title.ts";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const base = "/home-ops";

export default defineConfig({
  site: "https://swibrow.github.io",
  base,
  trailingSlash: "always",
  markdown: {
    processor: unified({
      smartypants: false,
      remarkPlugins: [[remarkDocLinks, { base }], remarkGithubAlerts],
    }),
    syntaxHighlight: { type: "shiki", excludeLangs: ["math", "mermaid"] },
    shikiConfig: {
      themes: { light: "github-light", dark: "github-dark-dimmed" },
      defaultColor: false,
      langAlias: { logsql: "text" },
      transformers: [shikiCodeTitle],
    },
  },
  vite: {
    server: { fs: { allow: [repoRoot] } },
    // mermaid is one large chunk, but it is only fetched on pages that have diagrams.
    build: { chunkSizeWarningLimit: 3000 },
  },
});
