// Shared by the content loader and the link rewriter so page ids and rewritten hrefs agree.
export function docIdFromPath(relPath: string): string {
  const withoutExt = relPath.replace(/\\/g, "/").replace(/\.md$/, "");
  if (withoutExt === "index") return "index";
  return withoutExt.replace(/\/index$/, "");
}

export function docHref(base: string, id: string): string {
  return id === "index" ? `${base}/` : `${base}/${id}/`;
}
