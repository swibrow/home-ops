const root = document.documentElement;
const darkQuery = matchMedia("(prefers-color-scheme: dark)");
const isDark = () => (root.dataset.theme ? root.dataset.theme === "dark" : darkQuery.matches);

function onThemeChange(fn: () => void) {
  document.addEventListener("themechange", fn);
  darkQuery.addEventListener("change", () => !root.dataset.theme && fn());
}

document.querySelector(".theme-toggle")?.addEventListener("click", () => {
  const next = isDark() ? "light" : "dark";
  root.dataset.theme = next;
  try {
    localStorage.setItem("theme", next);
  } catch {}
  document.dispatchEvent(new Event("themechange"));
});

let pagefindLoaded: Promise<void> | undefined;
function loadSearch(dialog: HTMLElement) {
  const base = dialog.dataset.pagefindBase!;
  pagefindLoaded ??= new Promise((resolve, reject) => {
    const css = Object.assign(document.createElement("link"), { rel: "stylesheet", href: `${base}pagefind-ui.css` });
    const js = Object.assign(document.createElement("script"), { src: `${base}pagefind-ui.js` });
    js.onload = () => {
      // @ts-expect-error PagefindUI is a global from pagefind-ui.js, generated after the Astro build.
      new PagefindUI({ element: "#search", showSubResults: true, showImages: false, autofocus: true });
      resolve();
    };
    js.onerror = () => {
      dialog.querySelector("#search")!.textContent = "Search is only available in the built site (run bun run build).";
      reject();
    };
    document.head.append(css, js);
  });
  return pagefindLoaded.then(() => dialog.querySelector<HTMLInputElement>(".pagefind-ui__search-input")?.focus()).catch(() => {});
}

function openDialog(id: string) {
  const dialog = document.getElementById(id) as HTMLDialogElement | null;
  if (!dialog || dialog.open) return;
  dialog.showModal();
  if (id === "search-dialog") loadSearch(dialog);
}

document.addEventListener("click", (event) => {
  const target = event.target as HTMLElement;
  const opener = target.closest<HTMLElement>("[data-open-dialog]");
  if (opener) return openDialog(opener.dataset.openDialog!);
  if (target.closest("[data-close-dialog]")) return target.closest("dialog")?.close();
  if (target instanceof HTMLDialogElement) return target.close();
  const copy = target.closest<HTMLButtonElement>(".code-copy");
  if (copy) {
    const code = copy.closest(".code-block")?.querySelector("pre code")?.textContent ?? "";
    navigator.clipboard.writeText(code).then(() => {
      copy.textContent = "Copied";
      setTimeout(() => (copy.textContent = "Copy"), 1500);
    });
  }
});

document.addEventListener("keydown", (event) => {
  const typing = (event.target as HTMLElement).closest("input, textarea, [contenteditable]");
  if ((event.key === "/" && !typing) || (event.key === "k" && (event.metaKey || event.ctrlKey))) {
    event.preventDefault();
    openDialog("search-dialog");
  }
});

for (const heading of document.querySelectorAll<HTMLElement>(".prose :is(h2, h3, h4)[id]")) {
  const link = Object.assign(document.createElement("a"), { href: `#${heading.id}`, className: "anchor", textContent: "#" });
  link.setAttribute("aria-label", `Link to ${heading.textContent}`);
  heading.append(link);
}

const tocLinks = new Map(
  [...document.querySelectorAll<HTMLAnchorElement>(".toc a")].map((a) => [decodeURIComponent(a.hash.slice(1)), a]),
);
if (tocLinks.size) {
  const headings = [...tocLinks.keys()].flatMap((id) => document.getElementById(id) ?? []);
  let queued = false;
  const update = () => {
    queued = false;
    const offset = parseFloat(getComputedStyle(root).scrollPaddingTop) + 8;
    const active = headings.findLast((h) => h.getBoundingClientRect().top <= offset) ?? headings[0];
    tocLinks.forEach((a, id) => a.toggleAttribute("aria-current", id === active.id));
  };
  addEventListener("scroll", () => !queued && (queued = true) && requestAnimationFrame(update), { passive: true });
  update();
}

const mermaidBlocks = [...document.querySelectorAll<HTMLElement>("pre > code.language-mermaid")];
if (mermaidBlocks.length) {
  const diagrams = mermaidBlocks.map((code) => {
    const figure = document.createElement("figure");
    figure.className = "mermaid-diagram";
    figure.dataset.source = code.textContent ?? "";
    code.parentElement!.replaceWith(figure);
    return figure;
  });

  import("mermaid").then(({ default: mermaid }) => {
    let run = 0;
    const draw = async () => {
      const current = ++run;
      const css = getComputedStyle(root);
      const v = (name: string) => css.getPropertyValue(name).trim();
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        theme: "base",
        fontFamily: v("--font-body"),
        themeVariables: {
          darkMode: isDark(),
          fontFamily: v("--font-body"),
          fontSize: "14px",
          background: v("--mermaid-bg"),
          primaryColor: v("--mermaid-node"),
          primaryBorderColor: v("--mermaid-border"),
          primaryTextColor: v("--mermaid-text"),
          secondaryColor: v("--mermaid-node-alt"),
          tertiaryColor: v("--mermaid-cluster"),
          clusterBkg: v("--mermaid-cluster"),
          clusterBorder: v("--mermaid-border"),
          lineColor: v("--mermaid-line"),
          textColor: v("--mermaid-text"),
          edgeLabelBackground: v("--mermaid-bg"),
        },
      });
      for (const [i, figure] of diagrams.entries()) {
        try {
          const { svg } = await mermaid.render(`mermaid-${i}-${current}`, figure.dataset.source!);
          if (current !== run) return;
          figure.innerHTML = svg;
        } catch (err) {
          figure.textContent = `Diagram failed to render: ${(err as Error).message}`;
        }
      }
    };
    draw();
    onThemeChange(draw);
  });
}
