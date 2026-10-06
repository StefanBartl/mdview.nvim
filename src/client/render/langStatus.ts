// src/client/render/langStatus.ts
//
// The small badge that says the preview shows a transformed text: the display
// language (`browser.display_lang`) is a translation of the buffer, so the
// reader must be able to tell it from the original, and must see when the
// translation is still running or failed. Neovim sends the state as a live
// control message `{ displayLang: {...} | false }` (the existing control
// channel; the relay passes it through untouched). `false` removes the badge.

export type LangState = 'idle' | 'translating' | 'done' | 'failed' | 'unavailable';

export interface LangStatus {
  state: LangState;
  lang?: string;
  engine?: string;
  done?: number;
  total?: number;
  message?: string;
}

const BADGE_ID = 'mdview-lang-status';
const STATES: readonly string[] = ['idle', 'translating', 'done', 'failed', 'unavailable'];

/** Read a control payload; anything that is not a status object means "no badge". */
export function parseLangStatus(value: unknown): LangStatus | null {
  if (!value || typeof value !== 'object') return null;
  const v = value as Record<string, unknown>;
  if (typeof v.state !== 'string' || !STATES.includes(v.state)) return null;
  const str = (x: unknown): string | undefined => (typeof x === 'string' && x ? x : undefined);
  const num = (x: unknown): number | undefined =>
    typeof x === 'number' && Number.isFinite(x) ? x : undefined;
  return {
    state: v.state as LangState,
    lang: str(v.lang),
    engine: str(v.engine),
    done: num(v.done),
    total: num(v.total),
    message: str(v.message),
  };
}

/** The text of the badge. */
export function langStatusLabel(s: LangStatus): string {
  const to = s.lang ? s.lang : '?';
  const via = s.engine ? ` via ${s.engine}` : '';
  switch (s.state) {
    case 'translating': {
      const progress = s.total ? ` ${s.done ?? 0}/${s.total}` : '';
      return `Translating to ${to}${via} …${progress}`;
    }
    case 'done':
      return `Translated to ${to}${via}${s.message ? ` (${s.message})` : ''}`;
    case 'failed':
      return `Original, translation failed${s.message ? `: ${s.message}` : ''}`;
    case 'unavailable':
      return `Original, no translation${s.message ? `: ${s.message}` : ''}`;
    default:
      return `Translation to ${to} ${s.message ?? 'pending'}`;
  }
}

/** Show, update or (with null) remove the badge. */
export function applyLangStatus(doc: Document, status: LangStatus | null): void {
  let el = doc.getElementById(BADGE_ID);
  if (!status) {
    el?.remove();
    return;
  }
  if (!el) {
    el = doc.createElement('div');
    el.id = BADGE_ID;
    el.setAttribute('role', 'status');
    el.style.cssText =
      'position:fixed;top:8px;right:8px;z-index:2147483000;padding:2px 8px;border-radius:10px;' +
      'font:12px/1.6 system-ui,sans-serif;background:rgba(30,30,30,.82);color:#fff;' +
      'pointer-events:none;max-width:60vw;overflow:hidden;text-overflow:ellipsis;white-space:nowrap';
    doc.body.appendChild(el);
  }
  el.dataset.state = status.state;
  el.textContent = langStatusLabel(status);
  el.style.background =
    status.state === 'failed' || status.state === 'unavailable'
      ? 'rgba(160,50,40,.9)'
      : 'rgba(30,30,30,.82)';
}
