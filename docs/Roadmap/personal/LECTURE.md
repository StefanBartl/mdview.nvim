# Coaching-/Lecture-Workflow mit mdview.nvim + markdown.nvim

> Persönliche Notiz, kein offizieller Roadmap-Teil. Szenario: 1:1-Call mit
> Coach, Screen-Share **nur des Browser-Tabs** mit der mdview-Preview, während
> du selbst in Neovim arbeitest (schreibst, springst zwischen Dateien,
> formatierst Tabellen, navigierst Überschriften) — der Coach sieht immer die
> gerenderte Markdown-Seite, nie dein Terminal/deine Config.

---

## 1. Einmaliges Setup (vor dem ersten Call)

### mdview.nvim config

```lua
require("mdview").setup({
  scroll_sync = true,
  scroll_sync_mode = "top",       -- "top": Zeile bleibt oben stabil beim Reden —
                                   -- ruhiger für einen passiven Zuschauer als
                                   -- "cursor" (Mirror), das bei jedem Scrollen
                                   -- springt. "cursor" ist eher was für dich
                                   -- allein (Editor-Gefühl).
  browser = {
    behavior        = "reuse",    -- EIN Tab folgt jedem Buffer-Wechsel — du
                                   -- musst das Sharing im Call nie neu wählen.
    focus           = "nvim",     -- Preview-Tab holt sich nie den Fokus/Vordergrund
                                   -- — du kannst weiterschreiben, ohne dass der
                                   -- Browser dich unterbricht.
    theme           = "github",   -- helles Theme liest sich über komprimiertes
                                   -- Video-Codec meist klarer als ein dunkles.
    external_links  = "new_tab",  -- ein Klick des Coaches auf einen Link verliert
                                   -- nie die geteilte Preview.
    cursor_marker   = "caret",    -- zeigt live, wo genau du gerade bist — du musst
                                   -- nicht mehr sagen "schau mal Zeile X".
    browser_autostart = true,
    require_display    = true,
  },
  experimental = {
    click_navigate = true,        -- relative Links im Preview öffnen die Zieldatei
                                   -- in nvim — nützlich, wenn der Coach selbst
                                   -- durch verlinkte Notizen klickt.
    reverse_scroll = false,       -- opt-in: siehe Abschnitt 4 (Kontrolle abgeben).
  },
})
```

Für maximale Privatsphäre beim Screen-Sharing (kein Verlauf/Lesezeichen/andere
Tabs sichtbar, falls der Browser mal in den Vordergrund kommt):
`browser.open_mode = "isolated"` + `browser.browser = "firefox"` (o. ä.) —
spawnt ein Wegwerf-Profil, das beim `:MDViewStop` auch zuverlässig wieder
zugeht (`browser.browser_autoclose`).

### Keymaps (mdview.nvim liefert bewusst keine mit)

```lua
local map = vim.keymap.set
map("n", "<leader>ms", "<cmd>MDViewStart<cr>",      { desc = "mdview: start" })
map("n", "<leader>mq", "<cmd>MDViewStop<cr>",       { desc = "mdview: stop" })
map("n", "<leader>mo", "<cmd>MDViewOpen<cr>",       { desc = "mdview: re-open tab" })
map("n", "<leader>mt", "<cmd>MDViewToggle<cr>",     { desc = "mdview: toggle" })
map("n", "<leader>mT", "<cmd>MDViewTheme<cr>",      { desc = "mdview: theme" })
map("n", "<leader>ml", "<cmd>MDViewShowWebLogs<cr>",{ desc = "mdview: web logs (debug vor dem Call)" })
```

### Relevante bestehende markdown.nvim-Keymaps (schon aktiv, nichts zu tun)

| Key | Aktion | Warum im Call nützlich |
|---|---|---|
| `<C-f>` / `<C-p>`, `]]` / `[[` | Heading vor/zurück | Schnell zum besprochenen Abschnitt springen, Preview folgt via scroll_sync |
| `{count}<leader>toc` | TOC einfügen/aktualisieren | Vor dem Call schnell eine Gliederung erzeugen |
| `<leader>tvt` / `<leader>tvx` | Tabellen-Float (Markdown/Box-Style) | Für dich selbst — sauberer lesen als Rohtext, ohne dass es der Coach sieht |
| `ma` / `mj` / `mi` | Link/Anchor/Bild öffnen | Schnell zwischen verwandten Notizen springen |
| `<leader>[` | Selektion/Wort in Link wrappen | Spontan während des Gesprächs verlinken |

