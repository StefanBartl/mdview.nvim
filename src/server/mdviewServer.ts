/// <reference types="node" />
import http from 'node:http';
import WebSocket, { WebSocketServer } from 'ws';
import { debounce } from 'lodash';
import getPort from 'get-port'; // Cross-platform port selection

/**
 * @class MdviewServer
 * @description
 * Singleton-/Factory-basierter WebSocket- und HTTP-Server für mdview.nvim.
 *
 * Funktionen:
 * - Startet einen HTTP-Server für POST /render Requests.
 * - Startet einen WebSocket-Server für live Updates an Clients.
 * - Debounced Broadcasting nach Dateiänderungen (z. B. 3000ms).
 * - Dynamische Portwahl, um Konflikte zu vermeiden (Cross-Platform).
 * - Kontrollierte Lifecycle-Verwaltung: start, stop, reset.
 */
export class MdviewServer {
  /** Singleton-Instanz */
  private static instance: MdviewServer | null = null;

  /** Interner HTTP-Server */
  private server?: http.Server;

  /** WebSocket-Server */
  private wss?: WebSocketServer;

  /** Aktive WebSocket-Clients */
  private clients: Set<WebSocket> = new Set();

  /** Port, auf dem der Server läuft */
  private port: number;

  /** Flag, ob der Server aktuell läuft */
  private isRunning = false;

  /** Debounced Broadcast-Funktion, um Flooding zu vermeiden */
  private broadcastDebounced: (data: string) => void;

  /**
   * @private
   * Privater Konstruktor, um Singleton über Factory zu erzwingen
   * @param port Gewünschter Port (wird geprüft / ggf. angepasst)
   */
  private constructor(port: number) {
    this.port = port;

    // Debounced Broadcasting (3000ms Delay)
    this.broadcastDebounced = debounce((data: string) => {
      for (const ws of this.clients) {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(data);
        }
      }
    }, 3000);
  }

  /**
   * @static
   * Factory-Methode: Gibt die Singleton-Instanz zurück oder erstellt sie
   * @param preferredPort Gewünschter Port (Default: 43219)
   * @returns Promise<MdviewServer> Singleton-Instanz
   */
  public static async getInstance(preferredPort = 43219) {
    if (!MdviewServer.instance) {
      // Dynamischer Port, wenn der gewünschte belegt ist
      const port = await getPort({ port: preferredPort });
      MdviewServer.instance = new MdviewServer(port);
      await MdviewServer.instance.start();
    }
    return MdviewServer.instance;
  }

  /**
   * @static
   * Setzt die Singleton-Instanz zurück (nützlich für Tests oder Hot-Reload)
   */
  public static async reset() {
    if (MdviewServer.instance) {
      await MdviewServer.instance.stop();
      MdviewServer.instance = null;
    }
  }

  /**
   * @public
   * Startet HTTP- und WebSocket-Server
   */
  public async start() {
    if (this.isRunning) return;

    this.server = http.createServer((req, res) => {
      if (req.method === 'POST' && req.url?.startsWith('/render')) {
        let body = '';
        req.on('data', chunk => (body += chunk));
        req.on('end', () => {
          // Broadcast an Clients (debounced)
          this.broadcastDebounced(body);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ status: 'ok' }));
        });
      } else {
        res.writeHead(404);
        res.end();
      }
    });

    // WebSocket-Server initialisieren
    this.wss = new WebSocketServer({ server: this.server });
    this.wss.on('connection', ws => {
      this.clients.add(ws);
      ws.on('close', () => this.clients.delete(ws));
    });

    // Server starten
    await new Promise<void>(resolve => {
      this.server?.listen(this.port, () => {
        console.log(`[mdview-server] Running on http://localhost:${this.port}`);
        resolve();
      });
    });

    this.isRunning = true;
  }

  /**
   * @public
   * Stoppt HTTP- und WebSocket-Server und löscht alle Clients
   */
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

  /**
   * @public
   * Broadcast an alle verbundenen Clients (debounced)
   * @param data JSON oder Markdown als String
   */
  public broadcast(data: string) {
    this.broadcastDebounced(data);
  }

  /**
   * @public
   * Liefert den Port, auf dem der Server läuft
   * @returns number
   */
  public getPort() {
    return this.port;
  }
}
