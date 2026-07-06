* [x] CI (GitHub Actions) anlegen: `.github/workflows/ci.yml`

Hinweise zur Datei und zum Workflow
* `node` Job führt Install, Lint, Test und Build für Client/Server aus. Man benötigt in `package.json` die Scripts `lint`, `test` und `build`. Falls diese noch fehlen, bitte entsprechende npm-Scripts anlegen (z. B. `lint: "eslint 'src/**' 'src/client/**'"`, `test: "vitest"`, `build: "tsc && rollup -c"` oder eine einfache Build-Kette).
* `lua` Job macht ein leichtes statisches Checking mit `luacheck`. Das ist eine schnelle, portable Initial-Überprüfung und vermeidet komplexe Neovim-Testsetups in der Anfangsphase.
* Später kann man `lua` Job erweitern um:
  * `plenary`/`busted` Tests via `nvim --headless` oder Installation von `busted` via luarocks,
  * E2E Tests mittels Playwright/Headless Chrome,
  * optional eine separate Matrix für Bun vs Node (wenn Bun als Option unterstützt wird).
* Cache für Node nutzt `actions/setup-node` und `actions/cache`. Anpassungen bei Verwendung von `pnpm` oder `yarn` sind möglich.

Aktualisierte Checkliste (Status)
* [x] Repository initialisieren (Git) und README / LICENSE anlegen
* [x] .gitignore ergänzen
* [x] Monorepo-/Ordnerstruktur anlegen:
  * [x] `lua/mdview/` (Neovim Lua Core)
  * [x] `plugin/` (plugin loader)
  * [x] `src/server/` (Node.js/Bun server)
  * [x] `src/client/` (TypeScript client)
  * [x] `wasm/` (WASM proof-of-concept / bindings)
  * [x] `tests/` (Unit & Integration tests)
  * [x] `ci/` (CI Konfiguration)
* [x] CI (GitHub Actions) anlegen: `.github/workflows/ci.yml`

Nächste Schritte, damit der erste Initial-Commit vollständig ist
* Man kann die Datei `.github/workflows/ci.yml` ins Repo hinzufügen und committen.
* Sicherstellen, dass in `package.json` die npm-Scripts `lint`, `test` und `build` existieren (auch als Platzhalter), damit CI nicht scheitert.
* Optional: minimale `tests/`-Stub-Dateien hinzufügen, damit `npm test` nicht fehlschlägt.
* Danach kann der initiale Commit erstellt und gepusht werden — die CI wird beim Push automatisch ausgelöst.
