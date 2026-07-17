# Konzept: Link-Handling + Cursor-Overlay im Browser

> Zwei Feature-Konzepte (noch keine Umsetzung). Jeweils: Problem → Ist-Zustand →
> Konzept mit Stufen/Optionen → Transport/Umsetzungsskizze → Empfehlung.

---

## Feature 1 — Link-Verhalten im Preview-Tab

### Problem
Klickt man im Preview auf einen **externen** Link (`http…`), navigiert der Browser
im **selben Tab** weg → der mdview-Tab ist „weg" und die WebSocket-Verbindung
tot. Frage außerdem: was passiert grundsätzlich, wenn man vom „Markdown-Dokument"
im Tab weg-navigiert — schließt mdview, bleibt es „im Cache", …?

### Ist-Zustand
- **Relative Links** (`other.md`, `./x.md`) → `click_navigate` (jetzt default an)
  fängt den Klick ab, öffnet die Datei in nvim, die Preview folgt. **Kein**
  Weg-Navigieren. ✔
- **Externe Links / `mailto:` / absolute `/…` / Protokoll-relativ `//…`** →
  `navTargetFromHref` gibt `null` zurück → **nicht** abgefangen → Browser folgt im
  selben Tab. �’ (Ammonia setzt zwar `rel="noopener noreferrer"`, aber **kein**
  `target`.)
- **In-Page-Anker** (`#heading`) → Standard-Browser-Scroll im Tab. ✔ (kein Problem)
- **Relay-Lebenszyklus:** Der Relay hängt an nvims `:MDViewStart`/`:MDViewStop`,
  **nicht** am Tab. Navigiert der Tab weg oder wird geschlossen, läuft der Relay
  weiter; der Content ist „gehalten" (LastPayload) solange die Session lebt.

### Konzept
1. **Externe Links → neuer Tab** (Kern-Fix):
   Nach jedem Render (wie beim Highlighting) alle „nicht-navigierbaren" `<a>`
   (die `navTargetFromHref` als extern einstuft) mit
   `target="_blank" rel="noopener noreferrer"` versehen. Ergebnis: externer Link
   öffnet in **neuem** Tab, der mdview-Tab bleibt erhalten. Alternativ Klick
   abfangen + `window.open(href, '_blank', 'noopener')` — aber das `target`-Attribut
   ist einfacher und robuster (funktioniert auch bei Middle-Click/Strg-Klick).
2. **In-Page-Anker** bleiben Standardverhalten (Scroll im Tab).
3. **Relative md-Links** bleiben `click_navigate`.
4. **„Weg-Navigation"-Semantik klarstellen (Doku + kleines Verhalten):**
   mdview **schließt nicht** bei Tab-Navigation. Empfohlenes, „übliches" Verhalten:
   - Relay bleibt (an nvim gebunden) → Session lebt weiter.
   - Landet man doch mal auf einer fremden Seite (z. B. manuell), holt man die
     Preview mit **`:MDViewOpen`** zurück (öffnet frischen Tab mit aktuellem
     Content aus LastPayload).
   - Optional-Ausbau: Client erkennt WS-`close` und zeigt ein dezentes Overlay
     „Verbindung getrennt — in nvim `:MDViewOpen`" statt einer stummen, toten
     Seite. Kein Auto-Reconnect nötig (der neue Tab via `:MDViewOpen` ist sauberer).

### Optionen / Entscheidungen
- **Default:** externe Links **immer** neuer Tab (üblich für Preview-Tools).
- **Config:** `browser.external_links = "new_tab" | "same_tab"` (default `new_tab`),
  an den Client als `&extlinks=` übergeben.
- **Sicherheit:** `rel="noopener noreferrer"` ist bereits gesetzt (kein
  `window.opener`-Leak) — beibehalten.

### Umsetzungsskizze
- Client `render/externalLinks.ts`: `markExternalLinks(root)` läuft nach jedem
  Render, setzt `target`/`rel` auf externe `<a>`. Wiederverwendet
  `navTargetFromHref`-Logik (extern = die Fälle, die `null` liefern, außer `#…`).
