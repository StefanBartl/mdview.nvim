/**  src/server/MdviewServer
 *
 * @class MdviewServer
 * @description
 * Singleton-/Factory-basierter WebSocket- und HTTP-Server für mdview.nvim.
 *
 * Verantwortlichkeiten:
 * - Startet HTTP-Server für POST /render Requests
 * - Startet WebSocket-Server für Live-Updates
 * - Debounced Broadcasting nach Dateiänderungen (z. B. 3000ms)
 * - Dynamische Portwahl, um Konflikte zu vermeiden (cross-platform)
 * - Kontrollierter Lifecycle: start, stop, reset
 *
 * Vorteile:
 * - Keine globalen Prozesse mehr manuell killen
 * - Debounced Updates verhindern Flooding bei vielen keystrokes
 * - Singleton garantiert nur eine Server-Instanz
 */

import http from 'node:http';
import WebSocket, { WebSocketServer } from 'ws';
import getPort from 'get-port';
import { debounce } from './mdviewServer.debounce.js';

/**
 * Singleton WebSocket + HTTP Server
 */
export class MdviewServer {
  private static instance: MdviewServer | null = null;
  public server?: http.Server;
  private wss?: WebSocketServer;
  private clients: Set<WebSocket> = new Set();
  private port: number;
  private isRunning = false;
  private broadcastDebounced: (data: string) => void;

  private constructor(port: number) {
    this.port = port;

    this.broadcastDebounced = debounce((data: string) => {
      for (const ws of this.clients) {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(data);
        }
      }
    }, 3000);
  }

  public static async getInstance(preferredPort = 43219) {
    if (!MdviewServer.instance) {
      const port = await getPort({ port: preferredPort });
      MdviewServer.instance = new MdviewServer(port);
      await MdviewServer.instance.start();
    }
    return MdviewServer.instance;
  }

  public static async reset() {
    if (MdviewServer.instance) {
      await MdviewServer.instance.stop();
      MdviewServer.instance = null;
    }
  }

  public async start() {
    if (this.isRunning) return;

    this.server = http.createServer(); // Listener in index.ts hinzugefügt

    this.wss = new WebSocketServer({ server: this.server, path: '/ws' });
    this.wss.on('connection', ws => {
      this.clients.add(ws);
      ws.on('close', () => this.clients.delete(ws));
      ws.on('error', () => this.clients.delete(ws));
    });

    await new Promise<void>(resolve => {
      this.server?.listen(this.port, () => {
        console.log(`[mdview-server] Running on http://localhost:${this.port}`);
        resolve();
      });
    });

    this.isRunning = true;
  }

  public async stop() {
    if (!this.isRunning) return;

    await new Promise<void>(resolve => {
      this.wss?.close(() => {
        this.server?.close(() => {
          this.clients.clear();
          this.isRunning = false;
          resolve();
        });
      });
    });
  }

  public broadcast(data: string) {
    this.broadcastDebounced(data);
  }

  public getPort() {
    return this.port;
  }
}
