# Konzept: Overlay-System für die Preview

> Konzept, noch nicht umgesetzt. Ziel: aus Neovim heraus **beliebige,
> ein-/ausschaltbare Overlays** über der Browser-Preview steuern — schwebendes
> TOC, Cursor-Lupe, Keycast u. a. — als **ein generisches, erweiterbares
> System**, nicht als lose Einzel-Features. Baut auf dem bereits vorhandenen
> Live-Control-Kanal (`\x05` `/control` → `adapter/control.lua` → Client
> `applyControl`) auf, mit dem `:MDViewCursor`/`:MDViewZoom`/`:MDViewReveal`
> schon heute den offenen Tab ohne Reload verändern.

---

## 1. Grundprinzip

Ein **Overlay** ist eine unabhängige, ein-/ausschaltbare UI-Schicht über dem
gerenderten Dokument. Es zeichnet nur, greift nicht in den Content ein, und
mehrere Overlays können gleichzeitig aktiv sein. Getoggelt wird live aus nvim.

Faktisch gibt es schon Overlays: `cursor_marker` (line/caret/section), der
`⇅ scroll enabled`-Badge, `zoom`. Das Konzept **verallgemeinert** das zu einem
Manager mit Registry, damit neue Overlays billig dazukommen und sich nicht
gegenseitig ins Gehege kommen (gemeinsame Layer + Z-Index-Ordnung).

---

## 2. Architektur

### 2.1 Client — Overlay-Manager + Registry

Eine gemeinsame Overlay-Ebene im DOM:

```
#mdview-overlays   position: fixed; inset: 0; pointer-events: none; z-index: 20
  └─ pro Overlay ein Container; einzelne Overlays opten via pointer-events:auto
     wieder ein (klickbares TOC etc.)
```

Ein Overlay implementiert ein schlankes Interface:

```ts
interface Overlay {
  name: string;
  mount(ctx: OverlayCtx): void;     // DOM anlegen, Listener setzen
  unmount(): void;                  // alles wieder entfernen
  onCursor?(line: number, col: number): void;  // pro Scroll-/Cursor-Ping
  onRender?(): void;                // nach jedem Re-Render (innerHTML gewiped)
  onControl?(data: unknown): void;  // overlay-spezifisches Control-Payload
}

interface OverlayCtx {
  root: HTMLElement;          // #mdview-root (der Content)
  layer: HTMLElement;         // #mdview-overlays (die Overlay-Ebene)
  headings(): HeadingInfo[];  // aus dem DOM (h1..h6 + data-sourcepos)
  caretPixel(line, col): {x,y,h} | null; // wiederverwendet aus cursorMarker
  governingHeading(line): HeadingInfo | null; // aus der Section-Spotlight-Logik
}
```

Der **Manager** hält die aktiven Overlays, ruft die Hooks (`onCursor` beim
Scroll-Ping, `onRender` nach jedem `renderMarkdown`, `onControl` bei
overlay-adressierten Control-Nachrichten) und mountet/unmountet auf Toggle. Die
Helfer in `OverlayCtx` bündeln, was mehrere Overlays brauchen — v. a. die
schon existierende Caret-Pixel-Berechnung (`caretPixelBox`) und die
„governing heading"-Logik aus dem Section-Spotlight, damit TOC & Co. sie
wiederverwenden statt zu duplizieren.

### 2.2 Transport

- **Toggle & niederfrequente Updates** über den bestehenden Control-Kanal:
  `{overlay: {name, on}}`, batchbar als `{overlays: {toc:true, keycast:false}}`.
  `applyControl` reicht das an den Manager weiter.
- **Hochfrequente Datenströme** (Keycast!) bekommen einen **eigenen ephemeren
  Kanal** analog zu `/scroll` (`\x01`): neuer `/keys`-Endpoint mit Prefix
  `\x06`, nvim-seitig gebatcht/debounced — nicht jeden Tastendruck als eigenen
  HTTP-POST. Overlays, die nur getoggelt werden, brauchen das nicht.
