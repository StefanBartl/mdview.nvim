// @vitest-environment jsdom
//
// A refused toggle puts the box back on the state the source has, also with
// several clicks in flight and answers that arrive in any order.

import { describe, it, expect } from 'vitest';
import { enableTaskCheckboxes, installTaskToggle } from '../../src/client/render/taskToggle';

const HTML = '<ul><li data-sourcepos="3:1-3:11"><input type="checkbox" disabled> alpha</li></ul>';
const flush = () => new Promise(resolve => setTimeout(resolve, 0));

interface Pending {
  resolve: (ok: boolean) => void;
  reject: (err: unknown) => void;
}

/** A box whose sends stay open until the test answers them. */
function setup() {
  const root = document.createElement('div');
  root.innerHTML = HTML;
  document.body.appendChild(root);
  enableTaskCheckboxes(root);
  const pending: Pending[] = [];
  installTaskToggle(root, () => {
    return new Promise<boolean>((resolve, reject) => pending.push({ resolve, reject }));
  });
  const box = root.querySelector<HTMLInputElement>('input[type="checkbox"]')!;
  const click = (v: boolean) => {
    box.checked = v;
    box.dispatchEvent(new window.Event('change', { bubbles: true }));
  };
  return { box, pending, click };
}

describe('refused toggles with several clicks in flight', () => {
  it('ok then refused ends on the saved tick', async () => {
    const { box, pending, click } = setup();
    click(true);
    click(false);
    pending[0].resolve(true);
    pending[1].resolve(false);
    await flush();
    expect(box.checked).toBe(true); // the source holds the first tick
  });

  it('refused then ok ends on the unticked, saved state', async () => {
    const { box, pending, click } = setup();
    click(true);
    click(false);
    pending[0].resolve(false);
    pending[1].resolve(true);
    await flush();
    expect(box.checked).toBe(false);
  });

  it('does not move the box before the last answer is in', async () => {
    const { box, pending, click } = setup();
    click(true);
    click(false);
    click(true);
    pending[2].resolve(false);
    await flush();
    expect(box.checked).toBe(true); // still waiting for two answers
    pending[0].resolve(false);
    pending[1].resolve(false);
    await flush();
    expect(box.checked).toBe(false); // nothing was saved: the source never changed
  });

  it('answers that arrive late and out of order still leave the newest saved state', async () => {
    const { box, pending, click } = setup();
    click(true); // 0
    click(false); // 1
    click(true); // 2
    pending[2].resolve(false);
    pending[1].resolve(true); // the source is unticked
    pending[0].resolve(true); // the older answer comes last: must not win
    await flush();
    expect(box.checked).toBe(false);
  });

  it('a send that rejects counts as refused and does not leave the box stuck', async () => {
    const { box, pending, click } = setup();
    click(true);
    pending[0].reject(new Error('toast failed'));
    await flush();
    expect(box.checked).toBe(false);
    click(true); // a later refusal still works
    pending[1].resolve(false);
    await flush();
    expect(box.checked).toBe(false);
  });
});
