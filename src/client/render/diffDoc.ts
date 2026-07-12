// src/client/render/diffDoc.ts
//
// Client-side reassembly of the document from the opt-in line-diff transport
// (experimental.line_diff). The relay forwards two kinds of \x03-prefixed JSON
// envelopes without ever inspecting them:
//   - full: { t:"f", v, text }            — a whole-document snapshot
//   - diff: { t:"d", v, base, edits[] }   — incremental line edits from `base`
// DiffDoc keeps the current lines + version and applies diffs only when their
// `base` matches its version; a mismatch (e.g. a tab that joined mid-stream and
// only has an older full snapshot) is ignored until the next full snapshot
// resyncs it. This makes desync self-healing rather than corrupting, which is
// why the relay can stay a dumb byte-forwarder.

export const ENVELOPE_PREFIX = '\x03';

/** A contiguous line edit: replace `count` lines at 0-based `start` with `lines`. */
export interface Edit {
  start: number;
  count: number;
  lines: string[];
}

export interface FullEnvelope {
  t: 'f';
  v: number;
  text: string;
}

export interface DiffEnvelope {
  t: 'd';
  v: number;
  base: number;
  edits: Edit[];
}

export type Envelope = FullEnvelope | DiffEnvelope;

export function isEnvelope(message: string): boolean {
  return message.startsWith(ENVELOPE_PREFIX);
}

export class DiffDoc {
  private lines: string[] = [];
  private version = -1;
  private synced = false;

  /** Current full document text. */
  text(): string {
    return this.lines.join('\n');
  }

  /**
   * Apply a \x03-prefixed envelope. Returns the new full text when the document
   * changed, or null when the message was ignored (malformed, or a diff whose
   * base doesn't match the current version — waiting for the next full snapshot).
   */
  apply(message: string): string | null {
    if (!isEnvelope(message)) return null;
    let env: Envelope;
    try {
      env = JSON.parse(message.slice(ENVELOPE_PREFIX.length)) as Envelope;
    } catch {
      return null;
    }

    if (env.t === 'f') {
      this.lines = env.text.split('\n');
      this.version = env.v;
      this.synced = true;
      return this.text();
    }

    if (env.t === 'd') {
      if (!this.synced || env.base !== this.version) {
        return null; // desynced — ignore until a full snapshot arrives
      }
      // Apply edits from the highest start index down so earlier edits don't
      // shift the indices of later ones. Coerce `lines` to an array: a pure
      // deletion has no replacement lines, and some JSON encoders (Neovim's
      // vim.json.encode) serialize an empty Lua table as {} rather than [], so
      // guard against a non-array here instead of spreading a bare object.
      const edits = [...(env.edits ?? [])].sort((a, b) => b.start - a.start);
      for (const e of edits) {
        const add = Array.isArray(e.lines) ? e.lines : [];
        this.lines.splice(e.start, e.count, ...add);
      }
      this.version = env.v;
      return this.text();
    }

    return null;
  }
}
