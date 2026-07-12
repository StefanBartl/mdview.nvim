// src/client/highlight/shiki.ts
//
// Shiki implementation of code-fence highlighting: exact TextMate/VSCode themes
// (tokyo-night, catppuccin, github, …) with inline-styled output. Heavier than
// highlight.js, so it is only ever loaded when browser.highlighter = "shiki"
// (dynamic import in ./index.ts). Selected per session; the mdview ?theme=
// param is mapped to the closest Shiki theme.

import { codeToHtml, bundledLanguages, bundledThemes } from 'shiki';

// Map an mdview theme name (?theme=) to a bundled Shiki theme.
function shikiTheme(): string {
  const params = new URLSearchParams(window.location.search);
  const requested = (params.get('theme') || 'github').toLowerCase();
  const light = requested.endsWith('-light');
  const base = requested.replace(/-(light|dark)$/, '');
  const map: Record<string, string> = {
    github: light ? 'github-light' : 'github-dark',
    'dark-dimmed': 'github-dark-dimmed',
    plain: light ? 'github-light' : 'github-dark',
    tokyonight: 'tokyo-night',
    catppuccin: light ? 'catppuccin-latte' : 'catppuccin-mocha',
    'vscode-dark': 'dark-plus',
    'vscode-light': 'light-plus',
  };
  const theme = map[base] || (light ? 'github-light' : 'github-dark');
  return theme in bundledThemes ? theme : 'github-dark';
}

function langOf(code: HTMLElement): string {
  const m = code.className.match(/language-([\w-]+)/);
  const lang = m ? m[1].toLowerCase() : '';
  return lang && lang in bundledLanguages ? lang : 'text';
}

/**
 * Replace each fenced code block under `root` with Shiki's themed output.
 * Per-block try/catch so one unsupported language can't blank the preview.
 */
export async function highlightAll(root: HTMLElement): Promise<void> {
  const theme = shikiTheme();
  const blocks = Array.from(root.querySelectorAll<HTMLElement>('pre > code'));
  await Promise.all(
    blocks.map(async code => {
      const pre = code.parentElement;
      if (!pre || !pre.isConnected) return;
      try {
        const html = await codeToHtml(code.textContent || '', { lang: langOf(code), theme });
        // Shiki returns a full <pre class="shiki">…</pre>; swap it in for comrak's.
        if (pre.isConnected) pre.outerHTML = html;
      } catch {
        /* leave the original block as-is on any failure */
      }
    }),
  );
}
