## Zustimmung und Architekturvorschlag (Kurz)

Ja — dem Vorschlag zustimmen. Die sauberste, wartbare Lösung ist eine **Transport-Adapter-Abstraktion** mit klar getrennten Implementierungen in separaten Dateien (keine Vermischung von WebSocket und WebTransport in einer Datei). Der Auswahl-Mechanismus ist dev-kontrollierbar (Feature-Flag im Quellcode), der Client macht zusätzlich eine **Feature-Detect** auf `window.WebTransport`. Je nach Flag + Detektion wird genau **eine** Implementierung dynamisch geladen. Dadurch bleibt der Code modular, testbar und das Risiko gering.

---

## Prinzipien / Anforderungen an die Implementierung

* **Single Responsibility:** jede Transport-Implementierung in eigener Datei (`websocket.transport.ts`, `webtransport.transport.ts`).
* **Transport-Interface:** ein gemeinsames TypeScript-Interface (`Transport`) beschreibt die API (sendMessage, onMessage, sendDatagram optional, openStream optional, close).
* **Factory/Bootstrap:** `transportFactory.ts` entscheidet (dev-flag + feature-detect) und lädt per dynamic `import()` genau die benötigte Implementierung.
* **Dev opt-in:** Flag `DEV_USE_WEBTRANSPORT = true|false` in `src/client/dev-config.ts` (nur für Entwickler im Source, nicht in user config).
* **Fallback:** wenn Flag true, aber Browser nicht unterstützt oder Server nicht WebTransport-ready, Fallback auf WebSocket.
* **No-mix:** Nie in einer Implementationsdatei WebSocket- und WebTransport-APIs mischen.
* **Tests & Mocks:** Unit-Tests für `transportFactory` + Mock-Implementierungen, E2E mit Playwright/Headless für beide Transports.
* **Docs:** README-Abschnitt: Wie man opt-in setzt, wie man die WebTransport-POC-Datei implementiert.

---

## Empfohlene Dateistruktur (Client)

```
src/
└─ client/
   ├─ transport/
   │  ├─ transport.interface.ts       # Transport interface (shared)
   │  ├─ websocket.transport.ts       # WebSocket implementation
   │  └─ webtransport.transport.ts    # WebTransport implementation (stub for now)
   ├─ transportFactory.ts            # decides which transport to import
   ├─ dev-config.ts                  # DEV_USE_WEBTRANSPORT flag
   ├─ main.ts                        # app bootstrapping — uses transportFactory
   └─ ... (other client files)
```

---

## Transport Interface (TypeScript)

```ts
// src/client/transport/transport.interface.ts
// English comments per project rules

export interface Transport {
  /**
   * Open / initialize the transport (connect or wait for ready).
   * May perform async handshake.
   */
  initialize(): Promise<void>;

  /**
   * Send a textual message (JSON encoded).
   */
  sendMessage(message: string): Promise<void>;

  /**
   * Register callback for inbound textual messages.
   */
  onMessage(cb: (message: string) => void): void;

  /**
   * Optional: send a best-effort datagram (unreliable).
   */
  sendDatagram?(data: Uint8Array): void;

  /**
   * Close the transport.
   */
  close(): Promise<void>;
}
```

---

## WebSocket Implementation (TS)

```ts
// src/client/transport/websocket.transport.ts
// English comments in code

import type { Transport } from "./transport.interface";

export class WebSocketTransport implements Transport {
  private ws!: WebSocket;
  private url: string;
  private onMessageCb?: (message: string) => void;

  constructor(url: string) {
    this.url = url;
  }

  async initialize(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(this.url);
      this.ws.addEventListener("open", () => resolve());
      this.ws.addEventListener("message", (ev) => {
        const data = typeof ev.data === "string" ? ev.data : String(ev.data);
        if (this.onMessageCb) this.onMessageCb(data);
      });
      this.ws.addEventListener("error", (err) => reject(err));
    });
  }

  async sendMessage(message: string): Promise<void> {
    if (this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(message);
    } else {
      // simple wait / retry pattern could be added
      await new Promise((r) => setTimeout(r, 10));
      this.ws.send(message);
    }
  }

  onMessage(cb: (message: string) => void): void {
    this.onMessageCb = cb;
  }

  async close(): Promise<void> {
    this.ws.close();
  }
}
```

