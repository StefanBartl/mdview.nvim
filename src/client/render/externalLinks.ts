// src/client/render/externalLinks.ts
//
// Open "external" links in a new tab so a click doesn't navigate the preview
// tab away (which would drop the WebSocket and lose the preview). External =
// anything that isn't a relative document link handled by click-to-navigate and
// isn't an in-page anchor: URLs with a scheme (http:, mailto:, …),
// protocol-relative (//…), and root-absolute (/…) hrefs. Runs after each render
// on the trusted, already-sanitized DOM.

/** True for links that should open in a new tab rather than in place. */
export function isExternalHref(href: string | null | undefined): boolean {
  if (!href) return false;
  const h = href.trim();
  if (h === '' || h.startsWith('#')) return false; // in-page anchor stays in tab
  return h.startsWith('//') || h.startsWith('/') || /^[a-z][a-z0-9+.-]*:/i.test(h);
}

export type ExternalLinkMode = 'new_tab' | 'same_tab';

export function parseExternalLinkMode(param: string | null | undefined): ExternalLinkMode {
  return param === 'same_tab' ? 'same_tab' : 'new_tab';
}

/**
 * Give every external link a target/rel so it opens in a new tab (mode
 * "new_tab", the default). "same_tab" leaves them alone (old behavior). rel
 * keeps noopener/noreferrer to avoid window.opener leaks.
 */
export function markExternalLinks(root: HTMLElement, mode: ExternalLinkMode): void {
  if (mode !== 'new_tab') return;
  root.querySelectorAll<HTMLAnchorElement>('a[href]').forEach(a => {
    if (isExternalHref(a.getAttribute('href'))) {
      a.setAttribute('target', '_blank');
      a.setAttribute('rel', 'noopener noreferrer');
    }
  });
}
