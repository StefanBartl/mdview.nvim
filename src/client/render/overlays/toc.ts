// src/client/render/overlays/toc.ts
//
// Floating mini-outline: a small panel listing the document's headings, with the
// section the Neovim cursor is in highlighted and a "3 / 12" progress readout, so
// a viewer can see the structure and how far along you are without you narrating
// it. Data comes entirely from the rendered DOM (headings + data-sourcepos) — no
// extra Neovim-side plumbing. Clicking an entry scrolls the preview there.

import type { HeadingInfo } from '../docModel';
import type { Overlay, OverlayCtx } from './types';

let panel: HTMLElement | null = null;
let listEl: HTMLElement | null = null;
let progressEl: HTMLElement | null = null;
let barEl: HTMLElement | null = null;
let items: { heading: HeadingInfo; el: HTMLElement }[] = [];
let octx: OverlayCtx | null = null;
let lastLine = -1;

function build(ctx: OverlayCtx): void {
  panel = document.createElement('div');
  panel.className = 'mdview-toc';

  const head = document.createElement('div');
  head.className = 'mdview-toc-head';
  progressEl = document.createElement('span');
  progressEl.className = 'mdview-toc-progress';
  head.append(progressEl);

  listEl = document.createElement('div');
  listEl.className = 'mdview-toc-list';

  const track = document.createElement('div');
  track.className = 'mdview-toc-track';
  barEl = document.createElement('div');
  barEl.className = 'mdview-toc-bar';
  track.append(barEl);

  panel.append(head, listEl, track);
  ctx.layer.append(panel);
}

function renderList(): void {
  if (!listEl || !octx) return;
  listEl.textContent = '';
  items = [];
  const hs = octx.headings();
  for (const h of hs) {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'mdview-toc-item';
    // Indent by heading depth; clamp so deep nesting stays readable.
    row.style.paddingLeft = `${0.25 + Math.min(h.level - 1, 3) * 0.6}rem`;
    row.textContent = h.text || '(untitled)';
    row.title = h.text;
    row.addEventListener('click', () => octx?.scrollTo(h.el));
    listEl.append(row);
    items.push({ heading: h, el: row });
  }
  if (hs.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'mdview-toc-empty';
    empty.textContent = 'no headings';
    listEl.append(empty);
  }
  highlight(lastLine);
}

function highlight(line: number): void {
  if (!octx) return;
  const current = line >= 0 ? octx.governingHeading(line) : null;
  let activeIdx = -1;
  for (const { heading, el } of items) {
    const on = current !== null && heading.index === current.index;
    el.classList.toggle('mdview-toc-item-active', on);
    if (on) activeIdx = heading.index;
  }
  const total = items.length;
  if (progressEl) {
    progressEl.textContent =
      total === 0 ? 'outline' : `outline · ${activeIdx >= 0 ? activeIdx + 1 : '–'} / ${total}`;
  }
  if (barEl) {
    const frac = total > 0 && activeIdx >= 0 ? (activeIdx + 1) / total : 0;
    barEl.style.width = `${Math.round(frac * 100)}%`;
  }
  // Keep the highlighted entry visible in a long outline.
  if (activeIdx >= 0) {
    items[activeIdx]?.el.scrollIntoView({ block: 'nearest' });
  }
}

export const tocOverlay: Overlay = {
  name: 'toc',

  mount(ctx: OverlayCtx): void {
    octx = ctx;
    build(ctx);
    renderList();
  },

  unmount(): void {
    panel?.remove();
    panel = null;
    listEl = null;
    progressEl = null;
    barEl = null;
    items = [];
    octx = null;
    lastLine = -1;
  },

  onCursor(line: number): void {
    lastLine = line;
    highlight(line);
  },

  onRender(): void {
    // Headings may have changed with the new content — rebuild the list.
    renderList();
  },
};
