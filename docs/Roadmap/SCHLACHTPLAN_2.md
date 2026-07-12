# Schlachtplan 2 — Feedback-Runde (2026-07-13)

> Zweite Feedback-Runde nach P0–P2. Root-Causes untersucht. Priorisiert
> P0 (Bug) → P1 (wichtig) → P2 (Entscheidung/größer).

---

## P0 — Bugs

### 1. `focus = "nvim"` öffnet gar keinen Browser (Windows)  🔴
- **Symptom:** Mit `browser.focus = "nvim"` öffnet sich nichts.
- **Ursache (gefunden):** Das fokus-erhaltende PowerShell-Skript läuft
  einwandfrei, wenn man es direkt aufruft (getestet: Marker-Datei + `Start-Process`
  öffnen wie erwartet). Aber nvims `jobstart({"powershell", …, "-Command",
  script})` baut auf Windows die Kommandozeile mit **eigenem Quoting** — das
  komplexe Skript (Doppel-/Einfach-Quotes, Semikolons, `[DllImport…]`) wird dabei
  zerhackt, PowerShell bekommt kaputten Input → Fehler → nichts öffnet.
- **Fix:** Skript **nicht** als `-Command`-Argument übergeben, sondern
  - (a) in eine Temp-`.ps1` schreiben und `powershell -ExecutionPolicy Bypass
    -WindowStyle Hidden -File <tmp>` starten (versionsunabhängig), **oder**
  - (b) `-EncodedCommand <base64(UTF-16LE)>` (nur ein simples Token, kein
    Quoting; braucht `vim.base64`, ab nvim 0.10).
  Empfehlung: (a) Temp-Datei — robust auf allen nvim-Versionen.
- **Aufwand:** klein.

---

## P1 — wichtig

### 2. Scroll-Sync: Off-by-one + Zeilengenauigkeit + Viewport-Spiegelung
- **Symptom:** Cursor auf Zeile 100 → Browser setzt Zeile **101** ganz oben
  (statt 100). Immer top-aligned, egal wo der Cursor im nvim-Sichtfeld ist.
- **Ursache:** comrak `sourcepos` ist **pro Block** (`<p>`, `<h1>`, …), nicht pro
  Zeile. Innerhalb eines mehrzeiligen Absatzes mappen alle Cursor-Zeilen auf den
  **Blockanfang** → keine Zeilengenauigkeit, und die Blockwahl wirkt „daneben".
- **Fix (dreiteilig):**
  1. **Zeilengenau interpolieren:** den Block wählen, der die Zeile *enthält*
     (`startLine ≤ line ≤ endLine`, beide aus `data-sourcepos`), und innerhalb
     des Blocks `frac = (line-start)/(end-start)` auf die Blockhöhe rechnen →
     Ziel-Y = `block.offsetTop + frac*block.height`. Behebt den Off-by-one.
  2. **Konfigurierbarer Offset:** `scroll_sync_offset` (px oder Zeilen), damit man
     „N Zeilen weiter oben" einstellen kann.
  3. **Viewport-Spiegelung (Extra-Feature):** nvim sendet zusätzlich die
     Cursor-Position im Fenster (`winline()/win_height` → Bruchteil). Neuer Modus
     `scroll_sync_mode = "top" | "cursor"`: bei `"cursor"` wird die Zielzeile an
     **derselben** relativen Höhe im Browser platziert wie der Cursor im nvim-
     Sichtfeld (Mitte bleibt Mitte). Payload: `line/total/winfrac`.
- **Aufwand:** mittel (Client-Rechnung + kleine Payload-Erweiterung + Config).

### 3. Transport-Sichtbarkeit (WebTransport vs. WebSocket)
- **Wunsch:** Zu Beginn ausgeben, wie man prüft welcher Transport läuft; Aussage
  in `:MDViewDiagnose` (und checkhealth nur wenn sinnvoll).
- **Fakten:** Es gibt **kein** HTTP/3-Backend → `webtransport=true` fällt immer
  auf WebSocket zurück. Der Client loggt seine Wahl bereits nach `/clientlog`
  → sichtbar in `:MDViewShowWebLogs` (`[client] websocket connected` bzw.
  `[client] transport: WebTransport failed, falling back to WebSocket`).
