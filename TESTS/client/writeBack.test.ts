import { describe, it, expect, vi } from 'vitest';
import {
  WRITE_BACK_MESSAGES,
  MAX_EXPECTED_BYTES,
  postJson,
  postText,
  resultOfStatus,
  writeBackUrl,
} from '../../src/client/render/writeBack';

describe('writeBackUrl', () => {
  it('names the token and the room', () => {
    expect(writeBackUrl('/toggle', { token: 't0k', key: 'C:/n/a.md' })).toBe(
      '/toggle?token=t0k&key=C%3A%2Fn%2Fa.md',
    );
  });

  it('adds the document on screen when there is one', () => {
    expect(writeBackUrl('/edit', { token: 't', key: 'room.md', doc: '/n/other file.md' })).toBe(
      '/edit?token=t&key=room.md&doc=%2Fn%2Fother%20file.md',
    );
  });

  it('leaves doc and expected out when unknown or empty', () => {
    expect(writeBackUrl('/field', { token: 't', key: 'k', doc: null })).toBe('/field?token=t&key=k');
    expect(writeBackUrl('/field', { token: 't', key: 'k', doc: '', expected: '' })).toBe(
      '/field?token=t&key=k',
    );
  });

  it('carries the line a toggle was computed against', () => {
    expect(writeBackUrl('/toggle', { token: 't', key: 'k', expected: '- [ ] a & b' })).toBe(
      '/toggle?token=t&key=k&expected=-%20%5B%20%5D%20a%20%26%20b',
    );
  });

  it('encodes values that could break the query', () => {
    const url = writeBackUrl('/edit', { token: 'a&b=c', key: 'k#1', doc: 'x?y' });
    expect(url).toBe('/edit?token=a%26b%3Dc&key=k%231&doc=x%3Fy');
  });
});

describe('resultOfStatus', () => {
  it('maps the relay answers to a result', () => {
    expect(resultOfStatus(204)).toBe('ok');
    expect(resultOfStatus(409)).toBe('stale');
    expect(resultOfStatus(403)).toBe('refused'); // no --edit, a wrong token ...
    expect(resultOfStatus(403, 'the file is read-only\n')).toBe('readonly');
    expect(resultOfStatus(413)).toBe('too-large');
    expect(resultOfStatus(500)).toBe('refused');
    expect(resultOfStatus(404)).toBe('refused');
  });

  it('has a message for every result that is not ok', () => {
    for (const r of ['stale', 'readonly', 'too-large', 'refused', 'offline'] as const) {
      expect(WRITE_BACK_MESSAGES[r]).toMatch(/^Not saved/);
    }
  });
});

describe('postJson', () => {
  it('posts the JSON body and returns the mapped status', async () => {
    const fetchFn = vi.fn(async () => new Response(null, { status: 409 }));
    const result = await postJson(fetchFn as unknown as typeof fetch, '/edit?x=1', { a: 1 });
    expect(result).toBe('stale');
    const [url, init] = fetchFn.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('/edit?x=1');
    expect(init.method).toBe('POST');
    expect(init.body).toBe('{"a":1}');
  });

  it('never rejects: a network failure is offline', async () => {
    const fetchFn = vi.fn(async () => {
      throw new TypeError('network down');
    });
    await expect(postJson(fetchFn as unknown as typeof fetch, '/edit', {})).resolves.toBe('offline');
  });
});

describe('writeBackUrl, the longest expected line', () => {
  it('leaves `expected` out above the relay bound (counted in bytes), keeps it at the bound', () => {
    const atBound = 'x'.repeat(MAX_EXPECTED_BYTES);
    expect(writeBackUrl('/toggle', { token: 't', key: 'k', expected: atBound })).toContain('&expected=');
    expect(writeBackUrl('/toggle', { token: 't', key: 'k', expected: atBound + 'x' })).toBe(
      '/toggle?token=t&key=k',
    );
    // 1025 two-byte characters are 2050 bytes, though only 1025 characters
    expect(writeBackUrl('/toggle', { token: 't', key: 'k', expected: 'ä'.repeat(1025) })).toBe(
      '/toggle?token=t&key=k',
    );
  });
});

describe('postText / 403 answers', () => {
  it('posts plain text and reports a refusal that says read-only as readonly', async () => {
    const fetchFn = vi.fn(async () => new Response('the file is read-only\n', { status: 403 }));
    expect(await postText(fetchFn as unknown as typeof fetch, '/toggle', '3:1', true)).toBe('readonly');
    const [, init] = fetchFn.mock.calls[0] as unknown as [string, RequestInit];
    expect(init.body).toBe('3:1');
    expect(init.keepalive).toBe(true);
    expect((init.headers as Record<string, string>)['Content-Type']).toBe('text/plain');
  });

  it('any other 403 (no --edit, a wrong token) is a plain refusal, and 5xx too', async () => {
    const f403 = vi.fn(async () => new Response('block editing is off\n', { status: 403 }));
    expect(await postText(f403 as unknown as typeof fetch, '/toggle', '3:1')).toBe('refused');
    const f500 = vi.fn(async () => new Response('toggle failed\n', { status: 500 }));
    expect(await postJson(f500 as unknown as typeof fetch, '/field', {})).toBe('refused');
  });
});
