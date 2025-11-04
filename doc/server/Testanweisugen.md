# Server Testanweisungen

# 1) Dev server starten
npm run dev:server

# 2) Lokalen Render-Test: sende Markdown per HTTP POST an /render
curl -v -X POST "http://localhost:43219/render?key=test1" -H "Content-Type: text/markdown" --data-binary "@tests/test.md"

# erwartete Response: JSON { html: "...", cached: false } (bei erstem Request)
# und das Browser-Client (wenn verbunden) erhält per WebSocket eine Nachricht:
# { type: "render_update", payload: "<html>...</html>", key: "test1", cached: false }

# 3) Wiederhole Request mit identischem Markdown -> cached: true
curl -X POST "http://localhost:43219/render?key=test1" -H "Content-Type: text/markdown" --data-binary "@tests/test.md"
