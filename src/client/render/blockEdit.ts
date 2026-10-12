// src/client/render/blockEdit.ts
//
// Block editing. Clicking a rendered block (heading, paragraph, list item,
// code block, table, quote) swaps it for a text field holding that block's
// *source lines*; committing the edit sends the lines back so the source is
// rewritten and the change flows back through the normal push path.
//
// Why raw source and not contenteditable: the rendered HTML has lost the
// Markdown (link targets, emphasis markers, table alignment), and turning edited
// HTML back into Markdown is lossy. The block's `data-sourcepos` already says
// which lines it came from, so the honest editing unit is those lines.
//
// The edit carries `expected` (the lines as rendered). The receiving side only
// applies it when the document still holds exactly those lines there, so an
// edit made against a stale render is refused instead of overwriting newer text.
//
// Commit happens on blur / Ctrl+Enter (Enter in a one-line field), not per
// keystroke: a write-back triggers a re-render that replaces the DOM, which the
// caller holds back while an editor is open (`isEditing`, `onClose`).

/** Tags that are one editable unit (the block as a whole, not its children). */
const EDITABLE_TAGS = new Set([
  'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'P', 'LI', 'PRE', 'TABLE', 'BLOCKQUOTE',
]);

/** Clicks inside these never open an editor (they have a job of their own). */
const INTERACTIVE = 'a, input, textarea, button, select, label, summary, .mdview-block-editor';

/**
 * Private blocks are blurred until revealed, and a click is the reveal gesture:
 * an editor opening on that click would show the raw text of what is hidden.
 */
const PRIVATE = '[data-private]';

export interface LineRange {
  /** 1-based first source line. */
  start: number;
  /** 1-based last source line, inclusive. */
  end: number;
}

export interface BlockEdit extends LineRange {
  /** The block's source lines as rendered, joined with "\n". */
  expected: string;
  /** The text that replaces them. */
  text: string;
}

/** The lines of a document, with CRLF read as one line break. */
export function splitLines(text: string): string[] {
  return text.replace(/\r\n/g, '\n').split('\n');
}

/** Parse comrak's "startLine:startCol-endLine:endCol". Null when malformed. */
export function parseSourcePos(sp: string | null | undefined): LineRange | null {
  if (!sp) return null;
  const m = /^(\d+):\d+-(\d+):\d+$/.exec(sp);
  if (!m) return null;
  const start = Number(m[1]);
  const end = Number(m[2]);
  if (!Number.isInteger(start) || !Number.isInteger(end) || start < 1 || end < start) return null;
  return { start, end };
}

/**
 * The source lines an element stands for. A list item that contains a nested
 * list covers the nested items' lines too; only its own lines (up to the line
 * before the first nested block) belong to it, the children are edited on their
 * own.
 */
export function rangeOf(el: Element): LineRange | null {
  const own = parseSourcePos(el.getAttribute('data-sourcepos'));
  if (!own) return null;
  if (el.tagName !== 'LI') return own;
  for (const child of Array.from(el.children)) {
    if (child.tagName !== 'UL' && child.tagName !== 'OL') continue;
    const nested = parseSourcePos(child.getAttribute('data-sourcepos'));
    if (nested && nested.start > own.start) {
      return { start: own.start, end: Math.min(own.end, nested.start - 1) };
    }
  }
  return own;
}

/**
 * The editable block a click landed in: the nearest ancestor (or the target
 * itself) that is one editable unit and carries a source position. Null for
 * clicks on links, controls, existing editors, private blocks or between blocks.
 */
export function blockAt(target: EventTarget | null, container: HTMLElement): HTMLElement | null {
  if (!(target instanceof Element)) return null;
  if (target.closest(INTERACTIVE) || target.closest(PRIVATE)) return null;
  let el: Element | null = target;
  while (el && el !== container) {
    if (EDITABLE_TAGS.has(el.tagName) && el.hasAttribute('data-sourcepos')) {
      return el as HTMLElement;
    }
    el = el.parentElement;
  }
  return null;
}

/**
 * Lines `start..end` (1-based, inclusive) joined with "\n". Null when the range
 * is not inside the text. `text` is the document, or its lines when the caller
 * has split it already (a large document is split once per click, not per call).
 */
