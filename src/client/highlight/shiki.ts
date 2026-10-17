// src/client/highlight/shiki.ts
//
// Shiki implementation of code-fence highlighting: exact TextMate/VSCode themes
// (tokyo-night, catppuccin, github, …) with inline-styled output. Heavier than
// highlight.js, so only ever loaded when browser.highlighter = "shiki" (dynamic
// import in ./index.ts).
//
// Uses Shiki's JavaScript RegExp engine, NOT the default Oniguruma WASM engine:
// the Oniguruma .wasm isn't served by the relay's static file server, so the
// WASM engine silently fails in the browser (works in Node, hence "highlights
// nothing"). The JS engine needs no WASM and loads grammars as normal chunks.
// `forgiving` keeps it from throwing on grammars using Oniguruma-only regex.

import { createHighlighter, bundledLanguages, bundledThemes } from 'shiki';
import { createJavaScriptRegexEngine } from 'shiki/engine/javascript';
import { PARAGRAPH_CLASS } from '../render/cursorParagraph';

type Highlighter = Awaited<ReturnType<typeof createHighlighter>>;

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

let hlPromise: Promise<Highlighter> | null = null;

async function getHighlighter(theme: string): Promise<Highlighter> {
  if (!hlPromise) {
    hlPromise = createHighlighter({
      themes: [theme],
      langs: [],
      engine: createJavaScriptRegexEngine({ forgiving: true }),
    });
  }
  const hl = await hlPromise;
  if (!hl.getLoadedThemes().includes(theme)) {
    await hl.loadTheme(theme as never);
  }
  return hl;
}

/**
 * A block hidden by the block editor (display: none, its textarea sits next to
 * it). Replacing it would show the highlighted copy beside the open editor, and
 * the editor would close onto a detached node.
 */
function isHidden(pre: HTMLElement): boolean {
  return pre.style.display === 'none';
}

/**
 * Replace each fenced code block under `root` with Shiki's themed output.
 * Per-block try/catch so one unsupported language can't blank the preview.
 */
export async function highlightAll(root: HTMLElement): Promise<void> {
  const theme = shikiTheme();
  const hl = await getHighlighter(theme);
  const blocks = Array.from(root.querySelectorAll<HTMLElement>('pre > code'));
  for (const code of blocks) {
    const pre = code.parentElement;
    if (!pre || !pre.isConnected || isHidden(pre)) continue;
    const lang = langOf(code);
    try {
      if (lang !== 'text' && !hl.getLoadedLanguages().includes(lang)) {
        await hl.loadLanguage(lang as never);
      }
      const html = hl.codeToHtml(code.textContent || '', { lang, theme });
      if (pre.isConnected && !isHidden(pre)) {
        // Shiki returns a full <pre class="shiki">; the replacement must keep
        // the block's source position, which scroll sync, the cursor/selection
        // mirrors and block editing all find the block by. It also keeps the
        // cursor paragraph tint: the render placed it on the old <pre>
        // synchronously, and no cursor ping follows this async swap.
        const sourcePos = pre.getAttribute('data-sourcepos');
        const tinted = pre.classList.contains(PARAGRAPH_CLASS);
        pre.insertAdjacentHTML('afterend', html);
        const highlighted = pre.nextElementSibling;
        pre.remove();
        if (sourcePos && highlighted) highlighted.setAttribute('data-sourcepos', sourcePos);
        if (tinted && highlighted) highlighted.classList.add(PARAGRAPH_CLASS);
      }
    } catch {
      /* leave the original block as-is on any failure */
    }
  }
}
