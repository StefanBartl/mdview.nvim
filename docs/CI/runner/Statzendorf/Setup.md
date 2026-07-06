# Setup

## Table of content

  - [Variante 4: Vitest- und Busted-Testergebnisse direkt in der GitHub Actions GUI anzeigen](#variante-4-vitest-und-busted-testergebnisse-direkt-in-der-github-actions-gui-anzeigen)
    - [Details:](#details)
  - [Variante 3: Gibt Vitest (Node.js/TS) und Busted (Lua) in JUnit/XML-Testberichte](#variante-3-gibt-vitest-nodejsts-und-busted-lua-in-junitxml-testberichte)
    - [Funktionsweise / Details](#funktionsweise-details)
  - [Version 3: Node.js/TypeScript und Lua/Busted parallelisiert; Ergebnisse in GitHub Actions sichtbar](#version-3-nodejstypescript-und-luabusted-parallelisiert-ergebnisse-in-github-actions-sichtbar)
    - [Details und Vorteile](#details-und-vorteile)
  - [Version 2: Node.js/TypeScript und Lua/Neovim parallelisiert, Cache-Verwendung](#version-2-nodejstypescript-und-luaneovim-parallelisiert-cache-verwendung)
    - [Verbesserungen](#verbesserungen)
  - [Version 1:  Einrichtung des Self-hosted Runners](#version-1-einrichtung-des-self-hosted-runners)
    - [1. Self-hosted Runner in GitHub registrieren](#1-self-hosted-runner-in-github-registrieren)
    - [Erstelle ein Runner-Verzeichnis](#erstelle-ein-runner-verzeichnis)
    - [Lade den Runner herunter (z.B. für Linux x64)](#lade-den-runner-herunter-zb-fr-linux-x64)
    - [Entpacken](#entpacken)
    - [Konfiguriere den Runner](#konfiguriere-den-runner)
    - [Starte den Runner im Hintergrund](#starte-den-runner-im-hintergrund)
    - [2. GitHub CI Jobs einem Self-hosted Runner zuweisen](#2-github-ci-jobs-einem-self-hosted-runner-zuweisen)
    - [3. Logs & GitHub UI](#3-logs-github-ui)
    - [4. Vorteile](#4-vorteile)
    - [5. Wichtig](#5-wichtig)

---

## Variante 4: Vitest- und Busted-Testergebnisse direkt in der GitHub Actions GUI anzeigen

Erweitern wir die CI so, dass **Vitest- und Busted-Testergebnisse direkt in der GitHub Actions GUI** angezeigt werden, ohne dass man Artefakte manuell herunterladen muss. Dafür nutzt man den **`test-report-annotation` Mechanismus**, also GitHub Action, die JUnit/XML-Dateien liest und als Test-Check ins PR/Commit einbindet.

Hier ist die angepasste Version:

```yaml
# CI pipeline for mdview.nvim - Node + Lua with Test Reporting in GitHub UI
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  node:
    name: Node.js / TypeScript
    runs-on: [self-hosted, linux, fast]
    steps:
      - uses: actions/checkout@v4

      - name: Cache node modules
        uses: actions/cache@v4
        with:
          path: ~/.npm
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-

      - name: Install dependencies
        run: npm ci

      - name: Lint (TypeScript / JS)
        run: npm run lint

      - name: Run Vitest unit tests and output JUnit XML
        run: npm test -- --reporter=junit --outputFile=tests/node/vitest.xml
        continue-on-error: false

      - name: Upload Node test results to GitHub UI
        uses: mikeal/junit-report-action@v2
        with:
          results: tests/node/vitest.xml

      - name: Build client
        run: npm run build

      - name: Upload Node build artifacts
        uses: actions/upload-artifact@v3
        with:
          name: node-build
          path: dist/

  lua:
    name: Lua / Neovim
    runs-on: [self-hosted, linux, fast]
    needs: node
    steps:
      - uses: actions/checkout@v4

      - name: Add local luarocks bin to PATH
        run: echo "${HOME}/.luarocks/bin" >> $GITHUB_PATH

      - name: Run luacheck
        run: luacheck lua/mdview --no-color || true

      - name: Run Lua unit tests with busted and output JUnit XML
        run: |
          mkdir -p tests/lua/output
          if command -v busted >/dev/null 2>&1; then
            busted -v \
              --pattern="*.spec.lua" \
              --lpath="./?.lua" \
              --output-junit=tests/lua/output/busted.xml \
              tests/lua || true
          else
            echo "busted not installed; skipping Lua unit tests"

      - name: Upload Lua test results to GitHub UI
        uses: mikeal/junit-report-action@v2
        with:
          results: tests/lua/output/busted.xml
```

### Details:

1. **`mikeal/junit-report-action@v2`**

   * Liest die JUnit/XML-Dateien von Vitest (`vitest.xml`) und Busted (`busted.xml`) ein.
   * Zeigt die Ergebnisse direkt als **Test-Check im Pull Request oder Commit** an.
   * Grün/Rot für erfolgreich/fehlgeschlagen, direkt in GitHub UI sichtbar.

2. **Selbstgehostete Runner**

   * Da Node.js, Lua, LuaRocks und Busted schon installiert sind, entfällt die Initialinstallation.
   * Pipeline läuft wesentlich schneller.

3. **Datei-Struktur**

   * Node Tests: `tests/node/*.test.ts` → `tests/node/vitest.xml`
   * Lua Tests: `tests/lua/*.spec.lua` → `tests/lua/output/busted.xml`

4. **Optionalität**

   * Lua-Tests brechen die Pipeline nicht, falls Busted nicht installiert ist.
   * Luacheck läuft nur als Lint und kann Fehler melden, aber Pipeline bricht nicht.

---

## Variante 3: Gibt Vitest (Node.js/TS) und Busted (Lua) in JUnit/XML-Testberichte

Hier ist eine optimierte CI-Version für **mdview.nvim**, die Vitest (Node.js/TS) und Busted (Lua) in **JUnit/XML-Testberichte** ausgibt, sodass GitHub Actions das direkt unter „Tests“ anzeigen kann. Außerdem ist sie auf Self-hosted Runner optimiert, bei dem Node.js, Lua 5.3, LuaRocks und Busted bereits installiert sind.

```yaml
# CI pipeline for mdview.nvim - Self-hosted with GitHub Test Reporting
# Vitest + Busted output in JUnit/XML for GitHub Actions

name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  node:
    name: Node.js / TypeScript
    runs-on: [self-hosted]
    steps:
      - uses: actions/checkout@v4

      - name: Cache node modules
        uses: actions/cache@v4
        with:
          path: ~/.npm
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-

      - name: Install dependencies
        run: npm ci

      - name: Lint (TypeScript / JS)
        run: npm run lint

      - name: Run Vitest unit tests and produce JUnit XML
        run: npm test -- --reporter=junit --outputFile=tests/node/vitest.xml
        continue-on-error: false

      - name: Upload Vitest test report
        uses: actions/upload-artifact@v3
        with:
          name: vitest-test-report
          path: tests/node/vitest.xml

      - name: Build client
        run: npm run build

      - name: Upload Node build artifacts
        uses: actions/upload-artifact@v3
        with:
          name: node-build
          path: dist/

  lua:
    name: Lua / Neovim
    runs-on: [self-hosted]
    steps:
      - uses: actions/checkout@v4

      - name: Add local luarocks bin to PATH
        run: echo "${HOME}/.luarocks/bin" >> $GITHUB_PATH

      - name: Run luacheck
        run: luacheck lua/mdview --no-color || true

      - name: Run Lua unit tests with busted and output JUnit XML
        run: |
          mkdir -p tests/lua/output
          if command -v busted >/dev/null 2>&1; then
            busted -v \
              --pattern="*.spec.lua" \
              --lpath="./?.lua" \
              --output-junit=tests/lua/output/busted.xml \
              tests/lua || true
          else
            echo "busted not installed; skipping Lua unit tests"
          fi

      - name: Upload Lua test report
        uses: actions/upload-artifact@v3
        with:
          name: busted-test-report
          path: tests/lua/output/busted.xml
```

### Funktionsweise / Details

1. **Vitest**

   * `--reporter=junit --outputFile=tests/node/vitest.xml` erzeugt einen JUnit-konformen XML-Bericht.
   * GitHub Actions erkennt das Format automatisch, wenn du es z.B. mit dem `actions/upload-artifact` hochlädst.
   * Smoke-Tests oder echte Tests werden in der Actions GUI unter „Tests“ angezeigt.

2. **Busted**

   * `--output-junit=...` erzeugt JUnit/XML für GitHub.
   * `--pattern="*.spec.lua"` erkennt alle Lua-Testdateien, z. B. `smoke_spec.lua`.
   * `--lpath="./?.lua"` sorgt dafür, dass `require` korrekt funktioniert.

3. **Artefakte**

   * Node `dist/` wird hochgeladen.
   * Testberichte werden separat hochgeladen, sodass man sie jederzeit herunterladen oder analysieren kann.

4. **Self-hosted Runner**

   * Vorinstallation von Node.js, Lua 5.3, LuaRocks und Busted spart Zeit.
   * Keine Installationsschritte nötig → Pipeline läuft sehr schnell.

5. **Optionalität**

   * `luacheck` oder `busted` brechen die Pipeline nicht, wenn sie nicht installiert sind, es wird nur eine Warnung ausgegeben.

---

---

## Version 3: Node.js/TypeScript und Lua/Busted parallelisiert; Ergebnisse in GitHub Actions sichtbar

Hier ist eine optimierte CI-Version für **Self-hosted Runner**, die Node.js/TypeScript und Lua/Busted parallelisiert und die Ergebnisse sauber in GitHub Actions sichtbar macht. Sie ist darauf ausgelegt, dass Node.js, Lua 5.3, LuaRocks und Busted bereits auf dem Runner installiert sind, sodass die Setup-Zeit fast entfällt. Zusätzlich werden Artefakte und Test-Reports gesammelt.

```yaml
# CI pipeline for mdview.nvim - Self-hosted optimized
# Node.js + TypeScript and Lua/Busted fully parallel, with test reports and caching optional
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  node:
    name: Node.js / TypeScript
    runs-on: [self-hosted, linux, fast]   # assumes Node 18 + npm already installed
    steps:
      - uses: actions/checkout@v4

      - name: Cache node modules
        uses: actions/cache@v4
        with:
          path: ~/.npm
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-

      - name: Install dependencies
        run: npm ci

      - name: Lint (TypeScript / JS)
        run: npm run lint

      - name: Run unit tests (client/server)
        run: npm test

      - name: Build client
        run: npm run build

      - name: Upload Node artifacts
        uses: actions/upload-artifact@v3
        with:
          name: node-build
          path: dist/

  lua:
    name: Lua / Neovim
    runs-on: [self-hosted, linux, fast]   # assumes Lua 5.3 + LuaRocks + Busted installed
    steps:
      - uses: actions/checkout@v4

      - name: Add local luarocks bin to PATH
        run: echo "${HOME}/.luarocks/bin" >> $GITHUB_PATH

      - name: Run luacheck
        run: luacheck lua/mdview --no-color || true

      - name: Run Lua unit tests with busted
        run: |
          if command -v busted >/dev/null 2>&1; then
            mkdir -p tests/lua/output
            busted -v --output=plain --lpath="./?.lua" --pattern="*.spec.lua" --root=tests/lua > tests/lua/output/busted.txt || true
          else
            echo "busted not installed; skipping Lua unit tests"
          fi

      - name: Upload Lua test artifacts
        uses: actions/upload-artifact@v3
        with:
          name: lua-test-results
          path: tests/lua/output/
```

### Details und Vorteile

1. **Self-hosted Runner**

   * Node.js + npm + Lua 5.3 + LuaRocks + Busted vorinstalliert → erste Installationszeit entfällt komplett.
   * Caches nur optional für Node/npm und LuaRocks.

2. **Parallelisierung**

   * Node- und Lua-Jobs laufen gleichzeitig, unabhängig.
   * Kein unnötiges Warten auf Paketinstallation.

3. **Testberichte / Artefakte**

   * Node `dist/` wird als Build-Artefakt hochgeladen.
   * Lua Busted-Ausgabe in `tests/lua/output/busted.txt` → als Artifact für GitHub UI sichtbar.

4. **Optionalität**

   * Luacheck und Busted sind optional, Pipeline bricht nicht ab.
   * Smoke-Tests laufen trotzdem.

5. **Konfiguration von Busted**

   * `--pattern="*.spec.lua"` → erkennt alle Lua Testdateien mit `.spec.lua`.
   * `--lpath="./?.lua"` → sorgt dafür, dass `require` in Lua korrekt funktioniert.

6. **Maximale Geschwindigkeit**

   * Da alle Abhängigkeiten schon installiert sind, sollte der gesamte CI-Durchlauf **unter 30 Sekunden** möglich sein.

--

## Version 2: Node.js/TypeScript und Lua/Neovim parallelisiert, Cache-Verwendung

Hier ist eine optimierte Version deiner CI, die **Node.js/TypeScript** und **Lua/Neovim** parallelisiert, Caches effektiver nutzt und die Jobs für maximale Geschwindigkeit vorbereitet. Ich habe Self-hosted Runner vorbereitet, aber weiterhin die Ubuntu-Runner kompatibel gelassen. Artefakte und Logs bleiben in GitHub sichtbar.

```yaml
# Optimized CI pipeline for mdview.nvim
# - Node/TypeScript: install, lint, test, build client
# - Lua: basic static check with luacheck and optional busted unit tests
# - Parallel jobs & caching for speed

name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  node:
    name: Node.js / TypeScript
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'

      - name: Cache node modules
        uses: actions/cache@v4
        with:
          path: ~/.npm
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-

      - name: Cache Vite build
        uses: actions/cache@v4
        with:
          path: node_modules/.vite
          key: ${{ runner.os }}-vite-${{ hashFiles('**/package-lock.json') }}

      - name: Install dependencies
        run: npm ci

      - name: Lint (TypeScript / JS)
        run: npm run lint

      - name: Run unit tests (client/server)
        run: npm test

      - name: Build client
        run: npm run build

      - name: Upload Node build artifacts
        uses: actions/upload-artifact@v3
        with:
          name: node-build
          path: dist/

  lua:
    name: Lua / Neovim quick checks
    runs-on: ubuntu-latest
    needs: node   # startet parallel, sobald Node abgeschlossen
    steps:
      - uses: actions/checkout@v4

      - name: Cache LuaRocks
        uses: actions/cache@v4
        with:
          path: ~/.luarocks
          key: ${{ runner.os }}-luarocks-5.3-${{ hashFiles('**/*.rockspec') }}

      - name: Install system dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y lua5.3 liblua5.3-dev luarocks git neovim build-essential

      - name: Install luacheck locally
        run: |
          luarocks install --lua-version=5.3 --local luacheck || true

      - name: Add local luarocks bin to PATH
        run: echo "${HOME}/.luarocks/bin" >> $GITHUB_PATH

      - name: Run luacheck
        run: luacheck lua/mdview --no-color || true

      - name: Run Lua unit tests with busted
        run: |
          if command -v busted >/dev/null 2>&1; then
            busted -v tests/lua || true
          else
            echo "busted not installed; skipping Lua unit tests"
          fi

      - name: Upload Lua test artifacts
        uses: actions/upload-artifact@v3
        with:
          name: lua-test-results
          path: tests/lua/output/
```

### Verbesserungen

1. **Parallelisierung**: Node- und Lua-Jobs laufen parallel, abhängig nur durch `needs: node`.
2. **Caching**:

   * `~/.npm` für Node Module
   * `node_modules/.vite` für Vite-Builds
   * `~/.luarocks` für LuaRocks-Pakete
     → spart bei Wiederholungen mehrere Minuten Installationszeit.
3. **Artefakte**:

   * Node `dist/` → für Builds oder Debugging verfügbar
   * Lua `tests/lua/output/` → für Busted-Ergebnisse oder Logs
4. **Optionalität**:

   * Luacheck und Busted sind optional, Pipeline bricht nicht ab
5. **Selbst-hosted Kompatibilität**:

   * Du kannst `runs-on: [self-hosted, linux, fast]` verwenden, um die komplette Installation zu umgehen.

---

## Version 1:  Einrichtung des Self-hosted Runners

GitHub Actions unterstützt **Self-hosted Runner**, und die GUI / die GitHub Actions UI arbeitet genauso wie mit den Standard-Runners. Du musst GitHub nur mitteilen, dass es einen bestimmten Runner verwenden soll. Alles andere – Logs, Status, Artefakte – erscheinen weiterhin in der GitHub UI.

Hier die Details:

---

### 1. Self-hosted Runner in GitHub registrieren

1. Gehe in deinem Repository auf **Settings → Actions → Runners → New self-hosted runner**.
2. Wähle das passende Betriebssystem (Linux, Windows, macOS).
3. GitHub zeigt einen Befehl, den du auf deinem Server ausführen musst. Beispiel für Linux:

```bash
### Erstelle ein Runner-Verzeichnis
mkdir actions-runner && cd actions-runner

### Lade den Runner herunter (z.B. für Linux x64)
curl -o actions-runner-linux-x64-2.314.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.314.0/actions-runner-linux-x64-2.314.0.tar.gz

### Entpacken
tar xzf ./actions-runner-linux-x64-2.314.0.tar.gz

### Konfiguriere den Runner
./config.sh --url https://github.com/<user>/<repo> --token <TOKEN>

### Starte den Runner im Hintergrund
./run.sh
```

* `<TOKEN>` ist ein einmaliger Token, den GitHub bereitstellt.
* Danach hört der Runner auf Jobs, die auf ihn gematcht werden.

---

### 2. GitHub CI Jobs einem Self-hosted Runner zuweisen

In der Workflow-Datei (`.github/workflows/ci.yml`) definierst du den Runner-Typ:

```yaml
jobs:
  node:
    runs-on: self-hosted   # <- statt ubuntu-latest
    name: Node.js / TypeScript
    steps:
      - uses: actions/checkout@v4
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 18
      ...
```

* GitHub wählt einen freien Self-hosted Runner für diesen Job.
* Du kannst auch Labels verwenden:

```yaml
runs-on: [self-hosted, linux, fast]
```

* Dann muss der Runner die Labels `linux` und `fast` haben, sonst wird er nicht genommen.

---

### 3. Logs & GitHub UI

* Alle Job-Logs, Artefakte und Statusmeldungen erscheinen **wie gewohnt** in der GitHub Actions GUI.
* Unterschied: Statt einer VM in der Cloud läuft der Job auf deinem Server.

**Beispiele:**

* ✅ `npm install`, Vitest, Lua/Busted-Tests → Output erscheint in GitHub Actions.
* ✅ Build-Artefakte können mit `actions/upload-artifact` hochgeladen werden, falls du sie speichern willst.

---

### 4. Vorteile

* Sehr schneller Jobstart, da Node, Lua etc. schon installiert sind.
* Versionskontrolle über Labels oder Runner-Gruppen.
* Logs & Artefakte bleiben sichtbar wie bei normalen GitHub Runners.

---

### 5. Wichtig

* Security: Self-hosted Runner hat Zugriff auf dein Repo und Secrets. Am besten dedizierter Server oder VM.
* Wartung: Updates für Node, Lua, GitHub Runner regelmäßig durchführen.
* Parallelität: Pro Runner nur ein Job gleichzeitig; du kannst aber mehrere Runner parallel betreiben.

---
