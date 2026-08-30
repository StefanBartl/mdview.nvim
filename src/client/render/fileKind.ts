// src/client/render/fileKind.ts
//
// Distinguishes a Markdown document (rendered through the WASM comrak+ammonia
// renderer) from any other text file (rendered as a syntax-highlighted
// read-only code view — see render/plainText.ts). Driven purely by the `key`
// URL param (the document path) already sent for every session, so no extra
// query param is needed: any_file (Lua side) is what decides
// whether a non-Markdown path ever reaches the client at all.

const MARKDOWN_EXTENSIONS = new Set(['md', 'markdown', 'mdx']);

/** Extension (lowercase, no dot), or '' if `path` has none. */
function extOf(path: string): string {
  const base = path.split(/[/\\]/).pop() ?? path;
  const dot = base.lastIndexOf('.');
  if (dot <= 0) return ''; // no extension, or a dotfile like ".gitignore"
  return base.slice(dot + 1).toLowerCase();
}

/** Whether `path` should be rendered as Markdown. */
export function isMarkdownPath(path: string): boolean {
  return MARKDOWN_EXTENSIONS.has(extOf(path));
}
