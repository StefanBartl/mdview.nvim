// ADD: Annotations

/* Minimal server using express + ws with correct TypeScript typings.
   - Provides HTTP static folder for client
   - Provides WebSocket server for live updates
   - Import WebSocket types from 'ws' to avoid DOM WebSocket conflicts.
   - Use http.createServer to attach WebSocketServer.

- HTTP + WebSocket server with /render endpoint and WS broadcast of render_update events.
*/

import express from "express";
import http from "http";
import path from "path";
import { WebSocketServer, type RawData } from "ws";
import { renderWithCache } from "./render.js";

const app = express();
const PORT = Number(process.env.MDVIEW_PORT) || 43219;

// parse raw body for markdown POSTs
app.use(express.text({ type: ["text/*", "application/*+md", "application/octet-stream"], limit: "10mb" }));

// Serve static client in production. In dev Vite serves client on 43220.
const clientDist = path.join(process.cwd(), "dist", "client");
app.use("/", express.static(clientDist));

// HTTP health endpoint
app.get("/health", (_req, res) => {
  res.status(200).send("ok");
});

/**
 * POST /render
 * Accepts raw markdown body and optional query `key` (identifier).
 * If key not provided, server uses a timestamp-derived id (not cached).
 *
 * Response: JSON { html, cached }
 *
 * Also broadcasts a `render_update` message over active WebSocket clients.
 */
app.post("/render", (req, res) => {
  try {
    const markdown = typeof req.body === "string" ? req.body : String(req.body || "");
    const key = (req.query.key as string) || `inline-${Date.now()}`;
    const { html, cached } = renderWithCache(key, markdown);

    // Broadcast to all connected WS clients
    try {
      const payload = JSON.stringify({ type: "render_update", payload: html, key, cached });
      wss.clients.forEach((client) => {
        if (client.readyState === client.OPEN) {
          client.send(payload);
        }
      });
    } catch (bcastErr) {
      // don't fail the HTTP response if broadcast fails
      console.warn("broadcast failed", bcastErr);
    }

    res.setHeader("Content-Type", "application/json");
    res.status(200).send(JSON.stringify({ html, cached }));
  } catch (err) {
    res.status(500).send(String(err));
  }
});

// create HTTP server + attach WS server
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: "/ws" });

wss.on("connection", (ws) => {
  console.log("ws: client connected");

  // greet client
  try {
    ws.send(JSON.stringify({ type: "hello", payload: "mdview" }));
  } catch {}

  ws.on("message", (msg: RawData) => {
    // convert RawData -> string robustly
    let text = "";
    if (typeof msg === "string") text = msg;
    else if (Array.isArray(msg)) text = Buffer.concat(msg as Buffer[]).toString("utf8");
    else if (msg instanceof ArrayBuffer) text = Buffer.from(new Uint8Array(msg)).toString("utf8");
    else if (ArrayBuffer.isView(msg)) text = Buffer.from(msg as Uint8Array).toString("utf8");
    else text = Buffer.from(msg as Buffer).toString("utf8");

    // handle control messages from client (optional)
    try {
      const data = JSON.parse(text);
      if (data?.type === "ping") {
        ws.send(JSON.stringify({ type: "pong" }));
      }
      // extend with more control messages as needed
    } catch {
      // ignore non-json messages
    }
  });

  ws.on("close", (code, reason) => {
    console.log("ws: client disconnected", code, reason?.toString());
  });

  ws.on("error", (err) => {
    console.warn("ws: error", err);
  });
});

// start server
server.listen(PORT, () => {
  console.log(`mdview server running at http://localhost:${PORT}`);
  console.log(`ws endpoint: ws://localhost:${PORT}/ws`);
});