---

## 2. Vor dem Call

1. Kurzer Trockenlauf: `:MDViewStart`, Theme/Lesbarkeit prüfen (`:MDViewTheme`),
   dann `:MDViewStop`.
2. Browserfenster in gewünschter Größe/Position vorplatzieren, **dann** erst
   den Screen-Share starten — und dabei explizit **nur das Browserfenster**
   teilen, nicht den ganzen Bildschirm/Desktop. `focus = "nvim"` sorgt dafür,
   dass es während des Calls nicht ungewollt in den Vordergrund springt.
3. Bei Reise/ohne Display: `:MDViewPreviewTab` als Fallback — read-only
   Treesitter-Preview direkt in einem nvim-Tab, komplett ohne Server/Browser.

## 3. Während des Calls

- **Thema starten:** `:MDViewStart <file>` (oder aktueller Buffer), einmal den
  Tab teilen — danach läuft alles über `behavior = "reuse"` automatisch mit.
- **Datei wechseln:** ganz normal `:e`, Telescope, `'0`-Marks etc. — der
  geteilte Tab zeigt automatisch die neue Datei, ohne dass du das Sharing neu
  auswählen musst.
- **Innerhalb eines Dokuments navigieren:** Heading-Sprünge (`<C-f>`/`<C-p>`)
  + `scroll_sync` bringen den Coach automatisch mit; `cursor_marker = "caret"`
  zeigt exakt die Stelle, über die du gerade sprichst.
- **Tabelle besprechen:** `:Markdown table view browsernice` öffnet sie groß
  und GitHub-gestylt in einem eigenen Tab (separat teilen oder kurz
  rüberschalten); `:Markdown table format` / `table mode on`, um sie live
  während des Gesprächs sauber zu halten.
- **Querverweis spontan anlegen:** `<leader>[` auf Wort/Selektion.
- **Kontrolle abgeben:** mit `experimental.reverse_scroll = true` kann der
  Coach im Preview selbst scrollen (Polling, kleine Latenz) — praktisch, wenn
  er/sie in Ruhe etwas nachlesen will, ohne dir "scroll mal hoch" zu sagen.
  Mit `click_navigate` kann er/sie sogar selbst auf einen Link klicken und die
  Zieldatei bei dir öffnen.

## 4. Nach dem Call

- `:MDViewStop` beendet den Relay **und** schließt den Tab
  (`browser.browser_autoclose`) — kein Aufräumen von Hand nötig.
- Siehe Feature-Idee „Session-Breadcrumbs" unten — aktuell noch nicht vorhanden,
  wäre aber genau für den Nachbereitung-Schritt gedacht.

---

## 5. Feature-Ideen — mdview.nvim

Sortiert nach Aufwand, mit Begründung aus genau diesem Szenario.

### Quick Wins

- **`:MDViewCursor [line|caret|off]`** — Laufzeit-Toggle für
  `browser.cursor_marker`, analog zu `:MDViewTheme`. Aktuell nur über
  `setup()`/URL-Param einstellbar; im Call will man aber spontan zwischen
  "zeig genau wo ich bin" (caret) und "lenk nicht ab" (off) wechseln können,
  ohne die Config neu zu laden.
- **`:MDViewSync [pause|resume|toggle]`** — Scroll-Sync temporär anhalten.
  Szenario: du scrollst kurz zu einer Referenzstelle weiter oben, ohne dass
  der Coach dahin mitgerissen wird, während er gerade den aktuellen Absatz
  liest.
- **Sichtbarer Indikator für `reverse_scroll`** — ein kleines Icon/Label im
  Preview, wenn der Modus aktiv ist, damit der Coach überhaupt weiß, dass er
  selbst scrollen darf (aktuell unsichtbares Feature).
- **`:MDViewZoom [+|-|reset]`** — Schriftgröße der Preview zur Laufzeit
  anpassen. Video-Calls komprimieren/downsamplen; größere Schrift verbessert
  die Lesbarkeit beim Gegenüber ohne System-Zoom des ganzen Fensters.

