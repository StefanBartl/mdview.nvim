// src/client/render/localImages.ts
//
// Rewrite relative <img src="..."> targets to the /asset route so they
// actually load. The WASM renderer already produces correct <img> markup
// for `![alt](path)` (see native/wasm-render's own tests) — the gap is
// resolution, not rendering: a bare relative src resolves against the
// PAGE's own URL in the browser, not the previewed document's directory on
// disk, and the relay's plain http.FileServer is rooted at the client
// bundle, not the document. See native/server/main.go's handleAsset for the
// server side (token-authed, clamped to the document's directory,
// image-extension allowlist).
//
// A src already handled by isExternalHref (a scheme, data:, protocol-
// relative, root-absolute) is left untouched — those either load directly
// (http(s)/data:) or point somewhere this rewrite has no business touching.
// Runs after each render on the trusted, already-sanitized DOM, same
// lifecycle as markExternalLinks.

import { isExternalHref } from './externalLinks';

/** True for an <img> src that should be rewritten to the /asset route. */
export function isLocalImageSrc(src: string | null | undefined): boolean {
  if (!src) return false;
  const s = src.trim();
  if (s === '') return false;
  return !isExternalHref(s);
}

/**
 * Rewrite every relative <img src> under `root` to `/asset?key=…&path=…
 * &token=…`. No-op without both key and token — matches clientLog's own
 * "missing token -> do nothing" tolerance elsewhere in this client.
 */
export function resolveLocalImages(root: HTMLElement, key: string | null, token: string | null): void {
  if (!key || !token) return;
  root.querySelectorAll<HTMLImageElement>('img[src]').forEach(img => {
    const src = img.getAttribute('src');
    if (!isLocalImageSrc(src)) return;
    img.setAttribute(
      'src',
      `/asset?key=${encodeURIComponent(key)}&path=${encodeURIComponent(src as string)}&token=${encodeURIComponent(token)}`
    );
  });
}
