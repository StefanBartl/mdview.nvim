// tests/client/clickNav.dom.test.ts
// @vitest-environment jsdom
//
// Real-DOM test for installClickNav: a click on a relative link inside the
// container must be intercepted (default prevented, target sent), while
// external links, anchors and modifier-clicks are left to the browser.

import { describe, it, expect, vi } from 'vitest';
import { installClickNav } from '../../src/client/render/clickNav';

function setup(html: string) {
  const root = document.createElement('div');
  root.innerHTML = html;
  document.body.appendChild(root);
  const send = vi.fn();
  installClickNav(root, send);
  return { root, send };
}

function clickFirstLink(root: HTMLElement, init: MouseEventInit = {}) {
  const a = root.querySelector('a')!;
  const ev = new window.MouseEvent('click', { bubbles: true, cancelable: true, button: 0, ...init });
  a.dispatchEvent(ev);
  return ev;
}

describe('installClickNav (real DOM)', () => {
  it('intercepts a relative link (as the WASM renders it)', () => {
    // exactly what render_markdown emits for [testlink](./docs/PoC.md)
    const { root, send } = setup('<p><a href="./docs/PoC.md" rel="noopener noreferrer">testlink</a></p>');
    const ev = clickFirstLink(root);
    expect(ev.defaultPrevented).toBe(true);
    expect(send).toHaveBeenCalledWith('./docs/PoC.md');
  });

  it('intercepts when the click lands on a child of the anchor', () => {
    const { root, send } = setup('<a href="sub/x.md"><code>x</code></a>');
    const code = root.querySelector('code')!;
    const ev = new window.MouseEvent('click', { bubbles: true, cancelable: true, button: 0 });
    code.dispatchEvent(ev);
    expect(ev.defaultPrevented).toBe(true);
    expect(send).toHaveBeenCalledWith('sub/x.md');
  });

  it('leaves external links to the browser', () => {
    const { root, send } = setup('<a href="https://example.com">ext</a>');
    const ev = clickFirstLink(root);
    expect(ev.defaultPrevented).toBe(false);
    expect(send).not.toHaveBeenCalled();
  });

  it('leaves ctrl/meta-clicks alone (open in new tab)', () => {
    const { root, send } = setup('<a href="other.md">x</a>');
    const ev = clickFirstLink(root, { ctrlKey: true });
    expect(ev.defaultPrevented).toBe(false);
    expect(send).not.toHaveBeenCalled();
  });
});
