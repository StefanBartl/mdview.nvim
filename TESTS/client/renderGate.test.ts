// tests/client/renderGate.test.ts
//
// The render gate: a text that arrives while an editor is open is held back,
// only the newest one is kept, and it is rendered when the hold ends.

import { describe, it, expect } from 'vitest';
import { createRenderGate } from '../../src/client/render/renderGate';

function setup() {
  const rendered: string[] = [];
  let held = false;
  const gate = createRenderGate({
    isHeld: () => held,
    render: text => rendered.push(text),
  });
  return {
    gate,
    rendered,
    hold: (value: boolean) => {
      held = value;
    },
  };
}

describe('createRenderGate', () => {
  it('renders at once while not held', () => {
    const t = setup();
    t.gate.push('a');
    t.gate.push('b');
    expect(t.rendered).toEqual(['a', 'b']);
    expect(t.gate.pending()).toBe(false);
  });

  it('holds a text back while held and keeps only the newest', () => {
    const t = setup();
    t.hold(true);
    t.gate.push('a');
    t.gate.push('b');
    expect(t.rendered).toEqual([]);
    expect(t.gate.pending()).toBe(true);
    expect(t.gate.current('screen')).toBe('b');
  });

  it('release renders the newest held text once', () => {
    const t = setup();
    t.hold(true);
    t.gate.push('a');
    t.gate.push('b');
    t.hold(false);
    expect(t.gate.release()).toBe(true);
    expect(t.rendered).toEqual(['b']);
    expect(t.gate.pending()).toBe(false);
    expect(t.gate.release()).toBe(false);
    expect(t.rendered).toEqual(['b']);
  });

  it('current is the text on screen when nothing is held', () => {
    const t = setup();
    expect(t.gate.current('screen')).toBe('screen');
  });

  it('a text pushed after the hold ended is rendered and drops a stale held one', () => {
    const t = setup();
    t.hold(true);
    t.gate.push('old');
    t.hold(false);
    t.gate.push('new');
    expect(t.rendered).toEqual(['new']);
    expect(t.gate.release()).toBe(false);
  });

  it('release without anything held renders nothing', () => {
    const t = setup();
    expect(t.gate.release()).toBe(false);
    expect(t.rendered).toEqual([]);
  });
});
