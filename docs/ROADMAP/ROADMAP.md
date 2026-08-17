# mdview.nvim — offene Punkte

Alles, was ansteht und konkret genug ist, um angefangen zu werden. Was noch
zu vage oder zu exotisch dafür ist, steht in [`../IDEAS/`](../IDEAS/).

| Wo | Inhalt |
| --- | --- |
| **diese Datei** | **offene** Punkte — hier anfangen |
| [`DONE.md`](DONE.md) | Entscheidungs-Log: was gebaut wurde und *warum so* |
| [`../FEATURES/`](../FEATURES/) | Katalog dessen, was es heute gibt |
| [`../IDEAS/`](../IDEAS/) | Ideen ohne nahe Umsetzung |
| [`SCHLACHTPLAN.md`](SCHLACHTPLAN.md) | Feedback-Runde nach v0.1.0 |
| [`history/`](history/) | Vor-Rewrite-Dokumente, nur Historie |
| [`personal/`](personal/) | persönliche Notizen, kein Roadmap-Teil |

---

## PDF-Seitenvorschau im Link-Hover

**Status:** offen, bewusst zurückgestellt (2026-08-17).

Der Link-Hover im Browser (`src/client/render/linkHover.ts`) zeigt für
`.pdf`-Ziele nur den Dateinamen. Der In-Editor-Hover in `markdown.nvim`
rendert dagegen Seite 1 inline — dort liegt `pdfport.render_page` im selben
Prozess.

**Warum im Browser nicht:** Der Browser kann Neovim nicht direkt fragen. Die
einzige Rückrichtung ist die Polling-Bridge (`lua/mdview/adapter/inbound_poll.lua`,
Intervall 250 ms). Ein PDF-Hover bräuchte damit:

1. Browser legt eine Anfrage in eine Server-Queue,
2. bis zu 250 ms, bis Neovim sie pollt,
3. `pdfport.render_page` rastert über `pdftoppm` (mehrere hundert ms),
4. das PNG landet im Temp-Verzeichnis — und ist damit **nicht** über `/asset`
   ausliefbar, weil diese Route bewusst auf das Dokumentverzeichnis
   eingegrenzt ist.

Ergebnis: rund eine Sekunde Latenz für einen Hover, plus eine neue Route,
die die Verzeichnis-Bindung aufweichen müsste — also genau die
Sicherheitseigenschaft, die `/asset` und `/preview` absichtlich eng halten.
Für ein Hover ein schlechter Tausch.

**Der saubere Weg, falls es später gewünscht ist:** Pre-Render beim
Doc-Push statt Anfrage zur Hover-Zeit. Neovim kennt beim Senden eines
Dokuments dessen Links; es könnte referenzierte PDFs vorab rastern und die
PNGs **neben das Dokument** legen. Dann greift der bestehende `/asset`-Pfad
unverändert — keine neue Route, keine aufgeweichte Containment-Prüfung,
keine Hover-Latenz. Kosten: Rasterarbeit für PDFs, die vielleicht nie
gehovert werden, und Schreibzugriff neben dem Dokument (Cache-Verzeichnis,
Aufräumen, `.gitignore`-Frage).

Erst angehen, wenn es einen konkreten Bedarfsfall gibt.

---

## Kooperatives Tab-Schließen im `default`-Browsermodus

**Status:** offen, Aufwand mittel.

Im Modus `browser.mode = "default"` öffnet mdview die URL im normalen Browser
des Nutzers (eigene Extensions, eigenes Profil). Preis: mdview kann den Tab
nicht programmatisch schließen, deshalb sind `browser_autoclose` und
`stop_on_browser_exit` dort No-ops.

Lösungsidee: kooperatives Schließen — der Client reagiert auf ein
WebSocket-`close`-Event mit `window.close()`. Damit würde Auto-Close auch im
default-Modus funktionieren, ohne ein isoliertes Profil zu erzwingen.

> Herkunft: In [`DONE.md`](DONE.md) (BUGS #2) als „in
> `TASKS.md` erfasst" vermerkt — diese Datei wurde jedoch nie angelegt, die
> Aufgabe war damit nirgends festgehalten. Hier nachgetragen.

---

## Externe Renderer-Website (opt-in)

**Status:** offen, opt-in, mit Vorbehalt.

Idee: das Rendering optional an eine externe Website auslagern statt lokal
per WASM.

**Vorbehalt:** widerspricht dem Loopback-only-Modell — Dokumentinhalte
würden das Gerät verlassen. Nur als ausdrückliches Opt-in mit deutlichem
Privacy-Hinweis denkbar. `browser.open_url` ist bereits die Escape-Hatch,
um eine beliebige URL zu öffnen, was den Bedarf teilweise abdeckt.

> Herkunft: wie oben — in [`DONE.md`](DONE.md)
> (Rendering #2) als „in `TASKS.md` festgehalten" vermerkt, ohne dass es
> diese Datei je gab.