export function sliceLines(text: string | string[], range: LineRange): string | null {
  const lines = typeof text === 'string' ? splitLines(text) : text;
  if (range.start < 1 || range.end > lines.length) return null;
  return lines.slice(range.start - 1, range.end).join('\n');
}

/**
 * Drop trailing blank lines from `range`. A block's source position can run
 * through the blank line that ends it (the last item of a list does); those
 * lines are separators, not part of what is edited, and replacing them would
 * make a missing trailing blank line eat the gap before the next block.
 */
export function trimBlankTail(text: string | string[], range: LineRange): LineRange {
  const lines = typeof text === 'string' ? splitLines(text) : text;
  let end = range.end;
  // Lines past the end of the text are left for `sliceLines` to refuse.
  while (end > range.start && end <= lines.length && lines[end - 1].trim() === '') end--;
  return { start: range.start, end };
}

export interface BlockEditOptions {
  /** The document text the DOM was rendered from. */
  getText: () => string;
  /** Editing switched on (`?edit=1`, `:MDView edit`). */
  isEnabled: () => boolean;
  /** Called once per committed, changed edit. */
  send: (edit: BlockEdit) => void;
  /** Called after an editor closed (commit or cancel), so a held-back render can run. */
  onClose?: () => void;
}

export interface BlockEditor {
  /** An editor is open: the caller must not replace the DOM under it. */
  isEditing: () => boolean;
  /** Close an open editor without sending anything. */
  cancel: () => void;
}

/**
 * Install the click handler once on `container` (which survives the innerHTML
 * swap). Returns a handle for the render loop.
 */
export function installBlockEdit(container: HTMLElement, opts: BlockEditOptions): BlockEditor {
  let active: { field: HTMLInputElement | HTMLTextAreaElement; block: HTMLElement } | null = null;

  const close = (): void => {
    if (!active) return;
    const { field, block } = active;
    active = null;
    field.remove();
    block.style.display = '';
    opts.onClose?.();
  };

  const commit = (range: LineRange, expected: string): void => {
    if (!active) return;
    const text = active.field.value.replace(/\r\n/g, '\n');
    const changed = text !== expected;
    close();
    if (changed) opts.send({ ...range, expected, text });
  };

  const open = (block: HTMLElement): void => {
    const lines = splitLines(opts.getText());
    const full = rangeOf(block);
    if (!full) return;
    const range = trimBlankTail(lines, full);
    const expected = sliceLines(lines, range);
    if (expected === null) return;

    const oneLine = !expected.includes('\n');
    const field = oneLine ? document.createElement('input') : document.createElement('textarea');
    field.className = 'mdview-block-editor';
    field.value = expected;
    field.spellcheck = false;
    field.setAttribute('aria-label', 'Edit the Markdown source of this block');
    if (field instanceof HTMLInputElement) {
      field.type = 'text';
    } else {
      field.rows = Math.min(expected.split('\n').length + 1, 30);
    }

    block.style.display = 'none';
    block.parentNode?.insertBefore(field, block);
    active = { field, block };
    field.focus();

    field.addEventListener('keydown', (ev: Event) => {
      const k = ev as KeyboardEvent;
      // Enter that confirms an IME composition is not a commit.
      if (k.isComposing) return;
      if (k.key === 'Escape') {
        k.preventDefault();
        close();
      } else if (k.key === 'Enter' && (oneLine || k.ctrlKey || k.metaKey)) {
        k.preventDefault();
        commit(range, expected);
      }
    });
    // Blur commits. `close` removes the field, which itself fires blur: the
    // `active` check keeps that from committing twice. A blur that leaves the
    // field still the active element is the *window* losing focus (alt-tab, a
    // click into the browser chrome): half-typed text is not committed then.
    field.addEventListener('blur', () => {
      if (!active || active.field !== field) return;
      if (document.activeElement === field) return;
      commit(range, expected);
    });
  };

  container.addEventListener('click', (ev: MouseEvent) => {
    if (!opts.isEnabled() || active) return;
    if (ev.button !== 0 || ev.ctrlKey || ev.metaKey || ev.shiftKey || ev.altKey) return;
    // A drag that selected text is a selection, not a request to edit.
    const sel = window.getSelection();
    if (sel && !sel.isCollapsed) return;
    const block = blockAt(ev.target, container);
    if (block) open(block);
  });

  return {
    isEditing: () => active !== null,
    cancel: close,
  };
}
