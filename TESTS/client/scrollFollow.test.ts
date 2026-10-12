// tests/client/scrollFollow.test.ts
//
// The scroll ping: its cursor fields, and the ping that is kept while a block
// editor hides the target block and applied when it closes.

import { describe, it, expect } from 'vitest';
import {
  SCROLL_SUPPRESS_MS,
  createScrollFollower,
  parseCursorFields,
} from '../../src/client/render/scrollFollow';

describe('parseCursorFields', () => {
  it('reads line and column', () => {
    expect(parseCursorFields('12/100/0.5/7')).toEqual({ line: 12, col: 7 });
  });

  it('has no column when the ping carries none', () => {
    expect(parseCursorFields('12/100/0.5')).toEqual({ line: 12, col: -1 });
    expect(parseCursorFields('12/100/0.5/x')).toEqual({ line: 12, col: -1 });
  });

  it('is null when the line is not a number', () => {
    expect(parseCursorFields('x/100/0.5')).toBeNull();
  });
});

describe('createScrollFollower', () => {
  function setup() {
    const applied: string[] = [];
    let clock = 1000;
    const follower = createScrollFollower({ apply: m => applied.push(m), now: () => clock });
    return {
      follower,
      applied,
      advance: (ms: number) => {
        clock += ms;
      },
    };
  }

  it('applies a ping at once when no editor is open', () => {
    const t = setup();
    t.follower.receive('P1', false);
    expect(t.applied).toEqual(['P1']);
    expect(t.follower.catchUp()).toBe(false);
  });

  it('keeps the newest ping while an editor is open and applies it on catchUp', () => {
    const t = setup();
    t.follower.receive('P1', true);
    t.follower.receive('P2', true);
    expect(t.applied).toEqual([]);
    expect(t.follower.catchUp()).toBe(true);
    expect(t.applied).toEqual(['P2']);
    expect(t.follower.catchUp()).toBe(false);
  });

  it('suppresses the echo of an applied ping for a short while', () => {
    const t = setup();
    expect(t.follower.suppressed()).toBe(false);
    t.follower.receive('P1', false);
    expect(t.follower.suppressed()).toBe(true);
    t.advance(SCROLL_SUPPRESS_MS + 1);
    expect(t.follower.suppressed()).toBe(false);
  });

  it('suppresses again after a catch-up, because that scrolls too', () => {
    const t = setup();
    t.follower.receive('P1', true);
    t.advance(SCROLL_SUPPRESS_MS + 1);
    expect(t.follower.suppressed()).toBe(false);
    t.follower.catchUp();
    expect(t.follower.suppressed()).toBe(true);
  });
});
