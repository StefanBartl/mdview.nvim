// src/client/render/scrollFollow.ts
//
// The browser side of "the preview follows Neovim's cursor" (the \x05 ping):
// reading the ping, and keeping a ping that could not be applied because the
// block it points at was hidden by an open block editor, so that it can be
// applied when the editor closes.

/** Time after an applied ping in which the resulting scroll event is not sent back. */
export const SCROLL_SUPPRESS_MS = 250;

export interface CursorFields {
  line: number;
  /** 0-based byte column, or -1 when the ping carries none. */
  col: number;
}

/**
 * The cursor position of a scroll ping ("line/total/viewfrac[/col]", prefix
 * already removed), or null when its line is not a number.
 */
export function parseCursorFields(payload: string): CursorFields | null {
  const fields = payload.split('/');
  const line = Number(fields[0]);
  if (!Number.isFinite(line)) return null;
  const col = Number(fields[3]);
  return { line, col: Number.isFinite(col) ? col : -1 };
}

export interface ScrollFollowOptions {
  /** Scrolls the preview to the ping (the whole message, with its prefix). */
  apply: (message: string) => void;
  /** The clock; injectable for tests. */
  now?: () => number;
}

export interface ScrollFollower {
  /**
   * A ping arrived. While an editor is open its block has no position, so the
   * newest ping is kept for `catchUp` instead of applied.
   */
  receive: (message: string, editing: boolean) => void;
  /** Apply the kept ping, if any (the editor closed). Returns whether one was. */
  catchUp: () => boolean;
  /** True while a scroll event is the echo of an applied ping. */
  suppressed: () => boolean;
}

export function createScrollFollower(options: ScrollFollowOptions): ScrollFollower {
  const now = options.now ?? Date.now;
  let skipped: string | null = null;
  let suppressUntil = 0;
  return {
    receive(message, editing) {
      if (editing) skipped = message;
      else options.apply(message);
      // Even a kept ping moves the remembered cursor; the scroll event of an
      // applied one must not bounce back to Neovim.
      suppressUntil = now() + SCROLL_SUPPRESS_MS;
    },
    catchUp() {
      if (skipped === null) return false;
      const message = skipped;
      skipped = null;
      options.apply(message);
      suppressUntil = now() + SCROLL_SUPPRESS_MS;
      return true;
    },
    suppressed: () => now() < suppressUntil,
  };
}
