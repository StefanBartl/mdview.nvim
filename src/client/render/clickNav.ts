// src/client/render/clickNav.ts
//
// Click-to-navigate (opt-in experimental.click_navigate). When a user clicks a
// relative link in the preview, we don't let the browser follow it (there's no
// web server behind these paths) — instead we hand the href to Neovim via the
// relay's /nav bridge, and Neovim opens the target document, which flows back
// into the preview through the normal push path.

/**
 * Decide whether a clicked link's href should be sent to Neovim, and with what
 * value. Returns the cleaned relative path to navigate to, or null when the
 * link should be left to the browser (external URLs, in-page anchors, absolute
 * or protocol-relative paths). Fragments/queries are stripped since Neovim
 * navigates to a file, not a URL.
 */
export function navTargetFromHref(href: string | null | undefined): string | null {
  if (!href) return null;
  const h = href.trim();
  if (h === '') return null;
  if (h.startsWith('#')) return null; // in-page anchor
  if (h.startsWith('//')) return null; // protocol-relative (external)
  if (h.startsWith('/')) return null; // root-absolute — not a doc-relative link
  if (/^[a-z][a-z0-9+.-]*:/i.test(h)) return null; // has a scheme (http:, mailto:, …)

  const clean = h.replace(/[?#].*$/, ''); // drop query/fragment
  return clean === '' ? null : clean;
}

/**
 * Install a delegated click handler on `root` that intercepts relative-link
 * clicks and calls `send(target)` with the resolved href, preventing the
 * browser's own navigation. Non-navigable links are left untouched.
 */
export function installClickNav(root: HTMLElement, send: (target: string) => void): void {
  root.addEventListener('click', (ev: MouseEvent) => {
    // Respect modifier-clicks (open in new tab, etc.) — leave those alone.
    if (ev.defaultPrevented || ev.button !== 0 || ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) {
      return;
    }
    const el = ev.target as Element | null;
    const anchor = el?.closest?.('a') as HTMLAnchorElement | null;
    if (!anchor) return;
    const target = navTargetFromHref(anchor.getAttribute('href'));
    if (target === null) return;
    ev.preventDefault();
    send(target);
  });
}
