// src/server/render.ts
// Markdown rendering + caching utility for mdview.nvim server
// Features:
// - Markdown -> HTML via markdown-it + markdown-it-anchor
// - Persistent MarkdownIt instance to avoid repeated allocations
// - SHA256 hash for change detection (prevents redundant re-renders / broadcasts)
// - In-memory cache keyed by document identifier (file path, session id, etc.)
// - Cache invalidation for external changes

import MarkdownIt from 'markdown-it';
import markdownItAnchor from 'markdown-it-anchor';
import crypto from 'crypto';

const md = new MarkdownIt({ html: true, linkify: true, typographer: true });
md.use(markdownItAnchor, { permalink: markdownItAnchor.permalink.ariaHidden({}) });

export function hashContent(input: string): string {
  return crypto.createHash('sha256').update(input, 'utf8').digest('hex');
}

export function renderMarkdown(markdown: string): string {
  return md.render(markdown);
}

const cache = new Map<string, { hash: string; html: string }>();

export function renderWithCache(key: string, markdown: string): { html: string; cached: boolean } {
  const contentHash = hashContent(markdown);
  const cachedEntry = cache.get(key);

  if (cachedEntry && cachedEntry.hash === contentHash) {
    return { html: cachedEntry.html, cached: true };
  }

  const html = renderMarkdown(markdown);
  cache.set(key, { hash: contentHash, html });
  return { html, cached: false };
}

export function invalidateCache(key: string): void {
  cache.delete(key);
}

export function clearAllCache(): void {
  cache.clear();
}
