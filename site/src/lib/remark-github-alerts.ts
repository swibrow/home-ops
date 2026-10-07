interface Node {
  type: string;
  value?: string;
  children?: Node[];
  data?: Record<string, unknown>;
}

const labels: Record<string, string> = {
  NOTE: "Note",
  TIP: "Tip",
  IMPORTANT: "Important",
  WARNING: "Warning",
  CAUTION: "Caution",
};
const marker = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*\n?/;

function walk(node: Node, fn: (n: Node) => void) {
  fn(node);
  node.children?.forEach((c) => walk(c, fn));
}

// Renders GitHub alert blockquotes (`> [!NOTE]`). A bold line right after the marker becomes the title.
export function remarkGithubAlerts() {
  return (tree: Node) => {
    walk(tree, (node) => {
      if (node.type !== "blockquote") return;
      const first = node.children?.[0];
      const text = first?.type === "paragraph" ? first.children?.[0] : undefined;
      const match = text?.type === "text" ? marker.exec(text.value ?? "") : null;
      if (!first || !text || !match) return;

      const kind = match[1];
      text.value = text.value!.slice(match[0].length);
      if (text.value === "") first.children!.shift();

      let title: Node[] = [{ type: "text", value: labels[kind] }];
      const rest = first.children!;
      if (rest[0]?.type === "strong") {
        const lead = rest.shift()!;
        const after = rest[0] as Node | undefined;
        if (after?.type === "text" && after.value?.startsWith("\n")) {
          after.value = after.value.slice(1);
          if (after.value === "") rest.shift();
        }
        const next = rest[0] as Node | undefined;
        if (!next || next.type === "break") title = lead.children ?? title;
        else rest.unshift(lead);
      }
      if (rest.length === 0) node.children!.shift();

      node.data = {
        hName: "aside",
        hProperties: { className: ["alert", `alert-${kind.toLowerCase()}`] },
      };
      node.children!.unshift({
        type: "paragraph",
        data: { hProperties: { className: ["alert-title"] } },
        children: title,
      });
    });
  };
}
