// src/client/render/scrollSync.ts
//
// Maps a Neovim cursor line to the rendered block element using comrak's
// data-sourcepos="startLine:col-endLine:col" hints (enabled in the WASM
// renderer). This is exact regardless of how tall each block renders, unlike a
// proportional line/total estimate. The actual scrolling (which needs layout
// geometry) stays in main.ts; the block *selection* lives here so it's unit
// testable in jsdom.

/**
 * Return the block whose source start-line is the closest one at or before
 * `line` — i.e. the block the cursor is in, or the nearest one above it. Returns
 * null when there are no data-sourcepos nodes or the cursor is before them all.
 */
export function pickSourceposTarget(container: HTMLElement, line: number): HTMLElement | null {
  const nodes = container.querySelectorAll<HTMLElement>('[data-sourcepos]');
  let best: HTMLElement | null = null;
  let bestLine = -1;
  nodes.forEach(el => {
    const sp = el.getAttribute('data-sourcepos');
    if (!sp) return;
    const startLine = Number(sp.split(':')[0]);
    if (!Number.isFinite(startLine)) return;
    if (startLine <= line && startLine > bestLine) {
      best = el;
      bestLine = startLine;
    }
  });
  return best;
}

/** Whether the container has any source-position hints to map against. */
export function hasSourcepos(container: HTMLElement): boolean {
  return container.querySelector('[data-sourcepos]') !== null;
}