### Mittel

- **Section-Spotlight (`cursor_marker = "section"`)** — statt nur eines
  dünnen Carets/Bars den *gesamten aktuellen Abschnitt* (H2/H3-Block, Grenzen
  aus den vorhandenen `data-sourcepos`-Blockgrenzen ableitbar) leicht
  hervorheben und den Rest dezent abdunkeln. Ein 2–3px-Strich kann in
  Videokompression untergehen; ein ganzer hervorgehobener Block ist deutlich
  robuster sichtbar für einen passiven Zuschauer.
- **Privacy-Blöcke** — ein Marker im Markdown (z. B. Fence ` ```private ` oder
  `<!--private-->…<!--/private-->`), der im Browser standardmäßig
  verblurrt/versteckt gerendert wird, mit Klick-zum-Aufdecken oder
  `:MDViewReveal [on|off|toggle]`. Für Zahlen/Namen Dritter, die im Dokument
  stehen, aber während des Calls nicht offen sichtbar sein sollen — ohne dafür
  extra ein anderes Fenster/eine andere Datei pflegen zu müssen.
- **Session-Breadcrumbs** — während eine Session läuft, mitprotokollieren,
  welche Überschriften/Dokumente wann besucht wurden (baut auf der
  vorhandenen `:MDViewLog`-Infrastruktur auf); exportierbar als grobe
  "worüber haben wir wann gesprochen"-Gliederung. Direkt nützlich, um nach dem
  Call schnell Notizen/Follow-ups zu schreiben.

### Größer

- **Persistenter Mini-Outline-Overlay** — ein schwebendes TOC im Preview, das
  die aktuelle Position hervorhebt, unabhängig vom Scroll-Zustand sichtbar
  bleibt. Hilft dem Coach, Struktur und Fortschritt im Dokument im Blick zu
  behalten, ohne dass du ständig sagst "wir sind jetzt bei Punkt 3 von 5".

---

## 6. Feature-Ideen — markdown.nvim

### Quick Wins

- **`:Markdown table view browser`/`browsernice`: Tab wiederverwenden** —
  ERLEDIGT. Jeder Aufruf schrieb vorher in eine neue `vim.fn.tempname()`-Datei
  und öffnete sie neu; über einen längeren Call sammelten sich so mehrere
  Tabellen-Tabs an. Jetzt schreibt jeder Stil (`browser_basic`/
  `browser_niceified`) in eine **feste** Datei
  (`stdpath("cache")/markdown_nvim/tableview_<style>.html`); der System-Opener
  wird nur beim **ersten** Aufruf pro Neovim-Session aufgerufen, danach wird
  nur die Datei überschrieben — ein ins generierte HTML eingebettetes
  Auto-Refresh-Script pollt per Intervall und übernimmt neuen Inhalt im
  bereits offenen Tab (Scroll-Position bleibt erhalten). `reopen` als Argument
  (`:Markdown table view browser reopen`, `:TableViewOpenBrowserNice reopen`)
  erzwingt einen frischen Tab, falls der alte von Hand geschlossen wurde.
  Umgesetzt in
  `lua/markdown_nvim/tableview/views/browser_session.lua` (markdown.nvim),
  getestet in `TESTS/browser_session_spec.lua`.
- **`:checkhealth`-Hinweis für den Coaching-Anwendungsfall** — wenn
  `mdview.nvim` erkannt ist, aber `browser.focus != "nvim"` oder
  `browser.behavior != "reuse"` konfiguriert ist, einen informativen Hinweis
  ausgeben ("für Screen-Share-Workflows empfohlen: …"). Kein neues Feature,
  nur ein Doku-/Health-Check-Baustein, der genau dieses Setup nahelegt.

### Bereits vorhanden (im Workflow nutzen, nicht neu bauen)

- `:Markdown refs sync`/`live` hält TOC + In-Doc-Links konsistent, wenn du
  während des Gesprächs live eine Überschrift umbenennst — kein Zutun nötig.
- `fenced_scope` (` ```markdown `-Sub-Dokument) eignet sich bereits, um eine
  Call-Agenda als eigenen Mini-Bereich mit eigener TOC/Navigation im selben
  Dokument zu führen, ohne ein zweites File zu pflegen.
