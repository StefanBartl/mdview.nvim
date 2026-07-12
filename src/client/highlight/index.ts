// src/client/highlight/index.ts
//
// Code-fence highlighting dispatcher. The highlighter is chosen per session via
// the ?hl= URL param (set from browser.highlighter on the Lua side) and its
// implementation is dynamically imported, so an unselected highlighter is never
// pulled into the loaded bundle — zero cost when off or when the other one is
// chosen.

export type HighlighterName = 'hljs' | 'shiki' | 'none';

/** Map the ?hl= param to a highlighter; defaults to highlight.js. */
export function parseHighlighter(param: string | null | undefined): HighlighterName {
  if (param === 'shiki') return 'shiki';
  if (param === 'none') return 'none';
  return 'hljs';
}

type Applier = (root: HTMLElement) => void | Promise<void>;

let cached: Applier | null = null;
let loadPromise: Promise<Applier | null> | null = null;

async function loadApplier(name: HighlighterName): Promise<Applier | null> {
  if (name === 'none') return null;
  if (cached) return cached;
  if (!loadPromise) {
    loadPromise = (async () => {
      if (name === 'shiki') {
        const m = await import('./shiki');
        return m.highlightAll;
      }
      const m = await import('./hljs');
      return m.highlightAll;
    })();
  }
  cached = await loadPromise;
  return cached;
}

/**
 * Highlight all code blocks under `root` with the chosen highlighter. Safe to
 * call after every render; the implementation module is loaded once and reused.
 * Never throws — a highlighter failure must not blank the preview.
 */
export async function highlight(name: HighlighterName, root: HTMLElement): Promise<void> {
  if (name === 'none') return;
  try {
    const apply = await loadApplier(name);
    if (apply) await apply(root);
  } catch (err) {
    console.error('[mdview] highlighter failed', err);
  }
}
