// src/client/render/overlays/types.ts
//
// The overlay contract. An overlay is an independent, toggleable UI layer drawn
// over the rendered document: it only draws, never edits the content, and
// several can be active at once. See docs/Roadmap/KONZEPT_overlays.md.

import type { HeadingInfo } from '../docModel';

export interface OverlayCtx {
  /** The content element (#mdview-root) — the rendered document. */
  root: HTMLElement;
  /** The shared overlay layer (#mdview-overlays); overlays append here. */
  layer: HTMLElement;
  /** The document's heading outline, derived from the DOM. */
  headings(): HeadingInfo[];
  /** The heading governing `line` (last heading at/before it), or null. */
  governingHeading(line: number): HeadingInfo | null;
  /** Cursor pixel position in the content's coordinate space, or null. */
  caretPixel(line: number, col: number): { x: number; y: number; h: number } | null;
  /** Scroll the content so `el` sits near the top. */
  scrollTo(el: HTMLElement): void;
}

export interface Overlay {
  name: string;
  /** Create DOM / attach listeners. Called when the overlay is switched on. */
  mount(ctx: OverlayCtx): void;
  /** Remove everything again. Called when switched off. */
  unmount(): void;
  /** Per cursor ping (nvim cursor moved). */
  onCursor?(line: number, col: number): void;
  /** After each re-render of the document (innerHTML was replaced). */
  onRender?(): void;
  /** Overlay-addressed control payload from Neovim. */
  onControl?(data: unknown): void;
}
