// src/server/mdviewServer.ts
// This file defines a singleton WebSocket + HTTP server for mdview.nvim.

import http from "node:http";
import WebSocket, { WebSocketServer } from "ws";
import getPort from "get-port";
import { debounce } from "./mdviewServer.debounce.js";

/**
 * MdviewServer
 *
 * Singleton WebSocket + HTTP Server that:
 * - starts an HTTP server to receive POST /render requests
 * - starts a WebSocketServer for live updates
 * - debounces broadcasts to avoid flooding (default 3000ms)
 * - supports dynamic port selection to avoid conflicts
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

    // debounce broadcasting to reduce update flood
    this.broadcastDebounced = debounce((data: string) => {
      for (const ws of this.clients) {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(data);
        }
      }
    }, 3000);
  }

  public static async getInstance(preferredPort = 43219): Promise<MdviewServer> {
    if (!MdviewServer.instance) {
      const port = await getPort({ port: preferredPort });
      MdviewServer.instance = new MdviewServer(port);
      await MdviewServer.instance.start();
    }
    return MdviewServer.instance;
  }

  public static async reset(): Promise<void> {
    if (MdviewServer.instance) {
      await MdviewServer.instance.stop();
      MdviewServer.instance = null;
    }
  }

  public async start(): Promise<void> {
    if (this.isRunning) return;

    // create a plain HTTP server; request listener may be attached elsewhere (index.ts)
    this.server = http.createServer();

    this.wss = new WebSocketServer({ server: this.server, path: "/ws" });
    this.wss.on("connection", (ws: WebSocket) => {
      this.clients.add(ws);
      ws.on("close", () => this.clients.delete(ws));
      ws.on("error", () => this.clients.delete(ws));
    });

    await new Promise<void>((resolve) => {
      this.server?.listen(this.port, () => {
        console.log(`[mdview-server] Running on http://localhost:${this.port}`);
        resolve();
      });
    });

    this.isRunning = true;
  }

  public async stop(): Promise<void> {
    if (!this.isRunning) return;

    await new Promise<void>((resolve) => {
      this.wss?.close(() => {
        this.server?.close(() => {
          this.clients.clear();
          this.isRunning = false;
          resolve();
        });
      });
    });
  }

  public broadcast(data: string): void {
    this.broadcastDebounced(data);
  }

  public getPort(): number {
    return this.port;
  }
}
