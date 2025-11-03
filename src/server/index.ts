/* Minimal server using express + ws with correct TypeScript typings.
   - Provides HTTP static folder for client
   - Provides WebSocket server for live updates
   - Import WebSocket types from 'ws' to avoid DOM WebSocket conflicts.
   - Use http.createServer to attach WebSocketServer.
*/


import express from "express";
import http from "http";
import path from "path";
import WebSocket, { WebSocketServer, type RawData } from "ws";

/**
 * Convert RawData (from 'ws' package) to a UTF-8 string.
 * Handles: string, Buffer, Buffer[], ArrayBuffer, Uint8Array.
 *
 * @param data RawData incoming from ws 'message' event
 * @returns string decoded from UTF-8
 */
function rawDataToString(data: RawData): string {
  // If ws already gave a string (rare), return immediately
  if (typeof data === "string") {
    return data;
  }

  // If data is an array of Buffers, concat them first
  if (Array.isArray(data)) {
    // data is Buffer[] according to ws types when chunked
    return Buffer.concat(data as Buffer[]).toString("utf8");
  }

  // If data is an ArrayBuffer (browser-style), wrap with Uint8Array then Buffer
  if (data instanceof ArrayBuffer) {
    return Buffer.from(new Uint8Array(data)).toString("utf8");
  }

  // If data is a TypedArray (e.g. Uint8Array), create Buffer from it
  if (ArrayBuffer.isView(data)) {
    // Cast to Uint8Array view and then Buffer
    return Buffer.from((data as Uint8Array)).toString("utf8");
  }

  // Fallback: assume Buffer-like
  return Buffer.from(data as Buffer).toString("utf8");
}

const app = express();
const PORT = Number(process.env.MDVIEW_PORT) || 43219;

// Serve static client build (in dev, vite serves client; in production dist)
const clientDist = path.join(process.cwd(), "dist", "client");
app.use("/", express.static(clientDist));

const server = http.createServer(app);

// Create WebSocketServer attached to the same HTTP server
const wss = new WebSocketServer({ server });

wss.on("connection", (ws: WebSocket) => {
  ws.on("message", (msg: RawData) => {
    const text = rawDataToString(msg);
    // Now 'text' is a proper string; handle JSON or plain text
    try {
      const payload = JSON.parse(text);
      console.log("parsed json", payload);
    } catch {
      console.log("received text:", text);
    }
  });
});
server.listen(PORT, () => {
  console.log(`mdview server running at http://localhost:${PORT}`);
});