- **Fix:**
  - `:MDViewDiagnose`: eine Sektion „Active transport" — der Client meldet seinen
    tatsächlichen Transport (kleines zusätzliches `/clientlog`-Feld oder aus dem
    Log-Ring gefiltert). Ehrliche Aussage: aktuell immer WebSocket.
  - checkhealth: **nicht** nötig (Session-/Laufzeit-Info gehört in Diagnose, nicht
    in den statischen Health-Check) — nur ein Hinweis „webtransport=on → fällt
    auf WS zurück (kein Backend)".
- **Aufwand:** klein.

### 4. Shiki highlightet nichts (hljs top)
- **Symptom:** `highlighter="shiki"` färbt gar nichts; `hljs` funktioniert super.
- **Wahrscheinliche Ursache:** Shiki lädt Grammatiken/Oniguruma-WASM als
  On-Demand-Chunks; scheitert das Laden über den Relay-Static-Server, wirft
  `codeToHtml` und der per-Block-`try/catch` lässt den Block **still** unverändert
  → „nichts". Muss im echten Browser (Network-Tab) verifiziert werden.
- **Fix/Entscheidung:** hljs **bleibt Default** (dein Wunsch). Shiki:
  - kurz debuggen (ist der Grammatik-Chunk-404? WASM-MIME? base path?), **oder**
  - als `experimental`/„best-effort" markieren mit Doku-Hinweis. Kein Blocker,
    da hljs die Kernanforderung erfüllt.
- **Aufwand:** unklar (Browser-Debugging) → time-boxen, sonst demoten.

---

## P2 — Entscheidungen / größer

### 5. color_my_ascii statt hljs/shiki? — NEIN (mit Begründung), Alternative Treesitter
- **Befund:** `require("color_my_ascii").fences` ist eine **Fence-Erkennungs**-API
  (Blockgrenzen, Sprache, Cursor-Block) — **kein** Token-Coloring-Export. Die
  Färbung selbst macht das Plugin intern über Extmarks/Highlight-Gruppen
  (Keyword-Listen pro Sprache), also **nur im nvim-Buffer**, nicht als HTML.
- **Konsequenz:** Damit lässt sich hljs/shiki **nicht** ersetzen — es gibt keine
  „gib mir (Range → Farbe) für diesen Codeblock"-Schnittstelle, und die
  Keyword-Heuristik wäre ohnehin gröber als hljs.
- **Echte Alternative (Zukunft, groß):** nvim-seitiges **Treesitter**-Highlighting
  spiegeln — pro Codeblock die Treesitter-Captures + aufgelöste Highlight-Farben
  als Spans an den Browser senden. Würde hljs/shiki-Dependency ersetzen und exakt
  „wie in nvim" aussehen. Aufwändig (Injection-Parsing, hl-group→hex-Auflösung,
  Transport). Als eigenes Feature notieren, nicht jetzt.

### 6. Default-Flags entscheiden (nach deinem Test-Feedback)
- `click_navigate` → **funktioniert** → als **Default an** vorschlagen.
- `line_diff` → funktioniert → Default abwägen: **Pro** Bandbreite/große Dateien;
  **Contra** minimaler Loopback-Nutzen + Komplexität/Desync-Fläche. Empfehlung:
  **aus** lassen (Loopback → kaum Nutzen), opt-in behalten.
- `reverse_scroll` → „fast ideal" → Default abwägen (Polling-Lag); eher opt-in.
- `webtransport` → **kein** Default (kein Backend, immer Fallback → sinnlos an).
- **Aufwand:** trivial (nur Default-Werte + Doku), sobald entschieden.

---

## Reihenfolge
1. **P0-1** focus-Bug (Temp-`.ps1`).
2. **P1-2** Scroll-Redesign (Off-by-one + Interpolation + Offset + Mirror-Modus).
3. **P1-3** Transport-Sichtbarkeit in `:MDViewDiagnose` + How-to.
4. **P1-4** Shiki time-boxed debuggen, sonst demoten.
5. **P2-6** Default-Flags setzen (click_navigate an; Rest opt-in).
6. **P2-5** Treesitter-Mirror nur dokumentieren (Zukunft).
