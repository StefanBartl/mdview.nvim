// tests/test-ws.js
// save as test-ws.js and run `node test-ws.js`
// Simple websocket client test for the mdview backend.
// Usage: node tests/test-ws.js ws://localhost:43219/ws

const WebSocket = require("ws");

const url = process.argv[2] || "ws://localhost:43219/ws";
const ws = new WebSocket(url);

ws.on("open", () => {
  console.log("OPEN", url);
  ws.send(JSON.stringify({ type: "hello" }));
});

ws.on("message", (m) => {
  console.log("MSG", m.toString());
});

ws.on("close", (code, reason) => {
  console.log("CLOSE", code, reason && reason.toString());
});

ws.on("error", (e) => {
  console.error("ERR", e && e.message ? e.message : e);
});

