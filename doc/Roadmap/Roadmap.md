# Roadmap

## Allgemein

1. `TODO-Comments` lösen

---

## Client

---

## Server

- In server wss-Broadcast: vor dem client.send(payload) try/catch pro-client, damit ein fehlerhafter Client nicht ganze Broadcast-Loop abbricht.
- Client: createTransport so erweitern, dass import.meta.env.VITE_WS_URL akzeptiert wird — einfach per .env konfigurierbar.

---
