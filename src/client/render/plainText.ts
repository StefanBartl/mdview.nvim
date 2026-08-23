// src/client/render/plainText.ts
//
// Renders a non-Markdown document as a single syntax-highlighted, read-only
// code block — the plain-text counterpart to the WASM Markdown renderer (see
// fileKind.ts / main.ts). Reuses the exact `<pre><code class="language-xxx">`
// shape comrak already emits for fenced code blocks, so it's themed for free
// by themes/_base.css and highlighted for free by the existing hljs/shiki
// dispatcher (highlight/index.ts) — no new CSS, no new highlighter code.
//
// Built via DOM APIs (createElement + textContent), never string-concatenated
// innerHTML: `text` is untrusted file content (it could contain a literal
// "<script>"), and textContent always treats it as inert text, so this path
// needs no HTML sanitizer.

import { languageForPath } from '../highlight/languageForPath';

/** Replace `container`'s content with `text` as one highlighted code block. */
export function renderPlainText(container: HTMLElement, text: string, path: string): void {
  container.replaceChildren();

  const pre = document.createElement('pre');
  const code = document.createElement('code');
  code.className = `language-${languageForPath(path)}`;
  code.textContent = text;
  pre.appendChild(code);
  container.appendChild(pre);
}
