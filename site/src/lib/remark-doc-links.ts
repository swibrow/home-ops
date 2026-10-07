import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { docHref, docIdFromPath } from "./slug.ts";

const docsDir = fileURLToPath(new URL("../../../docs/", import.meta.url));
const externalUrl = /^(?:[a-z][a-z0-9+.-]*:|\/\/|#|\/)/i;

interface Node {
  type: string;
  url?: string;
  children?: Node[];
}

function walk(node: Node, fn: (n: Node) => void) {
  fn(node);
  node.children?.forEach((c) => walk(c, fn));
}

// Rewrites links between docs/*.md files (as written for GitHub) into site URLs.
export function remarkDocLinks({ base }: { base: string }) {
  return (tree: Node, file: { path?: string }) => {
    if (!file.path) return;
    const fromDir = dirname(file.path.startsWith("file:") ? fileURLToPath(file.path) : file.path);
    walk(tree, (node) => {
      if (node.type !== "link" && node.type !== "definition") return;
      const url = node.url;
      if (!url || externalUrl.test(url)) return;
      const [path, hash] = url.split("#", 2);
      if (!path.endsWith(".md")) return;
      const target = relative(docsDir, resolve(fromDir, decodeURI(path)));
      if (target.startsWith("..")) {
        throw new Error(`${file.path}: link ${url} points outside docs/`);
      }
      node.url = docHref(base, docIdFromPath(target)) + (hash ? `#${hash}` : "");
    });
  };
}
