// src/client/render/spotlightMirror.ts
//
// Paints spotlight.nvim's highlights into the rendered document: the tokens
// marked in Neovim (a customer id, `400 (Bad Request)`, an error code in a log
// analysis) are marked in the preview too, in the same colors, live.
//
// The state arrives over the relay's /spotlight channel (see
// lua/mdview/core/spotlight_mirror.lua for the payload). This module owns
// everything after that: parsing it defensively, searching the DOM, painting.
//
// ## Search semantics -- the same as Neovim's
//
// A spotlight text is matched LITERALLY (never as a regex) and CASE-SENSITIVELY
// unless the item says otherwise. A "literal" spotlight matches any substring --
// no word boundaries -- exactly like a visual-selection spotlight in Neovim; a
// "word" spotlight matches only between word boundaries, like `\<text\>`.
// Matching is non-overlapping, left to right.
//
// ## What is searched
//
// The rendered text, per *block*: a paragraph, a list item, a table cell, a
// `<pre>`. Text nodes are joined within a block so a token split by inline
// markup -- `<code>` inside a sentence, the `<span>`s a code highlighter puts
// around every token -- is still found, and nothing matches across two blocks
// (Neovim's matches never cross a line either). `<script>`, `<style>` and form
// text are never searched.
//
// ## How it is painted
//
// The CSS Custom Highlight API where the browser has it (`CSS.highlights`): the
// DOM stays exactly as the renderer produced it, which matters because the
// cursor caret and the selection mirror resolve positions against it. Elsewhere
// the matches are wrapped in `<mark class="spotlight spotlight-N">`, and every
// apply starts by unwrapping the previous ones -- so a re-render, which replaces
// the whole DOM anyway, never has stale marks to reason about.
//
// Overlaps are resolved the same way in both: a match wins over a "line"
// highlight, and between two of the same kind the higher slot wins.
//
// ## Cost
//
// Bounded by `max` matches per spotlight (a token that occurs 50 000 times in a
// log would otherwise mean 50 000 ranges per render) and by a cap on the number
// of spotlights and the length of one text.

/** The palette has this many slots; spotlight.nvim hands them out as 1..8. */
export const SLOT_COUNT = 8;
/** Matches painted per spotlight when the sender names no (usable) limit. */
export const DEFAULT_MAX_MATCHES = 500;
/** Upper bound on a sender-supplied limit. */
export const MAX_MATCHES_CEILING = 100_000;
/** Spotlights taken from one message, and the longest text taken from each. */
export const MAX_ITEMS = 256;
export const MAX_TEXT_LENGTH = 2000;

export interface SpotlightItem {
  text: string;
  /** Palette slot, 1..SLOT_COUNT. */
  slot: number;
  /** Highlight the whole line / block the match sits in, not just the match. */
  line: boolean;
  /** "word": only between word boundaries (`\<..\>`); "literal": any substring. */
  kind: 'word' | 'literal';
  ignoreCase: boolean;
}

export interface SpotlightColor {
  slot: number;
  /** "#rrggbb" or "#rrggbbaa" -- anything else is dropped before it can reach CSS. */
  fg?: string;
  bg?: string;
  bold: boolean;
}

export interface SpotlightState {
  items: SpotlightItem[];
  colors: SpotlightColor[];
  /** Matches painted per spotlight. */
  max: number;
}

export interface ApplyStats {
  /** Spotlights that were searched for. */
  items: number;
  /** Matches found (each painted once, line highlights not counted). */
  matches: number;
  /** Spotlights that hit `max` and were cut off there. */
  capped: number;
}

const HEX_COLOR = /^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;

// ---------------------------------------------------------------------------
// Parsing

/** The empty state: no spotlights, nothing painted. */
export function emptyState(): SpotlightState {
  return { items: [], colors: [], max: DEFAULT_MAX_MATCHES };
}

function toSlot(value: unknown): number | null {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 1 || n > SLOT_COUNT) return null;
  return n;
}

/**
 * Validate a `/spotlight` payload. Anything malformed yields the empty state or
 * is dropped item by item: a bad payload must paint nothing, never a wrong thing.
 */