- **Initialzustand** beim Öffnen via URL-Param `&overlays=toc,keycast`, damit
  ein wieder geöffneter Tab (`:MDViewOpen`) die aktiven Overlays wiederherstellt
  — gleiches Muster wie `?cursor=` / `?zoom=`.

### 2.3 Neovim

- **Ein generisches Command**: `:MDViewOverlay <name> [on|off|toggle]` plus
  `:MDViewOverlay list` (zeigt registrierte Overlays + Zustand). Tab-Completion
  über die Namen. (Optional dünne Aliase `:MDViewTOC`, `:MDViewKeycast`.)
- **Config**: `browser.overlays = { toc=false, magnifier=false, keycast=false }`
  als Default + Merker für Reopen.
- **Keymaps**: mdview liefert keine, aber Doku-Beispiele — der Wunsch war ja
  „schnell togglen":
  ```lua
  map("n", "<leader>ot", "<cmd>MDViewOverlay toc toggle<cr>")
  map("n", "<leader>om", "<cmd>MDViewOverlay magnifier toggle<cr>")
  map("n", "<leader>ok", "<cmd>MDViewOverlay keycast toggle<cr>")
  ```
- **Datenquellen-Manifest** in Lua: pro Overlay, welche nvim-Seite es braucht.
  So registriert z. B. Keycast `vim.on_key()` **nur**, wenn es aktiv ist, und
  hängt es beim Ausschalten wieder ab (kein Dauerkostenpunkt).

### 2.4 Lifecycle & Persistenz

Overlays sind rein Preview-seitig und live-getoggelt. `browser.overlays` ist
Default + Reopen-Merker. **Keycast defaultet aus** (Privacy, s. u.).

---

## 3. Die konkreten Overlays

### 3.1 Floating TOC (Mini-Outline)  — klein–mittel

- **Datenquelle**: rein client-seitig aus dem DOM (`h1..h6` + `data-sourcepos`).
  Keine neue nvim-Seite nötig.
- **UI**: schwebendes Panel in einer Ecke; Liste der Überschriften eingerückt
  nach Level; der **aktuelle Abschnitt hervorgehoben** — nutzt die Cursor-Zeile
  (kommt schon über den Scroll-Ping) + dieselbe „governing heading"-Logik wie
  der Section-Spotlight. Dazu ein Fortschrittshinweis („Abschnitt 3/12" oder ein
  dünner Balken), damit der Zuschauer sieht, wo im Dokument man ist.
- **Interaktion**: Klick auf einen Eintrag scrollt die Preview dorthin. Optional
  (Entscheidung s. u.): den nvim-Cursor mitziehen (über den vorhandenen
  reverse-scroll-Bridge-Mechanismus).
- **Warum zuerst**: höchster Nutzen für den Coaching-Fall, baut fast komplett
  auf Vorhandenem auf.

### 3.2 Cursor-Lupe / Magnifier  — mittel

- **Datenquelle**: die Caret-Pixelposition (schon vorhanden via `caretPixelBox`;
  exakt mit den `source_map`-Spans, grob über die Blockposition ohne sie).
- **UI (echte Linse)**: runde `position:fixed`-Linse mit einem **geklonten,
  skalierten** Ausschnitt von `#mdview-root` — Text bleibt vektorscharf (kein
  Pixel-Sampling à la html2canvas). Bei Cursor-Ping neu positionieren, bei
  Re-Render das Klon-`innerHTML` synchronisieren.
