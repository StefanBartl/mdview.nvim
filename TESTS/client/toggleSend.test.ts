// tests/client/toggleSend.test.ts
//
// postToggle: the "<line>:<0|1>" body and the stale-line guard in the URL.
// sendToggle: the line as rendered goes along, and a document with lone CR line
// endings is not sent at all.

import { describe, it, expect, vi } from 'vitest';
import { MAX_EXPECTED_BYTES, postToggle } from '../../src/client/render/writeBack';
import { sendToggle } from '../../src/client/render/toggleSend';

function answering(status: number) {
  return vi.fn(async () => ({ status, text: async () => '' }) as unknown as Response);
}

describe('postToggle', () => {
  it('sends line and state, with the line it was computed against', async () => {
    const fetchFn = answering(200);
    const result = await postToggle(
      fetchFn as unknown as typeof fetch,
      { token: 't', key: 'k', doc: '/a b.md', expected: '- [ ] task' },
      3,
      true,
    );
    expect(result).toBe('ok');
    const [url, init] = fetchFn.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe(
      `/toggle?token=t&key=k&doc=${encodeURIComponent('/a b.md')}&expected=${encodeURIComponent('- [ ] task')}`,
    );
    expect(init.body).toBe('3:1');
    expect(init.method).toBe('POST');
    // A small request may outlive the page.
    expect(init.keepalive).toBe(true);
  });

  it('sends 0 for an unticked box', async () => {
    const fetchFn = answering(200);
    await postToggle(fetchFn as unknown as typeof fetch, { token: 't', key: 'k' }, 7, false);
    expect((fetchFn.mock.calls[0] as unknown as [string, RequestInit])[1].body).toBe('7:0');
  });

  it('leaves expected out when it is too long for the relay', async () => {
    const fetchFn = answering(200);
    await postToggle(
      fetchFn as unknown as typeof fetch,
      { token: 't', key: 'k', expected: '- [ ] ' + 'x'.repeat(MAX_EXPECTED_BYTES) },
      1,
      true,
    );
    expect((fetchFn.mock.calls[0] as unknown as [string])[0]).not.toContain('expected=');
  });

  it('maps a refusal and a network failure to a result', async () => {
    const stale = answering(409);
    expect(
      await postToggle(stale as unknown as typeof fetch, { token: 't', key: 'k' }, 1, true),
    ).toBe('stale');
    const down = vi.fn(async () => {
      throw new Error('down');
    });
    expect(
      await postToggle(down as unknown as typeof fetch, { token: 't', key: 'k' }, 1, true),
    ).toBe('offline');
  });
});

describe('sendToggle', () => {
  const target = { token: 't', key: 'k' };

  it('cuts expected from the line as rendered', async () => {
    const fetchFn = answering(200);
    const text = ['# T', '', '- [ ] one', '- [ ] two', ''].join('\n');
    expect(await sendToggle(fetchFn as unknown as typeof fetch, target, text, 4, true)).toBe('ok');
    const [url, init] = fetchFn.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toContain(`expected=${encodeURIComponent('- [ ] two')}`);
    expect(init.body).toBe('4:1');
  });

  it('cuts expected from a CRLF document without the CR', async () => {
    const fetchFn = answering(200);
    const text = ['- [ ] a', '- [ ] b'].join('\r\n') + '\r';
    await sendToggle(fetchFn as unknown as typeof fetch, target, text, 2, true);
    expect((fetchFn.mock.calls[0] as unknown as [string])[0]).toContain(
      `expected=${encodeURIComponent('- [ ] b')}`,
    );
  });

  it('sends nothing for a document with lone CR line endings', async () => {
    const fetchFn = answering(200);
    // comrak numbers "- [ ] x" as line 3 here, the source has it on line 2
    const text = 'a\rb\n- [ ] x\n- [ ] y';
    expect(await sendToggle(fetchFn as unknown as typeof fetch, target, text, 3, true)).toBe(
      'bare-cr',
    );
    expect(fetchFn).not.toHaveBeenCalled();
  });

  it('passes a refusal on', async () => {
    const stale = answering(409);
    expect(await sendToggle(stale as unknown as typeof fetch, target, '- [ ] a', 1, true)).toBe(
      'stale',
    );
  });
});