---

## WebTransport Implementation (TS stub / placeholder)

```ts
// src/client/transport/webtransport.transport.ts
// English comments in code
// NOTE: This is a stub/POC skeleton. Real implementation needs HTTP/3 server & TLS.

import type { Transport } from "./transport.interface";

export class WebTransportAdapter implements Transport {
  private session!: WebTransport;
  private onMessageCb?: (message: string) => void;
  private url: string;

  constructor(url: string) {
    // use https scheme for WebTransport
    this.url = url.replace(/^ws:/, "https:").replace(/^wss:/, "https:");
  }

  async initialize(): Promise<void> {
    // Feature detect at runtime: abort if not supported
    if (!(window as any).WebTransport) {
      throw new Error("WebTransport not available in this browser");
    }

    this.session = new (window as any).WebTransport(this.url);
    await this.session.ready;

    // wire incoming bidirectional streams (example)
    (async () => {
      for await (const stream of this.session.incomingBidirectionalStreams) {
        const reader = stream.readable.getReader();
        const chunks: Uint8Array[] = [];
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          chunks.push(value);
        }
        const text = new TextDecoder().decode(concat(chunks));
        if (this.onMessageCb) this.onMessageCb(text);
      }
    })();
  }

  async sendMessage(message: string): Promise<void> {
    const { writable } = await this.session.createBidirectionalStream();
    const writer = writable.getWriter();
    await writer.write(new TextEncoder().encode(message));
    await writer.close();
  }

  onMessage(cb: (message: string) => void): void {
    this.onMessageCb = cb;
  }

  sendDatagram(data: Uint8Array): void {
    this.session.datagrams?.send(data);
  }

  async close(): Promise<void> {
    await this.session.close();
  }
}

/** helper to concat Uint8Array chunks */
function concat(chunks: Uint8Array[]): Uint8Array {
  const total = chunks.reduce((s, c) => s + c.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.length;
  }
  return out;
}
```

> Hinweis: Obige WebTransport-Implementierung ist ein POC-Skeleton. Server-seitig ist HTTP/3 + TLS erforderlich — daher ist die Datei vorerst ein Stub, die beim opt-in aktiviert wird.

---

## Transport Factory (dynamischer Loader)

```ts
// src/client/transportFactory.ts
// English comments in code

import { Transport } from "./transport/transport.interface";
import { DEV_USE_WEBTRANSPORT } from "./dev-config";

// Returns a transport instance. This function uses dynamic import so that
// the WebTransport implementation is only loaded when selected.
export async function createTransport(url: string): Promise<Transport> {
  // Developer opt-in at build/source level
  if (DEV_USE_WEBTRANSPORT) {
    // runtime feature detect
    if ((window as any).WebTransport) {
      const mod = await import("./transport/webtransport.transport");
      const t = new mod.WebTransportAdapter(url);
      await t.initialize();
      return t;
    } else {
      // fallback to ws if browser does not support WebTransport
      const mod = await import("./transport/websocket.transport");
      const t = new mod.WebSocketTransport(url);
      await t.initialize();
      return t;
    }
  } else {
    // default path: WebSocket
    const mod = await import("./transport/websocket.transport");
    const t = new mod.WebSocketTransport(url);
    await t.initialize();
    return t;
  }
}
```

---

## Dev opt-in Flag (dev only)

```ts
// src/client/dev-config.ts
// English comments in code
// Toggle this flag in source during development to test WebTransport branch.
// NOTE: not exposed to end users in config for now.

export const DEV_USE_WEBTRANSPORT = false;
```

---

## Integration in `main.ts`

```ts
// src/client/main.ts
// English comments in code

import { createTransport } from "./transportFactory";

async function boot() {
  const url = `ws://${location.host}/ws`; // factory may convert if using WebTransport
  const transport = await createTransport(url);

  transport.onMessage((msg) => {
    // handle incoming render_update etc.
    console.log("message", msg);
  });

  // Example usage
  await transport.sendMessage(JSON.stringify({ type: "hello" }));
}

