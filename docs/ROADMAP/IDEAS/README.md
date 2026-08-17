# Ideen

Was hier liegt, ist **nicht geplant** — es ist festgehalten, damit es nicht
verlorengeht.

| Ordner | Inhalt |
| --- | --- |
| **dieser** | Ideen ohne nahe Umsetzung: exotisch, noch nicht konkretisiert, oder bewusst zurückgestellt |
| [`../ROADMAP.md`](../ROADMAP.md) | offene Punkte, die konkret genug zum Anfangen sind |
| [`../DONE.md`](../DONE.md) | Entscheidungs-Log: was gebaut wurde und warum so |
| [`../FEATURES/`](../FEATURES/) | Katalog dessen, was es heute gibt |

Die Grenze zur Roadmap: **kann man morgen anfangen?** Wenn ja, gehört es in
`ROADMAP.md`. Wenn zuerst noch Entwurfsarbeit, eine Grundsatzentscheidung
oder ein konkreter Bedarfsfall fehlt, gehört es hierher.

## Inhalt

- **[KONZEPT_overlays.md](KONZEPT_overlays.md)** — generisches, erweiterbares
  Overlay-System über der Preview (schwebendes TOC, Cursor-Lupe, Keycast) als
  ein System statt loser Einzel-Features. Teile davon existieren inzwischen
  (`src/client/render/overlays/`), das Gesamtkonzept ist offen.
- **[KONZEPT_links_und_cursor.md](KONZEPT_links_und_cursor.md)** — Link-Verhalten
  im Preview-Tab und Cursor-Overlay. Der Link-Teil ist inzwischen weitgehend
  umgesetzt (`externalLinks.ts`, `clickNav.ts`, `linkHover.ts`); die
  Cursor-Overlay-Stufen sind es nicht.
- **[KONZEPT_headless_und_standalone.md](KONZEPT_headless_und_standalone.md)** —
  Preview ohne laufende Neovim-Instanz. `:MDView standalone` deckt den
  Hauptfall ab; die weitergehenden Stufen sind offen.

> Diese drei Dokumente sind älter als der Go/Rust-Rewrite und nennen teils
> Endpoints, die es nicht mehr gibt (z. B. `/render?key=`). Als Idee bleiben
> sie gültig, die Umsetzung folgt der heutigen Architektur.