- **UI (einfachere Variante „Focus-Zoom")**: statt Linse den Block/Absatz unter
  dem Cursor sanft vergrößern (Fisheye-light). Weniger Code, gut für „schau
  genau hier".
- **Empfehlung**: Focus-Zoom als v1, echte Linse als Ausbau.

### 3.3 Keycast (Tastatureingaben anzeigen)  — mittel

- **Datenquelle**: `vim.on_key()` in nvim → Ringpuffer der letzten N Tasten,
  **debounced** (~120 ms) → POST `/keys` → `\x06`-Broadcast an den Client.
- **UI**: transientes Pill unten (wie *screenkey*), zeigt die zuletzt gedrückten
  Tasten und faded nach ~1,5 s aus.
- **Übersetzung**: rohe Bytes → lesbare Namen (`j`, `<C-w>`, `<Esc>`, `:w<CR>`)
  via `vim.fn.keytrans()` — nvim-seitig, der Client zeigt nur an.
- **Privacy** (wichtig): Insert-Mode-Tasten würden getippten Text zeigen. Config
  `keycast_scope = "non_insert" | "all"` (Default `non_insert`: nur Normal-/
  Command-/Operator-Tasten) und Keycast **komplett per Default aus**. So sieht
  der Zuschauer die *Bedienung* (Motions, Commands), nicht zwingend jeden
  Buchstaben.

### 3.4 Weitere Ideen (gleich mitdenken)

- **Reading-Progress-Bar**: dünner Balken oben, Position im Dokument.
- **Attention-Ping / „Laserpointer"**: `:MDViewPing` löst einen kurzen
  Highlight-Puls am Caret aus — Blick lenken ohne Maus. (Winziges Overlay,
  großer Effekt bei Calls.)
- **Presenter-Notes**: `speaker`-Fences (analog zu `private`), die **nur** als
  nvim-seitiges Overlay/Panel erscheinen, nicht im geteilten Tab — Stichpunkte
  für dich, unsichtbar für den Zuschauer. (Größer; eigenes Konzept wert.)
- **Minimap** des Dokuments am Rand.

---

## 4. Verhältnis zu bestehenden Features

`cursor_marker`, der rscroll-Badge und `zoom` sind faktisch schon Overlays.
Vorschlag: **neue** Overlays laufen über den Manager; die bestehenden Marker
bleiben zunächst wie sie sind und werden **optional später** unter das
Overlay-Dach gezogen (reiner Refactor, kein Muss). Der einzige harte Punkt jetzt:
eine gemeinsame Overlay-Ebene + klare Z-Index-Ordnung einführen, damit sich
TOC / Lupe / Keycast / Marker sauber stapeln statt chaotisch zu überlappen.

---

## 5. Phasen

1. **Fundament**: Overlay-Manager + Registry + `#mdview-overlays`-Ebene +
   `:MDViewOverlay` + `browser.overlays` + Control-/URL-Routing.
2. **Floating TOC** (nutzt Section-Logik + Headings).
3. **Focus-Zoom / Lupe**.
4. **Keycast** (neuer `/keys`-Kanal + `vim.on_key` + `keytrans`).
5. **Zugaben**: Progress-Bar, Attention-Ping.

Jede Phase ist eigenständig lauffähig und testbar (Manager + je Overlay:
vitest/jsdom für die Client-Logik, headless-nvim für die Command-/Datenquelle,
Browser-Probe für Pixel-Positionen — wie bei Caret & Section).

---

## 6. Offene Entscheidungen für dich

- **Command-Form**: ein generisches `:MDViewOverlay <name> [on|off|toggle]`
  (+ `list`) — Empfehlung — oder je Overlay ein eigenes Command? (Beides geht;
  generisch + optionale Aliase ist am flexibelsten.)
- **TOC-Klick**: nur die Preview scrollen, oder auch den nvim-Cursor mitziehen?
- **Keycast**: Default-Umfang `non_insert` vs. `all`, und ob überhaupt
  standardmäßig anbietbar (bleibt in jedem Fall opt-in).
- **Lupe**: pragmatischer Focus-Zoom zuerst, oder gleich die echte Klon-Linse?
- **Migration**: sollen `cursor_marker`/Badge/`zoom` perspektivisch unter den
  Overlay-Manager wandern, oder dauerhaft getrennt bleiben?