boot().catch((err) => console.error("boot failed:", err));
```

---

## Anpassungen auf Server-Seite (Kurz)

* Server muss langfristig **dual-stack** sein: expose both `/ws` (WebSocket) and `/wt` (WebTransport) endpoints. Für jetzt reicht `/ws`.
* WebTransport-Endpoint erfordert anfangs ein **separates server binary** (Rust/QUIC or Edge runtime) oder experimentelle Node lib. Deshalb: implement WebTransport endpoint später als separater process `webtransport.server.*` und document how to run it.
* Keep the existing WebSocket server unchanged.

---

## Vorteile dieses Vorgehens

* **Minimaler initialer Aufwand:** nur Factory + separate stub file; keine Änderung an bestehenden WebSocket-code nötig.
* **Sauberer Code:** keine Vermischung von transports; jede Implementierung bleibt übersichtlich.
* **Feature-toggle:** Entwickler können WebTransport lokal testen ohne User-Konfiguration oder Breaking Changes.
* **Futuresafe:** Bereit für echtes WebTransport-POC später, ohne Refactor-Pain.

---

## Risiken / Nachteile

* **Dynamische Imports erhöhen Bundle-Komplexität:** Vite will bundlen beide Dateien, aber lazy loading hält runtime-kosten niedrig. Dokumentation für CI/Build beachten.
* **Server-Komplexität später:** Betrieb eines HTTP/3 WebTransport servers ist aufwändiger (TLS, QUIC). Für now: keep WebSocket default.
* **Testaufwand:** Zusätzliche Tests nötig (mocks, integration).

---

## Test- & Implementierungscheckliste (aufgabenorientiert, checkbox)

* [ ] `src/client/transport/transport.interface.ts` anlegen
* [ ] `src/client/transport/websocket.transport.ts` anlegen (fertigstellen / Unit-tests)
* [ ] `src/client/transport/webtransport.transport.ts` als POC-stub anlegen (keine server-abhängigkeit yet)
* [ ] `src/client/transportFactory.ts` anlegen (dev opt-in logic + dynamic import)
* [ ] `src/client/dev-config.ts` anlegen mit `DEV_USE_WEBTRANSPORT = false`
* [ ] `src/client/main.ts` anpassen um `createTransport` zu benutzen
* [ ] Unit-tests für `transportFactory` (mock window.WebTransport + mock imports)
* [ ] Integration test for WebSocket path (existing server)
* [ ] Documentation: README section „Dev opt-in WebTransport (how to)“
* [ ] Create server stub notes: `src/server/webtransport.server.*` (todo) and document requirements (HTTP/3, TLS)
* [ ] Add CI job entry (optional) to run transport factory unit tests

---

## Weiteres: Hinweise für Build / Vite

* Dynamic `import()` funktioniert mit Vite; beide Implementierungen werden gebündelt, doch nur die tatsächlich importierte Klasse instanziiert. Falls man die WebTransport-implementierung später angesichts Node-API/Types zu groß findet, kann man separate chunking/conditional build-strategy nutzen.
* Achte auf `tsconfig` und linter: referenzen zu DOM-types (`WebTransport`) sind Browser-only — typedefs sollten nur in client-ts files auftauchen (kein `lib: ["DOM"]` in server tsconfig).

---

## Fazit

Der vorgeschlagene Weg ist robust, minimal invasiv und zukunftssicher: eine kleine Factory + dev flag + separate Implementationsdateien geben genau die gewünschte Trennung. Es entstehen keine großen Risiken, solange WebTransport zunächst nur als dev-opt-in stub verbleibt und WebSocket Standard bleibt.

Wenn gewünscht, erstelle ich jetzt die konkreten Dateien (TS-Templates + Teststubs + README-Abschnitt) als Patch/Copypaste, damit man sie direkt ins Repo legen kann. Welche Dateien sollen zuerst generiert werden?
