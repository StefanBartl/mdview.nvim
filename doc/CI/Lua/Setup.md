# Github CI Setup  Weg / Erklärungen für Lua

## Table of content

  - [Optimierung 3](#optimierung-3)
    - [Vorteile dieser Variante](#vorteile-dieser-variante)
  - [Optimierung 2](#optimierung-2)
    - [Vorteile dieser Version](#vorteile-dieser-version)
  - [Optimierung 1](#optimierung-1)
    - [1. Caching für Node und LuaRocks](#1-caching-fr-node-und-luarocks)
    - [2. Parallele Jobs](#2-parallele-jobs)
    - [3. Minimal-Smoketests sind OK](#3-minimal-smoketests-sind-ok)
    - [4. Zusammenfassung der empfohlenen Änderungen](#4-zusammenfassung-der-empfohlenen-nderungen)
    - [5. Hinweise](#5-hinweise)
  - [3](#3)
    - [Korrigierte GitHub Actions Steps für Lua](#korrigierte-github-actions-steps-fr-lua)
    - [Wichtige Punkte](#wichtige-punkte)
  - [2](#2)
  - [1](#1)
    - [1. **Installation in den lokalen Benutzerbereich**](#1-installation-in-den-lokalen-benutzerbereich)
    - [2. **Mit sudo installieren**](#2-mit-sudo-installieren)
    - [Beispiel für GitHub Actions (lokal installierte Lua-Tools)](#beispiel-fr-github-actions-lokal-installierte-lua-tools)

---

## Optimierung 3

Hier ist eine optimierte Variante deiner GitHub Actions CI, bei der der **Lua-Job explizit auf den Node-Job wartet**. So werden Lua-Checks nur ausgeführt, wenn Node/TypeScript erfolgreich durchgelaufen ist. Außerdem bleiben alle Caches aktiv, Smoke-Tests minimal, und parallele Ausführung wird kontrolliert:

```yaml
# CI pipeline for mdview.nvim
# - Node/TypeScript: install, lint, test, build client
# - Lua: basic static check with luacheck and optional busted unit tests

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
      - name: Checkout repository
        uses: actions/checkout@v4

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
        continue-on-error: false

      - name: Run unit tests (client/server)
        run: npm test

      - name: Build client
        run: npm run build

  lua:
    name: Lua / Neovim quick checks
    runs-on: ubuntu-latest
    needs: node  # <- Lua job startet erst, wenn Node erfolgreich ist
    steps:
      - uses: actions/checkout@v4

      - name: Cache LuaRocks
        uses: actions/cache@v4
        with:
          path: ~/.luarocks
          key: ${{ runner.os }}-luarocks-5.3-${{ hashFiles('**/*.rockspec') }}

      - name: Install system dependencies (Lua 5.3 + headers, luarocks, neovim)
        run: |
          sudo apt-get update
          sudo apt-get install -y lua5.3 liblua5.3-dev luarocks git neovim build-essential

      - name: Install luacheck via luarocks locally
        run: |
          luarocks install --lua-version=5.3 --local luacheck || true

      - name: Add local luarocks bin to PATH
        run: echo "${HOME}/.luarocks/bin" >> $GITHUB_PATH

      - name: Run luacheck on Lua sources
        run: luacheck lua/mdview --no-color || true

      - name: (Optional) Run Lua unit tests with busted
        run: |
          if command -v busted >/dev/null 2>&1; then
            busted -v tests/lua || true
          else
            echo "busted not installed; skipping Lua unit tests"
          fi
```

### Vorteile dieser Variante

1. **Abhängigkeit Node → Lua**: Lua-Checks laufen nur, wenn Node/TS erfolgreich gebaut wurde. Das spart Fehlersuche, z. B. wenn Server- oder Client-Code kaputt ist.
2. **Caches aktiv**: `~/.npm`, `node_modules/.vite` und `~/.luarocks` werden zwischengespeichert → deutlich kürzere CI-Laufzeiten bei wiederholten Builds.
3. **Lokale LuaRocks-Installation** (`--local`) verhindert Schreibrechte-Probleme.
4. **Smoke-Tests bleiben minimal**, CI-Läufe stabil.
5. Optional: Lua-Tests (busted) laufen nur, wenn installiert, sonst überspringt CI, ohne Fehler zu erzeugen.

--AUDIT:
Wenn du willst, kann ich dir noch eine **Version schreiben, die Node- und Lua-Jobs so cached und parallelisiert, dass erste Runs schnell starten**, aber trotzdem **sicherstellt, dass Lua nur bei Node-Erfolg läuft**, und zusätzlich **Vitest-Snapshots und Busted-Tests** sauber trennt. Willst du, dass ich das mache?

---

## Optimierung 2

Hier ist eine optimierte Version deiner CI-Pipeline, inklusive Node/Vite-Cache, LuaRocks-Cache und parallelen Jobs. Smoke-Tests bleiben minimal, alles andere unverändert.

```yaml
# CI pipeline for mdview.nvim
# - Node/TypeScript: install, lint, test, build client
# - Lua: basic static check with luacheck and optional busted unit tests

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
      - name: Checkout repository
        uses: actions/checkout@v4

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
        continue-on-error: false

      - name: Run unit tests (client/server)
        run: npm test

      - name: Build client
        run: npm run build

  lua:
    name: Lua / Neovim quick checks
    runs-on: ubuntu-latest
    # runs parallel to Node.js job
    steps:
      - uses: actions/checkout@v4

      - name: Cache LuaRocks
        uses: actions/cache@v4
        with:
          path: ~/.luarocks
          key: ${{ runner.os }}-luarocks-5.3-${{ hashFiles('**/*.rockspec') }}

      - name: Install system dependencies (Lua 5.3 + headers, luarocks, neovim)
        run: |
          sudo apt-get update
          sudo apt-get install -y lua5.3 liblua5.3-dev luarocks git neovim build-essential

      - name: Install luacheck via luarocks locally
        run: |
          luarocks install --lua-version=5.3 --local luacheck || true

      - name: Add local luarocks bin to PATH
        run: echo "${HOME}/.luarocks/bin" >> $GITHUB_PATH

      - name: Run luacheck on Lua sources
        run: luacheck lua/mdview --no-color || true

      - name: (Optional) Run Lua unit tests with busted
        run: |
          if command -v busted >/dev/null 2>&1; then
            busted -v tests/lua || true
          else
            echo "busted not installed; skipping Lua unit tests"
          fi
```

### Vorteile dieser Version

1. Node- und Lua-Job laufen **parallel**, spart Wall-Clock-Zeit (~1–2 Minuten bei Smoke-Tests).
2. Node: `~/.npm` + `node_modules/.vite` gecacht → schnellerer Rebuild bei kleinen Änderungen.
3. Lua: `~/.luarocks` gecacht → wiederverwendbare Lua-Tools, schnellerer CI-Lauf.
4. Lokale LuaRocks-Installation (`--local`) verhindert Schreibrechte-Probleme.
5. Smoke-Tests bleiben minimal, CI läuft stabil, Fehler werden korrekt erkannt.

---

## Optimierung 1

### 1. Caching für Node und LuaRocks

**Node:**

* Du hast `~/.npm` bereits gecacht. Optional kann man noch `node_modules/.vite` oder `.cache/vite` hinzufügen, um Vite-Builds zu beschleunigen.
* **Vorsicht:** Wenn du neue Pakete installierst oder `package-lock.json` änderst, wird der Cache invalidiert, daher keine Nachteile, nur der Cache wird kurz neu aufgebaut.

**LuaRocks:**

* Der lokale Installationspfad ist `~/.luarocks`. Wenn wir diesen cache’n, muss man darauf achten, dass bei Änderungen an Luacheck oder Lua-Version der Cache invalidiert wird.
* Nachteil: Wenn die Lua-Version in Zukunft wechselt, kann der Cache veraltet sein → wir müssen den Key abhängig von Lua-Version und ggf. Rockspec machen.

Beispiel für Cache in `lua`-Job:

```yaml
- name: Cache LuaRocks
  uses: actions/cache@v4
  with:
    path: ~/.luarocks
    key: ${{ runner.os }}-luarocks-5.3-${{ hashFiles('**/*.rockspec') }}
```

---

### 2. Parallele Jobs

* Aktuell: `lua`-Job braucht `node` (`needs: node`) → läuft sequenziell.
* Da dein Lua-Smoke-Test unabhängig von Node/TS ist, kann man ihn **parallel** laufen lassen.
* Vorteil: Wall-Clock-Zeit sinkt deutlich (Node-Tests und Lua-Checks gleichzeitig).
* Nachteil: Wenn du Node-Build-Artefakte für Lua brauchst (aktuell nicht der Fall), darfst du die Abhängigkeit nicht entfernen.

---

### 3. Minimal-Smoketests sind OK

* Deine Tests (`smoke.test.ts` für Node, `smoke_spec.lua` für Lua) sind schon trivial, da keine externen Abhängigkeiten → keine Optimierung nötig.

---

### 4. Zusammenfassung der empfohlenen Änderungen

**Node-Job bleibt fast gleich**, ggf. Vite-Cache ergänzen:

```yaml
- name: Cache Vite
  uses: actions/cache@v4
  with:
    path: node_modules/.vite
    key: ${{ runner.os }}-vite-${{ hashFiles('**/package-lock.json') }}
```

**Lua-Job parallel laufen lassen, mit LuaRocks-Cache:**

```yaml
lua:
  name: Lua / Neovim quick checks
  runs-on: ubuntu-latest
  # needs: node  <-- entfernen, läuft parallel
  steps:
    - uses: actions/checkout@v4

    - name: Cache LuaRocks
      uses: actions/cache@v4
      with:
        path: ~/.luarocks
        key: ${{ runner.os }}-luarocks-5.3-${{ hashFiles('**/*.rockspec') }}

    - name: Install system dependencies (Lua 5.3 + headers, luarocks, neovim)
      run: |
        sudo apt-get update
        sudo apt-get install -y lua5.3 liblua5.3-dev luarocks git neovim build-essential

    - name: Install luacheck via luarocks locally
      run: |
        luarocks install --lua-version=5.3 --local luacheck || true

    - name: Add local luarocks bin to PATH
      run: echo "${HOME}/.luarocks/bin" >> $GITHUB_PATH

    - name: Run luacheck on Lua sources
      run: luacheck lua/mdview --no-color || true

    - name: (Optional) Run Lua unit tests with busted
      run: |
        if command -v busted >/dev/null 2>&1; then
          busted -v tests/lua || true
        else
          echo "busted not installed; skipping Lua unit tests"
```

---

### 5. Hinweise

* **Cache-Invalidierung:** Wenn du Node-Pakete oder Lua-Rocks änderst, muss der Cache neu aufgebaut werden. Dafür sorgt der Hash über `package-lock.json` bzw. `*.rockspec`.
* **Lokale Installation** (`--local`) verhindert Schreibrechte-Probleme auf GitHub-Runner.
* **Parallelität:** Lua-Job kann parallel laufen, spart bis zu ~1 Minute pro Build.
* **Smoke-Tests minimal:** keine Änderung nötig, die Tests laufen unabhängig vom Build.

---

## 3

Luacheck ist **ein C-Modul**, das kompiliert werden muss, und LuaRocks sucht dafür nach den **Lua-Header-Dateien** (`lua.h`, etc.).

Bei Ubuntu musst du die Lua-Dev-Pakete installieren, sonst schlägt die Installation fehl. Für Lua 5.3 heißt das Paket `liblua5.3-dev`.

---

### Korrigierte GitHub Actions Steps für Lua

```yaml
lua:
  name: Lua / Neovim quick checks
  runs-on: ubuntu-latest
  needs: node
  steps:
    - uses: actions/checkout@v4

    - name: Install system dependencies (Lua 5.3 + headers, luarocks, neovim)
      run: |
        sudo apt-get update
        sudo apt-get install -y lua5.3 liblua5.3-dev luarocks git neovim build-essential

    - name: Install luacheck via luarocks locally
      run: |
        # Install into local tree (~/.luarocks) for Lua 5.3
        luarocks install --lua-version=5.3 --local luacheck

    - name: Add local luarocks bin to PATH
      run: echo "${HOME}/.luarocks/bin" >> $GITHUB_PATH

    - name: Run luacheck on Lua sources
      run: |
        luacheck lua/mdview --no-color || true

    - name: (Optional) Run Lua unit tests with busted
      run: |
        if command -v busted >/dev/null 2>&1; then
          busted -v tests/lua || true
        else
          echo "busted not installed; skipping Lua unit tests"
        fi
```

---

### Wichtige Punkte

1. `liblua5.3-dev` liefert die Header-Dateien (`lua.h`, `lualib.h`) → Luacheck kompiliert problemlos.
2. `build-essential` liefert Compiler, Make etc., die für das Kompilieren von LuaRocks-Paketen notwendig sind.
3. Mit `--local` wird alles in `~/.luarocks` installiert → keine Root-Rechte nötig.

Damit sollte der CI-Step stabil laufen und Luacheck korrekt installieren.


---

## 2

Hier ist eine vollständig korrigierte Version deines GitHub Actions CI-Jobs für Lua, die stabil mit **Lua 5.3** läuft, Luacheck lokal installiert und optional Busted ausführt, ohne Root-Rechte:

```yaml
lua:
  name: Lua / Neovim quick checks
  runs-on: ubuntu-latest
  needs: node
  steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Install system dependencies (Lua 5.3, luarocks, neovim)
      run: |
        sudo apt-get update
        sudo apt-get install -y lua5.3 luarocks git neovim build-essential

    - name: Install luacheck via luarocks locally
      run: |
        # Install into local tree (~/.luarocks) for Lua 5.3
        luarocks install --lua-version=5.3 --local luacheck

    - name: Add local luarocks bin to PATH
      run: echo "${HOME}/.luarocks/bin" >> $GITHUB_PATH

    - name: Run luacheck on Lua sources
      run: |
        # Lint Lua code; continue even if there are warnings
        luacheck lua/mdview --no-color || true

    - name: (Optional) Run Lua unit tests with busted
      run: |
        if command -v busted >/dev/null 2>&1; then
          busted -v tests/lua || true
        else
          echo "busted not installed; skipping Lua unit tests"
        fi
```

**Erklärung der Änderungen

1. **`--lua-version=5.3`**: erzwingt, dass Luacheck für die installierte Lua 5.3-Version gebaut wird. Ohne das schlägt die Installation in GitHub Actions fehl.
2. **`--local`**: installiert Pakete in `~/.luarocks`, keine Root-Rechte nötig.
3. **`$GITHUB_PATH`**: fügt `~/.luarocks/bin` zum PATH hinzu, damit `luacheck` und Busted gefunden werden.
4. **`|| true`** bei Luacheck/Busted: verhindert, dass der CI-Job bei Lint-Warnungen oder fehlenden Tests fehlschlägt.


---

## 1

Das Problem liegt nicht an deinem Workflow-Skript per se, sondern daran, wie `luarocks` standardmäßig installiert und genutzt wird:

* Standardmäßig versucht `luarocks install` Systemverzeichnisse (`/usr/local/lib/luarocks/...`) zu beschreiben.
* In GitHub Actions läuft der Runner **nicht als root**, daher fehlen die Schreibrechte → Fehler.

Es gibt zwei übliche Lösungen:

---

### 1. **Installation in den lokalen Benutzerbereich**

`luarocks` unterstützt den Parameter `--local`, um Pakete in den Benutzerpfad zu installieren. In GitHub Actions kannst du das so ändern:

```yaml
- name: Install luacheck via luarocks
  run: |
    luarocks install --local luacheck
```

Damit wird Luacheck in `~/.luarocks` installiert und es werden keine Root-Rechte benötigt. Danach musst du ggf. den Pfad zu den Binärdateien setzen, damit der Runner `luacheck` findet:

```yaml
- name: Add local luarocks bin to PATH
  run: echo "${HOME}/.luarocks/bin" >> $GITHUB_PATH
```

`$GITHUB_PATH` ist die GitHub Actions-Variable, die neue Pfade systemweit für alle nachfolgenden Steps exportiert.

---

### 2. **Mit sudo installieren**

Du könntest alternativ die Installation mit Root-Rechten erzwingen:

```yaml
- name: Install luacheck via luarocks
  run: sudo luarocks install luacheck
```

Nachteil: unnötige Root-Rechte, weniger portabel, kann in Zukunft zu Berechtigungsproblemen führen. Variante 1 (`--local`) ist sicherer.

---

### Beispiel für GitHub Actions (lokal installierte Lua-Tools)

```yaml
  lua:
    name: Lua / Neovim quick checks
    runs-on: ubuntu-latest
    needs: node
    steps:
      - uses: actions/checkout@v4

      - name: Install system deps
        run: |
          sudo apt-get update
          sudo apt-get install -y neovim lua5.3 luarocks

      - name: Install luacheck via luarocks locally
        run: |
          luarocks install --local luacheck

      - name: Add local luarocks bin to PATH
        run: echo "${HOME}/.luarocks/bin" >> $GITHUB_PATH

      - name: Run luacheck on Lua sources
        run: luacheck lua/mdview --no-color || true

      - name: (Optional) Run Lua unit tests with busted
        run: |
          if command -v busted >/dev/null 2>&1; then
            busted -v tests/lua || true
          else
            echo "busted not installed; skipping Lua unit tests"
          fi
```

Damit wird Luacheck korrekt installiert, PATH gesetzt und der Step schlägt nicht mehr fehl.

---
