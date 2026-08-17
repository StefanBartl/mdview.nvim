// src/client/render/linkHover.ts
//
// Hover a link in the preview and a small popup shows what it points at —
// the browser counterpart to markdown.nvim's in-editor hover, so both
// surfaces answer the same question the same way.
//
// What a target resolves to decides the popup:
//   image            -> the picture itself, via the /asset route (the same
//                       one localImages.ts already rewrites <img> src to)
//   markdown / text  -> its first lines, via /preview (server-side capped,
//                       extension-allowlisted, clamped to the document's
//                       directory — see native/server/main.go)
//   pdf              -> name only. Rendering a page needs pdfport, which
//                       lives in Neovim; reaching it from here means a
//                       poll-queue round trip (~250ms) plus rasterization,
//                       too slow for a hover. See docs/ROADMAP.
//   url              -> host / path / query, parsed locally. Never fetched:
//                       a hover that issued requests would disclose every
//                       link brushed past, exactly as in markdown.nvim.
//   anchor           -> the target heading's text, found in the rendered DOM
//
// Runs after each render on the trusted, already-sanitized DOM, same
// lifecycle as markExternalLinks and resolveLocalImages. All popup content
// is inserted as textContent, never innerHTML: /preview returns file
// contents, which are not trusted markup.

import { isExternalHref } from './externalLinks';
import { headings } from './docModel';

const IMAGE_EXT = /\.(png|jpe?g|gif|webp|bmp|svg|ico|avif)$/i;
const TEXT_EXT = /\.(md|markdown|mdx|txt)$/i;
const PDF_EXT = /\.pdf$/i;

export type HoverTargetKind = 'image' | 'text' | 'pdf' | 'url' | 'anchor' | 'other';

/** What kind of thing an href points at. Shape only — no I/O. */
export function classifyHref(href: string | null | undefined): HoverTargetKind {
  if (!href) return 'other';
  const h = href.trim();
  if (h === '') return 'other';
  if (h.startsWith('#')) return 'anchor';
  if (isExternalHref(h)) return 'url';

  const withoutFragment = h.split('#')[0];
  if (IMAGE_EXT.test(withoutFragment)) return 'image';
  if (TEXT_EXT.test(withoutFragment)) return 'text';
  if (PDF_EXT.test(withoutFragment)) return 'pdf';
  return 'other';
}

/**
 * GitHub-style heading slug: lowercase, strip anything that is not a word
 * character/space/hyphen, spaces to hyphens. Mirrors markdown.nvim's
 * `core.slug.gfm`, so an anchor that resolves in the editor resolves here
 * too.
 */
export function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s-]/gu, '')
    .trim()
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-');
}

/** Split a URL for display. Enough for a hover line, not a spec parser. */
export function describeUrl(href: string): string[] {
  try {
    const u = new URL(href, window.location.href);
    const out: string[] = [u.host || u.protocol];
    if (u.pathname && u.pathname !== '/') out.push(decodeURIComponent(u.pathname));
    if (u.search) out.push('? ' + decodeURIComponent(u.search.slice(1)));
    return out;
  } catch {
    return [href];
  }
}

interface PreviewResponse {
  name: string;
  lines: string[];
  truncated: boolean;
  size: number;
}

export interface LinkHoverOptions {
  key: string | null;
  token: string | null;
  /** Milliseconds the pointer must rest before the popup opens. */
  delayMs?: number;
  /** Cap on lines rendered in the popup (the server caps independently). */
  maxLines?: number;
}

const POPUP_ID = 'mdview-link-hover';

function removePopup(): void {
  document.getElementById(POPUP_ID)?.remove();
}

/**
 * Place the popup near the link without letting it leave the viewport.
 * Below the link by default; flipped above when there is not enough room.
 */
function positionPopup(popup: HTMLElement, anchor: HTMLElement): void {
  const rect = anchor.getBoundingClientRect();
  const margin = 8;

  popup.style.visibility = 'hidden';
  popup.style.left = '0px';
  popup.style.top = '0px';
  const pop = popup.getBoundingClientRect();

  let left = rect.left;
  if (left + pop.width + margin > window.innerWidth) {
    left = Math.max(margin, window.innerWidth - pop.width - margin);
  }

  let top = rect.bottom + margin;
  if (top + pop.height + margin > window.innerHeight) {
    const above = rect.top - pop.height - margin;
    // Only flip when above genuinely has more room; otherwise clamp below.
    top = above > margin ? above : Math.max(margin, window.innerHeight - pop.height - margin);
  }

  popup.style.left = `${left + window.scrollX}px`;
  popup.style.top = `${top + window.scrollY}px`;
  popup.style.visibility = 'visible';
}

function createPopup(title: string): HTMLElement {
  removePopup();
  const popup = document.createElement('div');
  popup.id = POPUP_ID;
  popup.className = 'mdview-link-hover';
  popup.setAttribute('role', 'tooltip');

  const head = document.createElement('div');
  head.className = 'mdview-link-hover__title';
  head.textContent = title;
  popup.appendChild(head);

  document.body.appendChild(popup);
  return popup;
}

function appendLines(popup: HTMLElement, lines: string[], maxLines: number): void {
  const body = document.createElement('pre');
  body.className = 'mdview-link-hover__body';
  // textContent, never innerHTML: these are file contents, not markup.
  body.textContent = lines.slice(0, maxLines).join('\n');
  popup.appendChild(body);
}

function appendNote(popup: HTMLElement, note: string): void {
  const el = document.createElement('div');
  el.className = 'mdview-link-hover__note';
  el.textContent = note;
  popup.appendChild(el);
}

