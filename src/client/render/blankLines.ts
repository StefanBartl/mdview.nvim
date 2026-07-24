// src/client/render/blankLines.ts
//
// Optional "show all blank lines" mode (:MDView blanklines). CommonMark
// treats runs of blank lines as pure block separators — one blank line or
// five between two paragraphs renders identically (one paragraph gap). When
// this mode is on, each blank line beyond the first minimal separator gets an
// extra visible gap in the preview, so the source's actual whitespace shows
// through instead of being collapsed.
//
// Implemented as spacer elements inserted between top-level blocks (using the
// data-sourcepos line gap already emitted for scroll-sync/cursor mapping —
// see docModel.ts), rather than by rewriting each block's margin: a spacer
// only ADDS space and never touches the theme's own paragraph/heading margins.

import { topLevelBlocks } from './docModel';

const SPACER_CLASS = 'mdview-blank-spacer';

/** Parse the `?blanklines=` URL param (absent/anything else = off, "1" = on). */
export function parseBlankLines(param: string | null | undefined): boolean {
  return param === '1';
}

/** Remove any spacers from a previous call, e.g. before a re-render replaces innerHTML anyway. */
function clearSpacers(container: HTMLElement): void {
  container.querySelectorAll(`.${SPACER_CLASS}`).forEach(el => el.remove());
}

/**
 * Insert a spacer before each top-level block that started more than one
 * blank line after the previous block ended, sized to the extra blank lines.
 * No-op (after clearing any stale spacers) when `enabled` is false.
 */
export function applyBlankLineSpacing(container: HTMLElement, enabled: boolean): void {
  clearSpacers(container);
  if (!enabled) return;

  const blocks = topLevelBlocks(container);
  for (let i = 1; i < blocks.length; i++) {
    const prev = blocks[i - 1];
    const cur = blocks[i];
    // CommonMark requires at least one blank line between top-level blocks
    // (a few constructs allow zero, e.g. a heading directly after a
    // paragraph) — clamp so those cases add no spacer instead of a negative one.
    const blankLines = cur.startLine - prev.endLine - 1;
    const extra = Math.max(0, blankLines - 1);
    if (extra <= 0) continue;

    const spacer = document.createElement('div');
    spacer.className = SPACER_CLASS;
    spacer.style.height = `${extra}em`;
    cur.el.before(spacer);
  }
}