export function parseSpotlightState(value: unknown): SpotlightState {
  const out = emptyState();
  if (!value || typeof value !== 'object') return out;
  const v = value as Record<string, unknown>;

  const max = Number(v.max);
  if (Number.isFinite(max) && max >= 1) {
    out.max = Math.min(Math.floor(max), MAX_MATCHES_CEILING);
  }

  if (Array.isArray(v.items)) {
    for (const raw of v.items) {
      if (out.items.length >= MAX_ITEMS) break;
      if (!raw || typeof raw !== 'object') continue;
      const r = raw as Record<string, unknown>;
      const slot = toSlot(r.slot);
      if (typeof r.text !== 'string' || r.text === '' || r.text.length > MAX_TEXT_LENGTH) continue;
      if (slot === null) continue;
      out.items.push({
        text: r.text,
        slot,
        line: r.line === true,
        kind: r.kind === 'word' ? 'word' : 'literal',
        ignoreCase: r.ignoreCase === true,
      });
    }
  }

  if (Array.isArray(v.colors)) {
    for (const raw of v.colors) {
      if (!raw || typeof raw !== 'object') continue;
      const r = raw as Record<string, unknown>;
      const slot = toSlot(r.slot);
      if (slot === null) continue;
      out.colors.push({
        slot,
        fg: typeof r.fg === 'string' && HEX_COLOR.test(r.fg) ? r.fg : undefined,
        bg: typeof r.bg === 'string' && HEX_COLOR.test(r.bg) ? r.bg : undefined,
        bold: r.bold === true,
      });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Searching

/** Half-open range of UTF-16 offsets into the searched string. */
export interface Match {
  start: number;
  end: number;
}

/** Neovim's idea of a word character, widened to Unicode letters and digits. */
const WORD_CHAR = /[\p{L}\p{N}_]/u;

function isWordChar(ch: string | undefined): boolean {
  return ch !== undefined && ch !== '' && WORD_CHAR.test(ch);
}

/** The code point ending right before `index`, as a string ('' at the start). */
function charBefore(text: string, index: number): string {
  if (index <= 0) return '';
  const low = text.charCodeAt(index - 1);
  if (low >= 0xdc00 && low <= 0xdfff && index >= 2) {
    const high = text.charCodeAt(index - 2);
    if (high >= 0xd800 && high <= 0xdbff) return text.slice(index - 2, index);
  }
  return text.charAt(index - 1);
}

/** The code point starting at `index`, as a string ('' at the end). */
function charAt(text: string, index: number): string {
  if (index >= text.length) return '';
  const cp = text.codePointAt(index);
  return cp === undefined ? '' : String.fromCodePoint(cp);
}

/** `\<` and `\>` around [start, end): a word boundary on each side. */
function onWordBoundaries(text: string, start: number, end: number): boolean {
  // `\<` needs a word character here and none right before; `\>` the mirror image.
  if (!isWordChar(charAt(text, start))) return false;
  if (isWordChar(charBefore(text, start))) return false;
  if (!isWordChar(charBefore(text, end))) return false;
  if (isWordChar(charAt(text, end))) return false;
  return true;
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Every match of `item` in `text`, left to right and non-overlapping, at most
 * `limit` of them. `capped` is true when one more existed beyond the limit
 * (so `limit` 0 is a pure "is there any?" probe).
 */
export function findMatches(
  text: string,
  item: Pick<SpotlightItem, 'text' | 'kind' | 'ignoreCase'>,
  limit: number,
): { matches: Match[]; capped: boolean } {
  const matches: Match[] = [];
  const needle = item.text;
  if (needle === '' || text.length < needle.length) {
    return { matches, capped: false };
  }
  const word = item.kind === 'word';

  // Case-sensitive is the default and the common case: a plain indexOf, which
  // also keeps every offset in the original string (lower-casing can change a
  // string's length). Case-insensitive goes through a regex for the same reason.
  let next: (from: number) => Match | null;
  if (item.ignoreCase) {
    const re = new RegExp(escapeRegExp(needle), 'giu');
    next = from => {
      re.lastIndex = from;
      const m = re.exec(text);
      return m ? { start: m.index, end: m.index + m[0].length } : null;
    };
  } else {
    next = from => {
      const i = text.indexOf(needle, from);
      return i < 0 ? null : { start: i, end: i + needle.length };
    };
  }

  let from = 0;
  while (from <= text.length - 1) {
    const m = next(from);
    if (!m) break;
    if (word && !onWordBoundaries(text, m.start, m.end)) {
      from = m.start + 1; // a failed candidate may overlap the next real one
      continue;
    }
    if (matches.length >= limit) return { matches, capped: true };
    matches.push(m);
    from = m.end;
  }
  return { matches, capped: false };
}

// ---------------------------------------------------------------------------
// The text the document is searched in

interface TextRun {
  node: Text;
  /** Offset of this node's first character within its group's text. */
  start: number;
  end: number;
}

/** The text of one block, with where each piece of it lives in the DOM. */
export interface TextGroup {
  text: string;
  runs: TextRun[];
  /** Inside a `<pre>`: lines are separated by "\n" in `text`. */
  pre: boolean;
}

const BLOCK_TAGS = new Set([
  'ADDRESS',
  'ARTICLE',
  'ASIDE',
  'BLOCKQUOTE',
  'CAPTION',
  'DD',
  'DETAILS',
  'DIV',
  'DL',
  'DT',
  'FIELDSET',
  'FIGCAPTION',
  'FIGURE',
  'FOOTER',
  'FORM',
  'H1',
  'H2',
  'H3',
  'H4',
  'H5',
  'H6',
  'HEADER',
  'HR',
  'LI',
  'MAIN',
  'NAV',
  'OL',
  'P',
  'PRE',
  'SECTION',
  'SUMMARY',
  'TABLE',
  'TBODY',
  'TD',
  'TFOOT',
  'TH',
  'THEAD',
  'TR',
  'UL',
]);

/** Elements whose text is not document content. */
const SKIP_TAGS = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEXTAREA', 'TEMPLATE', 'SVG']);

/** Layers other features draw into the container; they carry no document text. */
const SKIP_CLASSES = ['mdview-selection-layer'];

const MARK_ATTR = 'data-mdview-spotlight';

function skipElement(el: Element, tag: string): boolean {
  if (SKIP_TAGS.has(tag)) return true;
  return SKIP_CLASSES.some(c => el.classList.contains(c));
}

/**
 * The document's text, one group per block. Whitespace-only groups (the
 * newlines between two `<li>`s) are left out: nothing meaningful matches in them.
 */
export function collectTextGroups(root: Element): TextGroup[] {
  const groups: TextGroup[] = [];
  const cur: { parts: string[]; runs: TextRun[]; len: number; pre: boolean } = {
    parts: [],
    runs: [],
    len: 0,
    pre: false,
  };

  const flush = (): void => {
    if (cur.len > 0) {
      const text = cur.parts.join('');
      if (/\S/.test(text)) groups.push({ text, runs: cur.runs, pre: cur.pre });
    }
    cur.parts = [];
    cur.runs = [];
    cur.len = 0;
  };

  const walk = (parent: Node, pre: boolean): void => {
    for (let child = parent.firstChild; child; child = child.nextSibling) {
      if (child.nodeType === 3) {
        const node = child as Text;
        const data = node.data;
        if (data === '') continue;
        if (cur.len === 0) cur.pre = pre;
        cur.runs.push({ node, start: cur.len, end: cur.len + data.length });
        cur.parts.push(data);
        cur.len += data.length;
      } else if (child.nodeType === 1) {
        const el = child as Element;
        const tag = el.tagName.toUpperCase();
        if (skipElement(el, tag)) continue;
        if (tag === 'BR') {
          flush();
        } else if (BLOCK_TAGS.has(tag)) {
          flush();
          walk(el, pre || tag === 'PRE');
          flush();
        } else {
          walk(el, pre);
        }
      }
    }
  };

  walk(root, false);
  flush();
  return groups;
}

// ---------------------------------------------------------------------------
// Painting

/** One stretch of one group's text to paint. */
interface Paint {
  start: number;
  end: number;
  slot: number;
  line: boolean;
}

/** A line highlight never outranks a match; between equals the higher slot wins. */
function rank(p: { slot: number; line: boolean }): number {
  return (p.line ? 0 : 100) + p.slot;
}

/** The whole line (in a `<pre>`) or block that a match at [start, end) sits in, trimmed. */
function lineBounds(group: TextGroup, start: number, end: number): { start: number; end: number } {
  const { text } = group;
  let from = 0;
  let to = text.length;
  if (group.pre) {
    from = start > 0 ? text.lastIndexOf('\n', start - 1) + 1 : 0;
    const nl = text.indexOf('\n', end);
    to = nl < 0 ? text.length : nl;
  }
  while (from < to && /\s/.test(text.charAt(from))) from++;
  while (to > from && /\s/.test(text.charAt(to - 1))) to--;
  return { start: from, end: to };
}

/** Find every spotlight's matches and turn them into paints, per group. */
function computePaints(
  groups: TextGroup[],
  state: SpotlightState,
): { paints: Paint[][]; stats: ApplyStats } {
  const paints: Paint[][] = groups.map(() => []);
  const stats: ApplyStats = { items: state.items.length, matches: 0, capped: 0 };

  for (const item of state.items) {
    let remaining = state.max;
    const seenLines = new Set<string>();
    let capped = false;

    for (let g = 0; g < groups.length && !capped; g++) {
      const group = groups[g];
      if (group.text.length < item.text.length) continue;
      // Past the limit this only probes whether anything more exists.
      const found = findMatches(group.text, item, remaining);
      remaining -= found.matches.length;
      stats.matches += found.matches.length;
      if (found.capped) capped = true;

      for (const m of found.matches) {
        paints[g].push({ start: m.start, end: m.end, slot: item.slot, line: false });
        if (item.line) {
          const b = lineBounds(group, m.start, m.end);
          const key = `${g}:${b.start}:${b.end}`;
          if (b.end > b.start && !seenLines.has(key)) {
            seenLines.add(key);
            paints[g].push({ start: b.start, end: b.end, slot: item.slot, line: true });
          }
        }
      }
    }
    if (capped) stats.capped += 1;
  }
  return { paints, stats };
}

/** Non-overlapping stretches, each painted by exactly one winner. */
function resolveSegments(paints: Paint[]): Paint[] {
  if (paints.length === 0) return [];
  const sorted = [...paints].sort((a, b) => a.start - b.start || a.end - b.end);
  const points = new Set<number>();
  for (const p of sorted) {
    points.add(p.start);
    points.add(p.end);
  }
  const bounds = [...points].sort((a, b) => a - b);

  const out: Paint[] = [];
  let active: Paint[] = [];
  let idx = 0;
  for (let i = 0; i + 1 < bounds.length; i++) {
    const a = bounds[i];
    const b = bounds[i + 1];
    while (idx < sorted.length && sorted[idx].start <= a) active.push(sorted[idx++]);
    active = active.filter(p => p.end > a);
    if (active.length === 0) continue;
    let best = active[0];
    for (const p of active) if (rank(p) > rank(best)) best = p;
    const prev = out[out.length - 1];
    if (prev && prev.end === a && prev.slot === best.slot && prev.line === best.line) {
      prev.end = b;
    } else {
      out.push({ start: a, end: b, slot: best.slot, line: best.line });
    }
  }
  return out;
}

/** The run holding offset `at` (a start) or the last character before it (an end). */
function runAt(runs: TextRun[], at: number): TextRun | null {
  let lo = 0;
  let hi = runs.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const r = runs[mid];
    if (at < r.start) hi = mid - 1;
    else if (at >= r.end) lo = mid + 1;
    else return r;
  }
  return null;
}

/** A DOM Range over [start, end) of a group's text; null if it can't be built. */
function rangeFor(doc: Document, group: TextGroup, start: number, end: number): Range | null {
  const first = runAt(group.runs, start);
  const last = runAt(group.runs, end - 1);
  if (!first || !last) return null;
  try {
    const range = doc.createRange();
    range.setStart(first.node, start - first.start);
    range.setEnd(last.node, end - last.start);
    return range;
  } catch {
    return null;
  }
}

// -- CSS Custom Highlight API ------------------------------------------------

interface HighlightLike {
  priority: number;
  add(range: Range): unknown;
}
interface HighlightRegistryLike {
  set(name: string, highlight: HighlightLike): unknown;
  delete(name: string): unknown;
}
interface HighlightApi {
  registry: HighlightRegistryLike;
  create: () => HighlightLike;
}

function highlightRegistry(): HighlightRegistryLike | null {
  const registry = (globalThis as unknown as { CSS?: { highlights?: HighlightRegistryLike } }).CSS
    ?.highlights;
  return registry && typeof registry.set === 'function' ? registry : null;
}

/** The CSS Custom Highlight API, or null where the browser does not have it. */
function highlightApi(): HighlightApi | null {
  const registry = highlightRegistry();
  const Ctor = (globalThis as unknown as { Highlight?: new () => HighlightLike }).Highlight;
  if (!registry || typeof Ctor !== 'function') return null;
  return { registry, create: () => new Ctor() };
}

function highlightName(slot: number, line: boolean): string {
  return line ? `spotlight-line-${slot}` : `spotlight-${slot}`;
}

function clearHighlights(): void {
  const registry = highlightRegistry();
  if (!registry) return;
  for (let slot = 1; slot <= SLOT_COUNT; slot++) {
    registry.delete(highlightName(slot, false));
    registry.delete(highlightName(slot, true));
  }
}

function paintWithHighlightApi(
  api: HighlightApi,
  doc: Document,
  groups: TextGroup[],
  paints: Paint[][],
): void {
  const byName = new Map<string, { slot: number; line: boolean; highlight: HighlightLike }>();
  for (let g = 0; g < groups.length; g++) {
    for (const p of paints[g]) {
      const range = rangeFor(doc, groups[g], p.start, p.end);
      if (!range) continue;
      const name = highlightName(p.slot, p.line);
      let entry = byName.get(name);
      if (!entry) {
        const highlight = api.create();
        highlight.priority = rank(p);
        entry = { slot: p.slot, line: p.line, highlight };
        byName.set(name, entry);
      }
      entry.highlight.add(range);
    }
  }
  for (const [name, entry] of byName) api.registry.set(name, entry.highlight);
}

// -- <mark> fallback ----------------------------------------------------------

function paintWithMarks(doc: Document, groups: TextGroup[], paints: Paint[][]): void {
  for (let g = 0; g < groups.length; g++) {
    const segments = resolveSegments(paints[g]);
    const runs = groups[g].runs;
    // Back to front: splitting a text node leaves its first part in place, so
    // offsets earlier in the same node stay valid for the segments still to do.
    for (let s = segments.length - 1; s >= 0; s--) {
      const seg = segments[s];
      for (let r = runs.length - 1; r >= 0; r--) {
        const run = runs[r];
        if (run.end <= seg.start || run.start >= seg.end) continue;
        const from = Math.max(seg.start, run.start) - run.start;
        const to = Math.min(seg.end, run.end) - run.start;
        const node = run.node;
        if (!node.parentNode) continue;
        if (to < node.data.length) node.splitText(to);
        const middle = from > 0 ? node.splitText(from) : node;
        const mark = doc.createElement('mark');
        mark.className = `spotlight spotlight-${seg.slot}${seg.line ? ' spotlight-line' : ''}`;
        mark.setAttribute(MARK_ATTR, '');
        middle.parentNode?.insertBefore(mark, middle);
        mark.appendChild(middle);
      }
    }
  }
}

function unwrapMarks(root: Element): void {
  const marks = root.querySelectorAll(`mark[${MARK_ATTR}]`);
  if (marks.length === 0) return;
  const parents = new Set<Node>();
  marks.forEach(mark => {
    const parent = mark.parentNode;
    if (!parent) return;
    while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
    parent.removeChild(mark);
    parents.add(parent);
  });
  // Put the text nodes the wrapping split back together.
  parents.forEach(p => p.normalize());
}

// ---------------------------------------------------------------------------
// Public API

export type PaintMode = 'auto' | 'highlight' | 'marks';

/** Remove everything painted by a previous apply: highlights and wrapping marks. */
export function clearSpotlights(root: Element): void {
  clearHighlights();
  unwrapMarks(root);
}

/**
 * Paint `state` into `root`, replacing what an earlier call painted. Safe to
 * call after every render -- it starts from a clean slate each time.
 *
 * `mode` is for tests; "auto" uses the CSS Custom Highlight API when the browser
 * has it and `<mark>` wrapping when not.
 */
export function applySpotlights(
  root: HTMLElement,
  state: SpotlightState,
  mode: PaintMode = 'auto',
): ApplyStats {
  clearSpotlights(root);
  if (state.items.length === 0) return { items: 0, matches: 0, capped: 0 };

  const doc = root.ownerDocument;
  const groups = collectTextGroups(root);
  const { paints, stats } = computePaints(groups, state);

  const api = mode === 'marks' ? null : highlightApi();
  if (api) {
    paintWithHighlightApi(api, doc, groups, paints);
  } else if (mode !== 'highlight') {
    paintWithMarks(doc, groups, paints);
  }
  return stats;
}

/**
 * Publish the palette as CSS custom properties on `target`:
 * `--spotlight-N-bg`, `--spotlight-N-fg`, `--spotlight-N-weight`. The stylesheet
 * reads them with built-in fallbacks, so a slot Neovim sent no color for keeps a
 * usable default instead of disappearing. Re-sent on every colorscheme change.
 */
export function setSpotlightColors(
  colors: SpotlightColor[],
  target: HTMLElement = document.documentElement,
): void {
  for (let slot = 1; slot <= SLOT_COUNT; slot++) {
    target.style.removeProperty(`--spotlight-${slot}-bg`);
    target.style.removeProperty(`--spotlight-${slot}-fg`);
    target.style.removeProperty(`--spotlight-${slot}-weight`);
  }
  for (const c of colors) {
    if (c.bg) target.style.setProperty(`--spotlight-${c.slot}-bg`, c.bg);
    if (c.fg) target.style.setProperty(`--spotlight-${c.slot}-fg`, c.fg);
    if (c.bold) target.style.setProperty(`--spotlight-${c.slot}-weight`, '700');
  }
}

export interface SpotlightMirror {
  /** A `/spotlight` message body (JSON): store it, set the colors, paint. */
  update(json: string): void;
  /** Paint the stored state again -- after a render replaced the DOM. */
  reapply(): void;
  /** Forget the state and remove every highlight. */
  clear(): void;
  /** The state currently held. */
  state(): SpotlightState;
}

/**
 * The mirror for one preview container: holds the latest state Neovim sent and
 * paints it. `log` receives one line per change worth knowing about (what was
 * painted, what hit the match limit) -- it reaches `:MDView weblogs`.
 */
export function createSpotlightMirror(
  root: HTMLElement,
  opts: { log?: (msg: string) => void; mode?: PaintMode } = {},
): SpotlightMirror {
  let current = emptyState();
  let lastLogged = '';

  const paint = (announce: boolean): void => {
    let stats: ApplyStats;
    try {
      stats = applySpotlights(root, current, opts.mode ?? 'auto');
    } catch (err) {
      // Painting is decoration: it must never take the preview down with it.
      console.error('[mdview] spotlight paint failed', err);
      return;
    }
    if (!announce || !opts.log) return;
    const line =
      `spotlight: ${stats.items} spotlight(s), ${stats.matches} match(es)` +
      (stats.capped > 0 ? `, ${stats.capped} capped at ${current.max}` : '');
    if (line !== lastLogged) {
      lastLogged = line;
      opts.log(line);
    }
  };

  return {
    update(json: string): void {
      let parsed: unknown = null;
      try {
        parsed = JSON.parse(json);
      } catch {
        parsed = null; // malformed: paint nothing rather than something stale
      }
      current = parseSpotlightState(parsed);
      setSpotlightColors(current.colors);
      paint(true);
    },
    reapply(): void {
      if (current.items.length === 0) return;
      paint(false);
    },
    clear(): void {
      current = emptyState();
      setSpotlightColors([]);
      clearSpotlights(root);
    },
    state(): SpotlightState {
      return current;
    },
  };
}