- Aufruf in `main.ts` neben `highlight(...)` in `renderMarkdown`.
- jsdom-Test: externer Link bekommt `target="_blank"`, relativer/Anker nicht.
- **Aufwand:** klein.

---

## Feature 2 — Cursor-Position im Browser anzeigen (Overlay)

### Wunsch
Im Browser-Tab **sehen, wo der nvim-Cursor gerade steht** — ein Cursor-Zeichen
overlayed an genau der Stelle, an der man in nvim (Zeile/Spalte) ist.

### Kern-Herausforderung
Quelle → gerendertes HTML ist **nicht** 1:1: Markdown-Syntax verschwindet beim
Rendern (`**bold**` → `<strong>bold</strong>`, `# ` weg, `[txt](url)` → `txt`).
Damit stimmt die **Quell-Spalte** nicht mit der **Render-Spalte** überein. Wir
haben `data-sourcepos="startLine:startCol-endLine:endCol"` — aber nur auf
**Block**-Ebene, nicht pro Zeichen.

### Konzept — gestuft nach Genauigkeit/Aufwand

**Stufe A — Zeilen-Marker (robust, empfohlen als Erstes):**
- nvim sendet die Cursor-Zeile (kommt schon via scroll_sync). Client hebt den
  **aktuellen Block/die aktuelle Zeile** hervor:
  - Variante A1: dezenter Zeilen-Hintergrund oder linke Randleiste am
    Ziel-Element (wie „current line" in Editoren).
  - Variante A2: ein Caret-Strich am **Anfang** der Zeile im Ziel-Block (bei
    mehrzeiligen Blöcken via Interpolation wie beim Scroll positioniert).
- Kein Spalten-Problem, sofort nützlich („du bist hier").

**Stufe B — zeichen-approximativer Caret (Ausbau, opt-in):**
- nvim sendet zusätzlich die **Spalte**. Client:
  1. Ziel-Block via sourcepos (wie Stufe A).
  2. Innerhalb des Blocks mit der **DOM `Range`-API** einen Punkt setzen: über
     die Text-Knoten laufen, bis ~`col` gerenderte Zeichen erreicht sind
     (best-effort — entfernte Syntax wird ignoriert), `range.getBoundingClientRect()`
     liefert (x,y) → dort ein absolut positioniertes, blinkendes Caret-Overlay
     (`<span class="mdview-caret">`) einfügen.
- Ungenau bei viel Inline-Markup in der Zeile, aber für Prosa meist brauchbar.
  Klar als „approximativ" kommunizieren.

**Stufe C — exaktes Source-Mapping (groß, später):**
- Beim Rendern eine echte Source-Map mitliefern (WASM gibt zu jedem Inline-Node
  seine Quell-Range), Client mappt (Zeile,Spalte) exakt auf DOM-Position.
  Aufwändig (comrak-Inline-sourcepos ist begrenzt; ggf. eigener Renderer-Hook).
  Für ein Preview vermutlich Overkill — nur bei echtem Bedarf.

### Transport
- `scroll_sync` (bzw. ein Cursor-Kanal) erweitern: heutiges
  `line/total/viewfrac` → `line/total/viewfrac/col`. Update bei jedem
  `CursorMoved`/`CursorMovedI` (throttled, wie jetzt). Ephemer (kein LastPayload).
- **Wechselwirkung:** Der Cursor-Marker ist **unabhängig** vom Scroll-Modus.
  Bei `scroll_sync_mode="cursor"` (Mirror) liegt der Marker automatisch dort, wo
  auch nvim ihn zeigt — passt gut zusammen.

### Darstellung
- Overlay-Element im `#mdview-root`-Container, `position: absolute`, blinkende
  CSS-Animation. Farbe aus Theme (`--md-fg` oder neue `--cursor-color`).
- Bei Resize / erneutem Render neu positionieren (Marker nach jedem Render +
  jedem Cursor-Ping aktualisieren).
- Config: `browser.cursor_marker = "off" | "line" | "caret"` (default `off` oder
  `line` — zu entscheiden), an den Client als `&cursor=` übergeben.

### Empfehlung
1. **Stufe A (Zeilen-Marker)** zuerst — robust, kleiner Aufwand, kein Spalten-Problem.
2. **Stufe B (approx. Caret)** als opt-in Ausbau.
3. Stufe C zurückstellen.

---

## Priorisierung / Reihenfolge (Vorschlag)
1. **F1** externe Links → neuer Tab (klein, behebt echten „Tab weg"-Bug).
2. **F1** Disconnect-Overlay + Doku „Relay bleibt, `:MDViewOpen` holt zurück".
3. **F2 Stufe A** Zeilen-Marker.
4. **F2 Stufe B** approx. Caret (opt-in).
5. F2 Stufe C nur bei Bedarf.

## Offene Entscheidungen für dich
- F1: Config `browser.external_links` überhaupt anbieten, oder externe Links
  **immer** neuer Tab (fix)?
- F2: Default für `cursor_marker` — `off`, `line` oder gleich `caret`?
- F2: reicht dir Stufe A/B (approximativ), oder willst du perspektivisch Stufe C
  (exakt) — das ist deutlich größer.

---

## Status / Umsetzung (2026-07)

Umgesetzt in v0.2.0 (Feature-Commits):

- **F1 externe Links → neuer Tab.** `src/client/render/externalLinks.ts`
  (`markExternalLinks`) setzt `target=_blank rel=noopener noreferrer` auf
  externe `<a>`. Konfigurierbar über `browser.external_links` (`"new_tab"`
  Default | `"same_tab"`), an den Client als `&extlinks=` übergeben. Entscheidung
  zu „immer fix vs. konfigurierbar": **konfigurierbar**, Default `new_tab`.
- **F1 Back/Forward.** `src/client/render/history.ts`: Neovim sendet pro
  Dokumentwechsel einen `\x04`-Doc-Ping (`/doc`-Endpoint → `ws_client.send_doc`),
  der Client führt `pushState`; `popstate` bittet Neovim via `/nav`, das
  Zieldokument wieder zu öffnen (braucht `experimental.click_navigate`, default
  an). `viaPopstate`-Flag verhindert Push-Schleifen.
- **F2 Stufe A (Zeilen-Marker).** `src/client/render/cursorMarker.ts`
  (`updateCursorMarker`), blinkende Bar im linken Gutter an der Cursor-Zeile,
  positioniert mit demselben sourcepos-Block + In-Block-Interpolation wie der
  Scroll-Sync. Konfigurierbar über `browser.cursor_marker` (`"line"` Default |
  `"off"`), an den Client als `&cursor=` übergeben. Entscheidung Default:
  **`line`** — „was gut funktioniert und einfach ist".

### Künftige Task: Stufe C — exakter Spalten-Caret via Source-Map

Der Zeilen-Marker ist bewusst approximativ (markiert die Zeile, nicht die
Spalte). Ein spaltengenauer Caret braucht eine **exakte Source-Map** vom
Renderer: comrak liefert bereits `data-sourcepos` pro Block (Start/Ende
Zeile:Spalte); für Spaltengenauigkeit muss der Renderer zusätzlich pro
Text-/Inline-Knoten den Quell-Offset ausgeben (oder der WASM-Layer baut aus der
comrak-AST eine Zeichen-Offset↔DOM-Node-Tabelle). Der Client bindet dann den
nvim-`(row, col)` über diese Tabelle auf einen exakten DOM-Textknoten +
Character-Offset ab und setzt den Caret per `Range`/`getClientRects()`.

Die vom Nutzer vorgeschlagene Marker-Konsens-Heuristik (n-tes `a`, Whitespace
zählen …) hilft hier nicht zuverlässig: auf Zeilen mit Inline-Markup (`**`, `` ` ``,
`[..](..)`) driften Quell- und Render-Zeichen gemeinsam, alle Marker landen
gleich falsch. Nur die echte Source-Map löst das exakt. → eigenständige Task,
größerer Aufwand, zurückgestellt.
