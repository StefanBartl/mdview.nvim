// src/client/render/overlays/manager.ts
//
// Registry + manager for preview overlays. Owns the shared overlay layer
// (#mdview-overlays), mounts/unmounts overlays on toggle, and fans the render /
// cursor / control hooks out to whatever is active. Toggles arrive live from
// Neovim over the control channel (:MDViewOverlay), or as the initial ?overlays=
// URL parameter when a tab opens.

import { headings, governingHeading, scrollToBlock } from '../docModel';
import { caretContentPos } from '../cursorMarker';
import type { Overlay, OverlayCtx } from './types';

const registry = new Map<string, Overlay>();
const active = new Map<string, Overlay>();

let layerEl: HTMLElement | null = null;
let ctx: OverlayCtx | null = null;

/** Register an overlay implementation so it can be toggled by name. */
export function registerOverlay(overlay: Overlay): void {
  registry.set(overlay.name, overlay);
}

/** Names of all registered overlays. */
export function overlayNames(): string[] {
  return [...registry.keys()];
}

/** Names of the currently mounted overlays. */
export function activeOverlayNames(): string[] {
  return [...active.keys()];
}

/**
 * Bind the manager to the preview container. Creates the shared overlay layer
 * and the context handed to each overlay. Safe to call once at boot.
 */
export function initOverlays(container: HTMLElement): void {
  if (!layerEl || !layerEl.isConnected) {
    layerEl = document.createElement('div');
    layerEl.id = 'mdview-overlays';
    layerEl.setAttribute('aria-hidden', 'true');
    document.body.appendChild(layerEl);
  }
  ctx = {
    root: container,
    layer: layerEl,
    headings: () => headings(container),
    governingHeading: (line: number) => governingHeading(container, line),
    caretPixel: (line: number, col: number) => caretContentPos(container, line, col),
    scrollTo: (el: HTMLElement) => scrollToBlock(container, el),
  };
}

/** Switch one overlay on or off. Unknown names and no-op toggles are ignored. */
export function setOverlay(name: string, on: boolean): void {
  const overlay = registry.get(name);
  if (!overlay || !ctx) return;
  const mounted = active.has(name);
  if (on === mounted) return;
  if (on) {
    try {
      overlay.mount(ctx);
      active.set(name, overlay);
    } catch {
      /* a broken overlay must never take the preview down */
    }
  } else {
    active.delete(name);
    try {
      overlay.unmount();
    } catch {
      /* ignore */
    }
  }
}

/** Apply a batch of toggles, e.g. {toc: true, keycast: false}. */
export function setOverlays(states: Record<string, boolean>): void {
  for (const [name, on] of Object.entries(states)) {
    if (typeof on === 'boolean') setOverlay(name, on);
  }
}

/** Cursor ping: the Neovim cursor moved to line/col. */
export function notifyCursor(line: number, col: number): void {
  for (const o of active.values()) {
    try {
      o.onCursor?.(line, col);
    } catch {
      /* ignore */
    }
  }
}

/** The document was re-rendered (innerHTML replaced). */
export function notifyRender(): void {
  for (const o of active.values()) {
    try {
      o.onRender?.();
    } catch {
      /* ignore */
    }
  }
}

/** Deliver an overlay-addressed control payload. */
export function dispatchOverlayControl(name: string, data: unknown): void {
  const o = active.get(name);
  try {
    o?.onControl?.(data);
  } catch {
    /* ignore */
  }
}

/** Test seam: drop all state (registry stays, overlays are unmounted). */
export function resetOverlays(): void {
  for (const name of [...active.keys()]) setOverlay(name, false);
  layerEl?.remove();
  layerEl = null;
  ctx = null;
}
