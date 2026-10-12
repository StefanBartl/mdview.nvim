// src/client/render/editState.ts
//
// Whether block editing is on for this tab, kept across a reload. The URL of a
// tab says `edit=0|1` as it was when the tab opened; `:MDView edit on|off`
// afterwards switches it with a control message, which a reload would forget.
// The choice is stored in sessionStorage (per tab), tagged with the session
// token so a tab that is reused for a new session does not obey an old choice.
// Storage can be missing or throw (private windows, blocked site data): then
// the URL decides, as before.

const KEY_PREFIX = 'mdview-edit:';

export interface EditStateStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

function defaultStorage(): EditStateStorage | null {
  try {
    return window.sessionStorage;
  } catch {
    return null;
  }
}

/** The stored choice for this session, or null when there is none (or another session's). */
export function readEditState(
  token: string,
  key: string,
  storage: EditStateStorage | null = defaultStorage(),
): boolean | null {
  try {
    const raw = storage?.getItem(KEY_PREFIX + key) ?? null;
    if (raw === null) return null;
    const sep = raw.lastIndexOf(':');
    if (sep < 0 || raw.slice(0, sep) !== token) return null;
    const flag = raw.slice(sep + 1);
    return flag === '1' ? true : flag === '0' ? false : null;
  } catch {
    return null;
  }
}

/** Remember the choice for this session. Never throws. */
export function writeEditState(
  token: string,
  key: string,
  on: boolean,
  storage: EditStateStorage | null = defaultStorage(),
): void {
  try {
    storage?.setItem(KEY_PREFIX + key, `${token}:${on ? '1' : '0'}`);
  } catch {
    /* a reload then falls back to the URL */
  }
}
