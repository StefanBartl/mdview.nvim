// src/server/index.ts

import http from "node:http";
import { renderWithCache } from "./render.js";
import { MdviewServer } from "./mdviewServer.js";

const PORT = Number(process.env.MDVIEW_PORT) || 43219;

/**
 * readRequestBody
 *
 * Safely accumulate the request body into a UTF-8 string. Uses Buffer for binary-safety
 * and provides a typed Promise-based API to avoid callback-style listeners scattered in logic.
 */
function readRequestBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const buffers: Buffer[] = [];
    req.on("data", (chunk: Buffer | string) => {
      if (Buffer.isBuffer(chunk)) buffers.push(chunk);
      else buffers.push(Buffer.from(String(chunk), "utf8"));
    });
    req.on("end", () => {
      try {
        const body = Buffer.concat(buffers).toString("utf8");
        resolve(body);
      } catch (err) {
        reject(err);
      }
    });
    req.on("error", (err) => {
      reject(err);
    });
  });
}

(async () => {
  try {
    // Start singleton server
    const server = await MdviewServer.getInstance(PORT);

    console.log(`[mdview-server] Running on http://localhost:${server.getPort()}`);
    console.log(`ws endpoint: ws://localhost:${server.getPort()}/ws`);

    // Use the strongly-typed `server` property provided by MdviewServer rather than `any`.
    const httpServer = server.server;
    if (!httpServer) {
      throw new Error("MdviewServer did not provide an http.Server instance");
    }

    // Attach a request listener. Use an async inner function to allow await usage.
    httpServer.on("request", (req: http.IncomingMessage, res: http.ServerResponse) => {
      (async () => {
        try {
          if (req.method === "POST" && req.url?.startsWith("/render")) {
            const body = await readRequestBody(req);
            const urlObj = new URL(req.url!, `http://localhost`);
            const rawKey = String(urlObj.searchParams.get("key") || `inline-${Date.now()}`);
            const key = rawKey.replace(/\\/g, "/"); // Windows-safe
            const markdown = String(body || "");

            console.log(`[mdview-server] POST /render key=${key} markdown_len=${markdown.length}`);

            // Render with cache; renderWithCache must return { html, cached }
            const { html, cached } = renderWithCache(key, markdown);

            // Broadcast only on cache miss
            if (!cached) {
              const payload = JSON.stringify({ type: "render_update", payload: html, key, cached });
              // `server` is the MdviewServer instance and exposes broadcast(data: string).
              server.broadcast(payload);
            }

            // Respond to client
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ html, cached }));
            return;
          }

          if (req.method === "GET" && req.url === "/health") {
            res.writeHead(200, { "Content-Type": "text/plain" });
            res.end("ok");
            return;
          }

          // Default 404
          res.writeHead(404, { "Content-Type": "text/plain" });
          res.end("Not Found");
        } catch (err) {
          console.error("[mdview-server] HTTP request error", err);
          if (!res.headersSent) {
            res.writeHead(500, { "Content-Type": "text/plain" });
            res.end(String(err));
          }
        }
      })();
    });
  } catch (err) {
    console.error("[mdview-server] failed to start", err);
    process.exitCode = 1;
  }
})();
