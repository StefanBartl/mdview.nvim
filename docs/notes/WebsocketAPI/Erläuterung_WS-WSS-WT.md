# Vergleich: WebSocket API vs. WebSocketStream API vs. WebTransport

  Im Folgenden wird die Situation sachlich aufgeschlüsselt, Vor- und Nachteile werden gegeneinander abgewogen, und praktische Empfehlungen sowie ein Adapter-Pattern für den Server werden vorgeschlagen. Antworten sind allgemein gültig formuliert, technische Details sind auf die von Ihnen gezeigte `MdviewServer`-Architektur anwendbar.

---

## Table of content

  - [Kurzüberblick — technische Gemeinsamkeiten und Unterschiede](#kurzberblick-technische-gemeinsamkeiten-und-unterschiede)
  - [Auf „Zuverlässigkeit“ bezogen: was ist gemeint?](#auf-zuverlssigkeit-bezogen-was-ist-gemeint)
  - [Praktische Auswirkungen auf Ihr `MdviewServer` (Konsequenzen & Aufwand)](#praktische-auswirkungen-auf-ihr-mdviewserver-konsequenzen-aufwand)
    - [1) Kompatibilität & Infrastruktur](#1-kompatibilitt-infrastruktur)
    - [2) API / Code-Änderungen](#2-api-code-nderungen)
    - [3) Performance & Semantik](#3-performance-semantik)
  - [Empfehlungen, priorisiert (praktisch, risikobewusst)](#empfehlungen-priorisiert-praktisch-risikobewusst)
  - [Adapter-Pattern — vorgeschlagene Struktur (Beispiel)](#adapter-pattern-vorgeschlagene-struktur-beispiel)
    - [Adapter interface (TypeScript sketch, English comments)](#adapter-interface-typescript-sketch-english-comments)
    - [Minimal WS adapter (sketch)](#minimal-ws-adapter-sketch)
    - [Optional: Streams wrapper so server logic can treat socket as streams](#optional-streams-wrapper-so-server-logic-can-treat-socket-as-streams)
  - [Deployment / Ops–Prüfungen bei Übergang zu WebTransport](#deployment-opsprfungen-bei-bergang-zu-webtransport)
  - [Konkrete Empfehlung für mdview (konkret und pragmatisch)](#konkrete-empfehlung-fr-mdview-konkret-und-pragmatisch)
  - [Beispiel: Wrap `ws` messages into a ReadableStream (node side sketch)](#beispiel-wrap-ws-messages-into-a-readablestream-node-side-sketch)
  - [Fazit — wann wechseln / wann nicht](#fazit-wann-wechseln-wann-nicht)
  - [Kurze To-Do-Liste (konkret umsetzbar)](#kurze-to-do-liste-konkret-umsetzbar)

---

## Kurzüberblick — technische Gemeinsamkeiten und Unterschiede

* **WebSocket (klassische WebSocket API / `ws` auf Node)**

  * Transport: TCP (HTTP Upgrade → WS).
  * Proven, breit unterstützt (Browser, Node, Proxy-Friendly).
  * Bidirektional, zuverlässige, ordered delivery (TCP).
  * Server-Ökosystem ausgereift (`ws`, `uWebSockets.js`, etc.).
* **WebSocketStream API (WHATWG Streams wrapper für WebSocket)**

  * Semantic: dieselbe WebSocket-Wire-Protocol (TCP) wie klassische WebSocket, aber API basiert auf ReadableStream/WritableStream (Streams API).
  * Vorteil: native backpressure, bessere Integration in Fetch/Streams-based pipelines (transform streams, async iteration).
  * Laufzeit/Kompatibilität: relativ neu; Browser unterstützen `WebSocketStream` zunehmend, Node-Seite ist uneinheitlich (Node 20+ bietet WHATWG Streams, aber native WebSocketStream server-side ist nicht automatisch vorhanden).
* **WebTransport (QUIC / HTTP/3-basiert)**

  * Transport: QUIC (UDP), Multiplexing, optionale unordentliche/Datagram-Übertragung, geringere Head-of-Line-Blocking, bessere Verbindungsmigration (z. B. Mobilfunk/Hand-Off).
  * Vorteile bei Latenz, Multiplexing, Resilience; moderne API mit Streams-Primitiven ähnlich Fetch Streams.
  * Nachteile: deutlich geringere Server-/Proxy-Unterstützung; benötigt HTTP/3 + QUIC auf Server, TLS; Firewalls/Proxies können blocken; komplexerer Ops/Deployment; Browser-Support wächst, aber Server-Ecosystem ist noch begrenzt.

---

## Auf „Zuverlässigkeit“ bezogen: was ist gemeint?

* Begriff ist mehrdeutig:

  * **Delivery reliability**: WebSocket (TCP) liefert ordered + reliable; WebTransport liefert ebenfalls zuverlässige Streams, zusätzlich flexible Datagramme (wenn gewünscht). Beide bieten also „Zuverlässigkeit“ im Sinne von Paketzustellung.
  * **Robustheit gegenüber Netzwechseln**: WebTransport (QUIC) ist in der Praxis robuster bei Netzwerkwechseln (z. B. WLAN→Mobil), kann Verbindungs-Migration/Recovery besser handhaben.
  * **Operational reliability / proxy compatibility**: klassische WebSockets sind in vielen Unternehmensnetzwerken und über viele Reverse-Proxies robust; WebTransport kann in Proxy-Umgebungen scheitern, wenn HTTP/3/QUIC nicht durchgelassen wird.

Wenn die Dokumentation behauptet, WebTransport sei „zuverlässiger“, ist meistens das Merkmal **besserer Resilience bei wechselnden/instabilen Netzwerken** (QUIC) und **günstigeres Multiplexing ohne HOL blocking** gemeint — nicht, dass WebSockets grundsätzlich unzuverlässig wären.

---

## Praktische Auswirkungen auf Ihr `MdviewServer` (Konsequenzen & Aufwand)

### 1) Kompatibilität & Infrastruktur

* **WebSocket (`ws`)**: läuft lokal auf `http.createServer` + `ws` ohne TLS, funktioniert auf `localhost`, einfach zu entwickeln und zu debuggen. Gut für editor → browser lokal preview.
* **WebSocketStream (clientseitig)**: Client kann `new WebSocketStream(url)` verwenden; serverseitig müsste man Streams-compatible API bereitstellen oder Wrapping schreiben. `ws` liefert callbacks/events — muss in Streams gewrappt werden. Aufwand moderat.
* **WebTransport**: benötigt HTTP/3 + QUIC, TLS — lokal entwickeln ist aufwändiger (zertifikate, spezielle Node-Server/HTTP3 libraries wie `@mrbbot/node-quic`/`quiche`/`ngtcp2` oder einen Caddy/NGINX proxy mit HTTP/3). Deployment komplexer. Nicht empfohlen, wenn Ziel erst mal „funktionen lokal und in vielen Umgebungen“.

### 2) API / Code-Änderungen

* **Minimaler Aufwand**: Beibehalten von `ws` (Ihr aktuelles `MdviewServer`) und optional server-side Stream-wrapper für bessere backpressure handling. Das heißt: interne Broadcast/POST-Handler bleiben identisch, nur die send/receive API kapseln.
* **Mittlerer Aufwand**: Implementieren einer abstrakten Transport-Adapter-Schnittstelle und zwei Implementierungen:

  * `adapter/ws_adapter.ts` → benutzt `ws` (beste Kompatibilität).
  * `adapter/webtransport_adapter.ts` → experimentell, nur wenn HTTP/3+QUIC vorhanden, feature-flag.
* **Höherer Aufwand**: Migration zu WebTransport als Standard — erfordert Infrastrukturänderungen, TLS, Tests gegen Proxies.

### 3) Performance & Semantik

* **Backpressure / Streams**: `WebSocketStream` verbesserte Entwicklererfahrung für Stream-based code (ReadableStream/WritableStream). Wenn in Server/Client Daten als Streams verarbeitet werden (z. B. große markdown → chunked rendering), ist Streams API vorteilhaft.
* **Message ordering & partial updates**: WebTransport ermöglicht bessere Multiplexing (mehrere Streams pro Verbindung). Wenn man parallel mehrere Dateien oder große Assets streamen will, kann das helfen. Für einfache „push Markdown as text“ reicht WebSocket.

---

## Empfehlungen, priorisiert (praktisch, risikobewusst)

1. **Beibehaltung von `ws` als Default** (lowest friction). Vorteile: stabil, sofort lauffähig lokal, tiefe Node-Ökosystem-Integration, funktioniert durch Proxies.
2. **Abstraktionslayer für Transport einführen**

   * Bietet die Möglichkeit, später WebSocketStream oder WebTransport zu ergänzen, ohne Business-Logik zu ändern.
   * Exemplarische API: `{ start(serverOrOptions), broadcast(data), send(client, data), on('connection', cb), stop() }`.
3. **WebSocketStream (clientseitig) optional nutzen**

   * Auf Clientseite (browser) kann `WebSocketStream` genutzt werden, solange serverseitig Streams-wrapping möglich ist. Falls Node-Server keine native WebSocketStream bietet, kann man serverseitig `ReadableStream`/`WritableStream`-Wrapper über `ws` implementieren (siehe Beispiel unten).
4. **WebTransport experimentell anbieten**

   * Implementieren als opt-in, feature-flagged adapter. Klare Dokumentation: requires HTTPS + HTTP/3; may fail behind proxies. Gut für spätere Produktionsoptimierungen (mobile resiliency).
5. **Instrumentation & Tests**

   * Metriken/health endpoints: connection counts, last successful push, latency; Test fallback behavior (if WebTransport fails, gracefully fallback to ws).

---

## Adapter-Pattern — vorgeschlagene Struktur (Beispiel)

* `src/server/transports/adapter.ts` (Interface)
* `src/server/transports/ws_adapter.ts` (implements adapter using `ws`)
* `src/server/transports/webtransport_adapter.ts` (experimental)
* `src/server/MdviewServer.ts` verwendet `const transport = require('./transports/ws_adapter')` und ruft `transport.start(server)` usw.

### Adapter interface (TypeScript sketch, English comments)

```ts
// src/server/transports/adapter.ts
export interface TransportAdapter {
  // start the transport, may accept an existing http.Server (for ws) or options (for webtransport)
  start(serverOrOptions?: any): Promise<void>;

  // stop / cleanup
  stop(): Promise<void>;

  // send to all connected clients
  broadcast(payload: string): void;

  // send to single client (opaque client handle)
  send(client: any, payload: string): void;

  // event: on new client connection
  onConnection(cb: (client: any) => void): void;

  // get current client count
  clientsCount(): number;
}
```

### Minimal WS adapter (sketch)

```ts
// src/server/transports/ws_adapter.ts
import { WebSocketServer } from 'ws';

export class WsAdapter {
  private wss?: WebSocketServer;
  private clients = new Set<any>();
  private connectionCb?: (c:any)=>void;

  async start(server: any) {
    this.wss = new WebSocketServer({ server, path: '/ws' });
    this.wss.on('connection', (ws) => {
      this.clients.add(ws);
      if (this.connectionCb) this.connectionCb(ws);
      ws.on('close', ()=> this.clients.delete(ws));
      ws.on('error', ()=> this.clients.delete(ws));
    });
  }

  async stop() {
    await new Promise<void>(resolve => this.wss?.close(()=>resolve()));
    this.clients.clear();
  }

  broadcast(payload: string) {
    for (const c of this.clients) {
      if (c.readyState === c.OPEN) c.send(payload);
    }
  }

  send(client: any, payload: string) {
    if (client && client.readyState === client.OPEN) client.send(payload);
  }

  onConnection(cb: (client:any) => void) {
    this.connectionCb = cb;
  }

  clientsCount() { return this.clients.size; }
}
```

### Optional: Streams wrapper so server logic can treat socket as streams

* Server can expose for each client `{ readable: ReadableStream, writable: WritableStream }` by wrapping `ws.on('message', ...)` into a `ReadableStream` and `ws.send` into `WritableStream`. Das verbessert interne Verarbeitung mit TransformStreams usw., ohne die underlying transport protocol zu ändern.

---

## Deployment / Ops–Prüfungen bei Übergang zu WebTransport

* **TLS/HTTPS + HTTP/3**: WebTransport zwingt zur Verwendung von secure contexts. Für lokale Entwicklung ist das unkomfortabel (self-signed certs oder special flags nötig). Für CI/CD/Production ist Provider/Reverse-Proxy nötig (Caddy/NGINX mit HTTP/3 support).
* **Proxy & corporate networks**: WebTransport kann blockiert werden; entsprechend Fallback zu WS implementieren.
* **Monitoring**: Track connection failures, fallback rates, and latency differences.

---

## Konkrete Empfehlung für mdview (konkret und pragmatisch)

1. **Implement adapter layer** in `MdviewServer` und keep `ws` adapter as default.
2. **Expose Stream wrappers** on server side (optional): damit Client-seitig `WebSocketStream` genutzt werden kann, ohne server komplett neu zu schreiben.
3. **Implement experimental WebTransport adapter** als Modul, markiert als experimental/opt-in, mit Feature flag in config. Dokumentation muss TLS/HTTP3 requirements deutlich machen.
4. **Health & fallback**: `GET /health` bereits vorhanden — erweitern um transport-capabilities metadata (e.g., supportsWebTransport boolean) damit client weiß, ob es versuchen soll, WebTransport zu verwenden.
5. **Testing**: Automatisierte tests für fallback (WebTransport fails → WS used) und for large messages/streaming behavior.

---

## Beispiel: Wrap `ws` messages into a ReadableStream (node side sketch)

```ts
// server-side helper to present a WebSocket as a WHATWG ReadableStream
import { WebSocket } from 'ws';

export function websocketToReadable(ws: WebSocket) {
  const rs = new ReadableStream<string>({
    start(controller) {
      const onMessage = (data: WebSocket.Data) => {
        // normalize data to string
        const msg = typeof data === 'string' ? data : data.toString();
        controller.enqueue(msg);
      };
      const onClose = () => controller.close();
      const onErr = (err: any) => controller.error(err);

      ws.on('message', onMessage);
      ws.on('close', onClose);
      ws.on('error', onErr);

      // cleanup
      return () => {
        ws.off('message', onMessage);
        ws.off('close', onClose);
        ws.off('error', onErr);
      };
    }
  });
  return rs;
}
```

Diese Wrapper erlauben, serverseitig Stream-based pipelines zu verwenden (transformations, backpressure simulation) — ohne WebTransport wirklich zu benötigen.

---

## Fazit — wann wechseln / wann nicht

* **Nicht wechseln**, wenn: Ziel ist schnelle lokale Entwicklung, maximale Kompatibilität, geringe Ops-Komplexität. `ws` + optional Streams-wrapper erfüllt die meisten Anforderungen.
* **Wechsel/evaluieren**, wenn: Ziel ist höhere mobile resilience, bessere multiplexing/latency für viele simultane streams, oder langfristige Produktivdeploys mit HTTP/3-Infrastruktur. Dann ist WebTransport eine attraktive Option — aber nur mit klarer Feature-Flag-Strategie, Fallbacks und Deployment-Plan.

---

## Kurze To-Do-Liste (konkret umsetzbar)

1. Introduce `transports/adapter` interface and `ws_adapter` implementation.
2. Replace direct `WebSocketServer` usage in `MdviewServer` with adapter injection.
3. Add server-side `ReadableStream`/`WritableStream` wrappers for `ws` clients.
4. Add `transport` field to `/health` response to indicate supported transports.
5. Implement `webtransport_adapter` as experimental, document TLS/HTTP3 requirements and fallback behavior.

---
