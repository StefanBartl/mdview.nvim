// tests/client/diffDoc.test.ts
import { describe, it, expect } from 'vitest';
import { DiffDoc, ENVELOPE_PREFIX, isEnvelope } from '../../src/client/render/diffDoc';

const full = (v: number, text: string) => ENVELOPE_PREFIX + JSON.stringify({ t: 'f', v, text });
const diff = (v: number, base: number, edits: unknown[]) =>
  ENVELOPE_PREFIX + JSON.stringify({ t: 'd', v, base, edits });

describe('DiffDoc', () => {
  it('detects envelopes by prefix', () => {
    expect(isEnvelope(ENVELOPE_PREFIX + '{}')).toBe(true);
    expect(isEnvelope('# plain markdown')).toBe(false);
  });

  it('applies a full snapshot', () => {
    const d = new DiffDoc();
    expect(d.apply(full(0, '# Title\nbody'))).toBe('# Title\nbody');
    expect(d.text()).toBe('# Title\nbody');
  });

  it('applies a diff whose base matches the current version', () => {
    const d = new DiffDoc();
    d.apply(full(0, 'a\nb\nc'));
    // replace line index 1 ("b") with two lines
    const out = d.apply(diff(1, 0, [{ start: 1, count: 1, lines: ['B1', 'B2'] }]));
    expect(out).toBe('a\nB1\nB2\nc');
  });

  it('ignores a diff whose base does not match (desync)', () => {
    const d = new DiffDoc();
    d.apply(full(5, 'a\nb'));
    // base 2 != current version 5 -> ignored
    expect(d.apply(diff(6, 2, [{ start: 0, count: 1, lines: ['x'] }]))).toBeNull();
    expect(d.text()).toBe('a\nb'); // unchanged
  });

  it('recovers from desync on the next full snapshot', () => {
    const d = new DiffDoc();
    d.apply(full(5, 'a\nb'));
    d.apply(diff(6, 2, [{ start: 0, count: 1, lines: ['x'] }])); // ignored
    expect(d.apply(full(7, 'fresh\ndoc'))).toBe('fresh\ndoc');
    // and diffs chain from the new version again
    expect(d.apply(diff(8, 7, [{ start: 1, count: 1, lines: ['DOC'] }]))).toBe('fresh\nDOC');
  });

  it('ignores diffs before any full snapshot', () => {
    const d = new DiffDoc();
    expect(d.apply(diff(1, 0, [{ start: 0, count: 0, lines: ['x'] }]))).toBeNull();
  });

  it('applies multiple edits without index-shift corruption', () => {
    const d = new DiffDoc();
    d.apply(full(0, 'l0\nl1\nl2\nl3'));
    // two edits: insert at 1, and replace at 3 — applied high-to-low internally
    const out = d.apply(
      diff(1, 0, [
        { start: 1, count: 0, lines: ['INS'] },
        { start: 3, count: 1, lines: ['L3'] },
      ]),
    );
    expect(out).toBe('l0\nINS\nl1\nl2\nL3');
  });

  it('handles a pure deletion whose lines serialized as {} (vim.json.encode)', () => {
    const d = new DiffDoc();
    d.apply(full(0, 'a\nb\nc'));
    // Raw envelope as Neovim would emit for a deletion: "lines":{}
    const raw = ENVELOPE_PREFIX + '{"t":"d","v":1,"base":0,"edits":[{"start":1,"count":1,"lines":{}}]}';
    expect(d.apply(raw)).toBe('a\nc');
  });

  it('returns null on malformed JSON', () => {
    const d = new DiffDoc();
    expect(d.apply(ENVELOPE_PREFIX + 'not json')).toBeNull();
  });

  // Integration guard: these are the EXACT envelope strings ws_client.send_content
  // emits (captured from a headless Neovim run). If the Lua encoder's shape ever
  // drifts from what DiffDoc parses, this breaks.
  it('reconstructs text from real Lua-emitted envelopes', () => {
    const P = ENVELOPE_PREFIX;
    const d = new DiffDoc();
    expect(d.apply(P + '{"t":"f","v":1,"text":"# Title\\nline b\\nline c"}')).toBe(
      '# Title\nline b\nline c',
    );
    expect(
      d.apply(P + '{"t":"d","v":2,"edits":[{"lines":["line B"],"start":1,"count":1}],"base":1}'),
    ).toBe('# Title\nline B\nline c');
    expect(
      d.apply(P + '{"t":"d","v":3,"edits":[{"lines":["line d"],"start":3,"count":0}],"base":2}'),
    ).toBe('# Title\nline B\nline c\nline d');
  });
});
