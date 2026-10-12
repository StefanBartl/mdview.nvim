// tests/client/editState.test.ts
//
// The block-edit switch survives a reload, but only within its own session.

import { describe, it, expect } from 'vitest';
import { readEditState, writeEditState } from '../../src/client/render/editState';

function memory() {
  const data = new Map<string, string>();
  return {
    getItem: (k: string) => data.get(k) ?? null,
    setItem: (k: string, v: string) => void data.set(k, v),
  };
}

describe('edit state', () => {
  it('is null before anything was stored', () => {
    expect(readEditState('t1', '/a.md', memory())).toBeNull();
  });

  it('reads back what was written, on and off', () => {
    const s = memory();
    writeEditState('t1', '/a.md', true, s);
    expect(readEditState('t1', '/a.md', s)).toBe(true);
    writeEditState('t1', '/a.md', false, s);
    expect(readEditState('t1', '/a.md', s)).toBe(false);
  });

  it('ignores a choice made under another session token', () => {
    const s = memory();
    writeEditState('old', '/a.md', true, s);
    expect(readEditState('new', '/a.md', s)).toBeNull();
  });

  it('keeps rooms apart', () => {
    const s = memory();
    writeEditState('t1', '/a.md', true, s);
    expect(readEditState('t1', '/b.md', s)).toBeNull();
  });

  it('copes with a token that contains a colon', () => {
    const s = memory();
    writeEditState('a:b', '/a.md', true, s);
    expect(readEditState('a:b', '/a.md', s)).toBe(true);
  });

  it('ignores garbage', () => {
    const s = memory();
    s.setItem('mdview-edit:/a.md', 'nonsense');
    expect(readEditState('t1', '/a.md', s)).toBeNull();
    s.setItem('mdview-edit:/a.md', 't1:x');
    expect(readEditState('t1', '/a.md', s)).toBeNull();
  });

  it('never throws when storage is missing or broken', () => {
    expect(readEditState('t', 'k', null)).toBeNull();
    expect(() => writeEditState('t', 'k', true, null)).not.toThrow();
    const broken = {
      getItem: () => {
        throw new Error('blocked');
      },
      setItem: () => {
        throw new Error('blocked');
      },
    };
    expect(readEditState('t', 'k', broken)).toBeNull();
    expect(() => writeEditState('t', 'k', true, broken)).not.toThrow();
  });
});
