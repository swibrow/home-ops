import type { ShikiTransformer } from "shiki";
import type { Element } from "hast";

// Wraps each block in a figure with a header bar: the `title="..."` fence meta used in the docs
// (GitHub ignores it) or the language, plus a copy button wired up by a delegated click handler.
export const shikiCodeTitle: ShikiTransformer = {
  name: "code-title",
  root(root) {
    const pre = root.children[0] as Element;
    const title = /title="([^"]+)"/.exec(this.options.meta?.__raw ?? "")?.[1];
    const lang = this.options.lang === "plaintext" || this.options.lang === "text" ? "" : this.options.lang;
    const header: Element = {
      type: "element",
      tagName: "div",
      properties: { className: ["code-header"], "data-pagefind-ignore": "" },
      children: [
        {
          type: "element",
          tagName: "span",
          properties: { className: [title ? "code-title" : "code-lang"] },
          children: [{ type: "text", value: title ?? lang }],
        },
        {
          type: "element",
          tagName: "button",
          properties: { type: "button", className: ["code-copy"], "aria-label": "Copy code" },
          children: [{ type: "text", value: "Copy" }],
        },
      ],
    };
    root.children = [
      {
        type: "element",
        tagName: "figure",
        properties: { className: ["code-block"] },
        children: [header, pre],
      },
    ];
  },
};
