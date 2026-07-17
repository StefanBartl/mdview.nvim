// src/client/render/cursorMarker.ts
//
// Shows where the Neovim cursor is, in the preview. Stage A ("line"): a small
// caret in the left gutter at the cursor's line, positioned with the same
// sourcepos block + in-block interpolation as the scroll sync — so it's
// line-accurate even inside multi-line blocks. Column-accurate placement (a
// caret at the exact character) needs a source map and is a future stage; see
// docs/Roadmap/KONZEPT_links_und_cursor.md.

import { pickScrollTarget, fractionInBlock } from './scrollSync';

export type CursorMarkerMode = 'off' | 'line';

export function parseCursorMarkerMode(param: string | null | undefined): CursorMarkerMode {
  return param === 'line' ? 'line' : param === 'off' ? 'off' : 'line';
}

let barEl: HTMLElement | null = null;

function ensureBar(container: HTMLElement): HTMLElement {
  // Re-create if it was wiped (innerHTML replace on re-render detaches it) or if
  // it belongs to a different container.
  if (!barEl || barEl.parentElement !== container) {
    barEl = document.createElement('div');
    barEl.className = 'mdview-cursor-bar';
    barEl.setAttribute('aria-hidden', 'true');
    container.appendChild(barEl);
  }
  return barEl;
}

/**
 * Position the cursor marker at `line`. Positioned in the container's content
 * coordinates (top relative to the padding box), so it scrolls with the
 * content. Call after each render and on each cursor ping. Hidden in "off" mode
 * or when the line can't be located.
 */
export function updateCursorMarker(container: HTMLElement, line: number, mode: CursorMarkerMode): void {
  if (mode === 'off') {
    if (barEl) barEl.style.display = 'none';
    return;
  }
  const target = pickScrollTarget(container, line);
  if (!target) {
    if (barEl) barEl.style.display = 'none';
    return;
  }
  const rect = target.el.getBoundingClientRect();
  const contRect = container.getBoundingClientRect();
  const yInContent =
    rect.top - contRect.top + container.scrollTop + fractionInBlock(target, line) * rect.height;

  const bar = ensureBar(container);
  bar.style.display = 'block';
  bar.style.top = `${yInContent}px`;
}
