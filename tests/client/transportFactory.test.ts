// tests/client/transportFactory.test.ts
//
// Unit tests for createTransport's transport selection and fallback. The real
// WebSocket / WebTransport wire paths need a browser + a live relay, so here we
// stub the globals and assert only the decision logic: when WebTransport is
// preferred and available it is used; on any failure (or lack of support, or
// no opt-in) it falls back to WebSocket without throwing.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTransport } from '../../src/client/transport/transportFactory';

const realWebSocket = globalThis.WebSocket;
const realWebTransport = (globalThis as Record<string, unknown>).WebTransport;

// A fake WebSocket whose constructor immediately "opens" so initialize()
// resolves. createTransport awaits WebSocketTransport.initialize().
class FakeWebSocket {
  static OPEN = 1;
  readyState = 1;
  onopen: (() => void) | null = null;
  onmessage: ((ev: { data: unknown }) => void) | null = null;
  onerror: ((ev: unknown) => void) | null = null;
  constructor(public url: string) {
    queueMicrotask(() => this.onopen?.());
  }
  send() {}
  close() {}
}

afterEach(() => {
  globalThis.WebSocket = realWebSocket;
  (globalThis as Record<string, unknown>).WebTransport = realWebTransport;
  vi.restoreAllMocks();
});

beforeEach(() => {
  globalThis.WebSocket = FakeWebSocket as unknown as typeof WebSocket;
});

describe('createTransport', () => {
  it('uses WebSocket when WebTransport is not opted in', async () => {
    const log = vi.fn();
    const t = await createTransport('ws://localhost:1/ws', { log });
    expect(t).toBeTruthy();
    // No WebTransport-related logging when not opted in.
    expect(log).toHaveBeenCalledWith('transport active: websocket');
  });

  it('falls back to WebSocket when WebTransport is unsupported', async () => {
    delete (globalThis as Record<string, unknown>).WebTransport;
    const log = vi.fn();
    const t = await createTransport('ws://localhost:1/ws', {
      preferWebTransport: true,
      webTransportUrl: 'https://localhost:1/wt',
      log,
    });
    expect(t).toBeTruthy();
    expect(log).toHaveBeenCalledWith(expect.stringContaining('unsupported'));
  });

  it('falls back to WebSocket when WebTransport connection fails', async () => {
    // A WebTransport whose `ready` rejects — simulates no HTTP/3 backend.
    class FailingWebTransport {
      ready = Promise.reject(new Error('connection refused'));
      closed = Promise.resolve();
      async createBidirectionalStream() {
        throw new Error('unreachable');
      }
      close() {}
    }
    (globalThis as Record<string, unknown>).WebTransport = FailingWebTransport;
    const log = vi.fn();
    const t = await createTransport('ws://localhost:1/ws', {
      preferWebTransport: true,
      webTransportUrl: 'https://localhost:1/wt',
      log,
    });
    expect(t).toBeTruthy(); // did not throw — fell back
    expect(log).toHaveBeenCalledWith(expect.stringContaining('falling back to WebSocket'));
  });

  it('uses WebTransport when opted in, supported, and connecting succeeds', async () => {
    class OkWebTransport {
      ready = Promise.resolve();
      closed = Promise.resolve();
      async createBidirectionalStream() {
        return {
          readable: { getReader: () => ({ read: () => new Promise(() => {}) }) },
          writable: { getWriter: () => ({ write: async () => {}, close: async () => {} }) },
        };
      }
      close() {}
    }
    (globalThis as Record<string, unknown>).WebTransport = OkWebTransport;
    const log = vi.fn();
    const t = await createTransport('ws://localhost:1/ws', {
      preferWebTransport: true,
      webTransportUrl: 'https://localhost:1/wt',
      log,
    });
    expect(t).toBeTruthy();
    expect(log).toHaveBeenCalledWith('transport active: webtransport');
  });
});
