// ADD: Annotations
// Small rendering utility that converts Markdown -> HTML, computes a content hash,
// and exports helpers for caching and rendering. Uses markdown-it + markdown-it-anchor.

import MarkdownIt from "markdown-it";
import markdownItAnchor from "markdown-it-anchor";
import crypto from "crypto";

/**
 * Create a configured markdown-it instance.
 * Keep this instance persistent to avoid reallocation on each request.
 */
const md = new MarkdownIt({
  html: true,
  linkify: true,
  typographer: true,
});
md.use(markdownItAnchor, {
  permalink: markdownItAnchor.permalink.ariaHidden({}),
});

/**
 * Compute a stable SHA256 hex hash for the given string.
 * Used to detect unchanged content and avoid re-rendering/sending identical payloads.
 */
export function hashContent(input: string): string {
  return crypto.createHash("sha256").update(input, "utf8").digest("hex");
}

/**
 * Render markdown to HTML using markdown-it.
 * This function is synchronous and cheap for small->medium documents.
 *
 * @param markdown source markdown text
 * @returns HTML string
 */
export function renderMarkdown(markdown: string): string {
  return md.render(markdown);
}

/**
 * Simple in-memory cache structure to keep last hash -> html mapping per "document key".
 * Key is a string (for now we support using file path or a session id).
 */
const cache = new Map<string, { hash: string; html: string }>();

/**
 * Render with cache check: if content hash is unchanged, returns cached HTML and a flag.
 *
 * @param key string identifier for the markdown source (e.g. file path)
 * @param markdown markdown text
 * @returns { html: string, cached: boolean }
 */
export function renderWithCache(
  key: string,
  markdown: string
): { html: string; cached: boolean } {
  const h = hashContent(markdown);
  const entry = cache.get(key);
  if (entry && entry.hash === h) {
    return { html: entry.html, cached: true };
  }
  const html = renderMarkdown(markdown);
  cache.set(key, { hash: h, html });
  return { html, cached: false };
}

/**
 * Invalidate cache for a given key (useful when external events require fresh render).
 */
export function invalidateCache(key: string): void {
  cache.delete(key);
}
