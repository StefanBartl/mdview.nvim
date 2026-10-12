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

/**
 * The path that decides how a text is rendered: the document Neovim announced
 * for this tab, else the room's path. They differ under `browser.behavior =
 * "reuse"`, where the room keeps the first document's path for the whole
 * session while the tab follows the active buffer.
 */
export function shownPath(doc: string | null, key: string): string {
  return doc || key;
}

/**
 * After a doc ping: must the text on screen be rendered again? The content of a
 * buffer switch arrives BEFORE the ping that names its document, so it was
 * rendered as the previous document's kind. `renderedAsMarkdown` is null before
 * anything was rendered. A code view is always redone: its language comes from
 * the path.
 */
export function needsRerenderAfterDocChange(
  renderedAsMarkdown: boolean | null,
  doc: string,
): boolean {
  if (renderedAsMarkdown === null) return false;
  const markdown = isMarkdownPath(doc);
  return !markdown || markdown !== renderedAsMarkdown;
}