function assetUrl(path: string, key: string, token: string): string {
  return `/asset?key=${encodeURIComponent(key)}&path=${encodeURIComponent(path)}&token=${encodeURIComponent(token)}`;
}

/**
 * Install link hovering on `root`. Returns a teardown function; calling
 * `installLinkHover` again after a re-render is safe as long as the previous
 * teardown ran (main.ts does exactly that).
 */
export function installLinkHover(root: HTMLElement, opts: LinkHoverOptions): () => void {
  const delayMs = opts.delayMs ?? 250;
  const maxLines = opts.maxLines ?? 20;

  let timer: number | undefined;
  // Bumped on every hover so a slow fetch landing after the pointer moved on
  // is discarded instead of opening a popup for a link already left.
  let generation = 0;

  function cancel(): void {
    if (timer !== undefined) {
      window.clearTimeout(timer);
      timer = undefined;
    }
    generation++;
    removePopup();
  }

  async function show(anchor: HTMLAnchorElement): Promise<void> {
    const href = anchor.getAttribute('href');
    const kind = classifyHref(href);
    if (!href || kind === 'other') return;

    const mine = generation;
    const name = href.split('#')[0].split('/').pop() || href;

    if (kind === 'url') {
      const popup = createPopup(new URL(href, window.location.href).protocol.replace(':', ''));
      appendLines(popup, describeUrl(href), maxLines);
      positionPopup(popup, anchor);
      return;
    }

    if (kind === 'anchor') {
      const wanted = slugify(decodeURIComponent(href.slice(1)));
      // Resolved against the document's heading outline (docModel.headings,
      // which keys off H1..H6 tags), NOT off element ids: the WASM renderer
      // emits no id attributes, so an id lookup would silently find nothing
      // for every anchor. Slug matching also mirrors how markdown.nvim's
      // in-editor hover resolves the same link.
      const target = headings(root).find(h => slugify(h.text) === wanted);
      const popup = createPopup('anchor');
      if (target) {
        const parts: string[] = [target.text];
        let sib = target.el.nextElementSibling;
        let count = 0;
        while (sib && count < 4 && !/^H[1-6]$/.test(sib.tagName)) {
          const text = sib.textContent?.trim();
          if (text) {
            parts.push(text);
            count++;
          }
          sib = sib.nextElementSibling;
        }
        appendLines(popup, parts, maxLines);
      } else {
        appendNote(popup, `no heading matches #${decodeURIComponent(href.slice(1))}`);
      }
      positionPopup(popup, anchor);
      return;
    }

    if (kind === 'pdf') {
      const popup = createPopup(name);
      appendNote(popup, 'PDF — click to open');
      positionPopup(popup, anchor);
      return;
    }

    if (!opts.key || !opts.token) return;

    if (kind === 'image') {
      const popup = createPopup(name);
      const img = document.createElement('img');
      img.className = 'mdview-link-hover__image';
      img.alt = name;
      img.src = assetUrl(href.split('#')[0], opts.key, opts.token);
      img.onload = () => {
        if (generation === mine) positionPopup(popup, anchor);
      };
      img.onerror = () => {
        if (generation !== mine) return;
        img.remove();
        appendNote(popup, 'image could not be loaded');
        positionPopup(popup, anchor);
      };
      popup.appendChild(img);
      positionPopup(popup, anchor);
      return;
    }

    // kind === 'text'
    const path = href.split('#')[0];
    const url = `/preview?key=${encodeURIComponent(opts.key)}&path=${encodeURIComponent(path)}&token=${encodeURIComponent(opts.token)}`;

    let response: Response;
    try {
      response = await fetch(url);
    } catch {
      if (generation !== mine) return;
      const popup = createPopup(name);
      appendNote(popup, 'preview unavailable');
      positionPopup(popup, anchor);
      return;
    }
    if (generation !== mine) return;

    if (!response.ok) {
      const popup = createPopup(name);
      // 404 is the interesting one: the link is broken, which is worth
      // saying plainly rather than silently showing nothing.
      appendNote(popup, response.status === 404 ? 'target not found' : 'preview unavailable');
      positionPopup(popup, anchor);
      return;
    }

    let data: PreviewResponse;
    try {
      data = (await response.json()) as PreviewResponse;
    } catch {
      return;
    }
    if (generation !== mine) return;

    const popup = createPopup(data.name || name);
    appendLines(popup, data.lines ?? [], maxLines);
    if (data.truncated) appendNote(popup, '…');
    positionPopup(popup, anchor);
  }

  function onOver(event: MouseEvent): void {
    const anchor = (event.target as HTMLElement | null)?.closest?.('a[href]') as
      | HTMLAnchorElement
      | null;
    if (!anchor || !root.contains(anchor)) return;
    cancel();
    const mine = generation;
    timer = window.setTimeout(() => {
      if (generation === mine) void show(anchor);
    }, delayMs);
  }

  function onOut(event: MouseEvent): void {
    const related = event.relatedTarget as HTMLElement | null;
    // Moving into the popup itself must not dismiss it (so it can be read
    // and scrolled); moving anywhere else does.
    if (related?.closest?.(`#${POPUP_ID}`)) return;
    cancel();
  }

  root.addEventListener('mouseover', onOver);
  root.addEventListener('mouseout', onOut);
  window.addEventListener('scroll', cancel, { passive: true });
  window.addEventListener('resize', cancel);
  document.addEventListener('keydown', cancel);

  return () => {
    cancel();
    root.removeEventListener('mouseover', onOver);
    root.removeEventListener('mouseout', onOut);
    window.removeEventListener('scroll', cancel);
    window.removeEventListener('resize', cancel);
    document.removeEventListener('keydown', cancel);
  };
}
