// src/server/static.ts
// Serve static client files from dist/client when present.
// Returns true if a file was served, false otherwise.

import path from "node:path";
import fs from "node:fs";
import type http from "node:http";

/**
 * tryServeStatic
 *
 * Serve a file under <project-root>/dist/client if it exists and is a file.
 * Simple path-traversal guard included.
 *
 * @param req IncomingMessage
 * @param res ServerResponse
 * @returns boolean true when file served, false otherwise
 */
export function tryServeStatic(
  req: http.IncomingMessage,
  res: http.ServerResponse
): boolean {
  const webRoot = path.resolve(process.cwd(), "dist", "client");
  let reqPath = req.url || "/";
  if (reqPath.includes("..")) return false; // path traversal guard

  if (reqPath === "/") reqPath = "/index.html";
  const filePath = path.join(webRoot, reqPath);
  if (!filePath.startsWith(webRoot)) return false;

  try {
    if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
      const ext = path.extname(filePath).toLowerCase();
      const contentType =
        ext === ".html"
          ? "text/html"
          : ext === ".js"
          ? "application/javascript"
          : ext === ".css"
          ? "text/css"
          : "application/octet-stream";
      const data = fs.readFileSync(filePath);
      res.writeHead(200, { "Content-Type": contentType });
      res.end(data);
      return true;
    }
  } catch (err) {
    // swallow errors and return false so caller falls back to other routes
    console.error("[mdview-server] static serve error", err);
    return false;
  }
  return false;
}
