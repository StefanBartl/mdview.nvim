# mdview.nvim — Roadmap

> Erledigtes samt Begründungen: [`Roadmap/Roadmap.md`](Roadmap/Roadmap.md).
> Diese Datei sammelt **offene** Punkte.

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
