
 **irgendwo** muss `busted` ausgeführt werden. Je nachdem welche Variante man in der CI wählt, bedeutet das:

* Bei **Linux-native** Steps: muss `lua5.3`, `liblua5.3-dev`, `luarocks` und `busted` (z. B. `luarocks install --local busted`) installiert sein.
* Bei **Windows-native** Steps: muss `busted` auf dem Windows-Runner installiert sein (selten; Installation auf Windows ist möglich, aber oft kompliziert).
* Bei der **Container-/Docker-/Podman-Variante**: muss `busted` **nicht** auf dem Host installiert sein — der Container installiert die nötigen Pakete zur Laufzeit (oder ein Image mit bereits installiertem busted kann verwendet werden). Diese Variante ist portabel und am wartungsarmsten.

Unten sind präzise Hinweise und ein empfohlenes, robustes CI-Snippet (ersetzt den Bereich, der aktuell mehrere Varianten kommentiert). Es verwendet bedingte Steps gemäß `runner.os` — so läuft auf Linux die native Variante, auf Windows die PowerShell-Variante, und zusätzlich ist eine Container-Fallback-Variante vorhanden, falls Docker/Podman verfügbar ist.

Wichtige Punkte vorab

* Wenn `luarocks install` auf CI ausgeführt wird und native Compilation erforderlich ist, benötigt man `liblua5.3-dev` und `build-essential` (Linux).
* Bei nicht-root-Umgebungen immer `--local` zu `luarocks install` verwenden (installiert unter `~/.luarocks`). Pfad in PATH via `$GITHUB_PATH` hinzufügen.
* Die Container-Variante ist plattformunabhängig und am zuverlässigsten, sofern Docker/Podman auf dem Runner läuft.
* Erzeuge vorab Ausgabe-Verzeichnisse (`tests/lua/output`) damit Upload/Report-Steps keine fehlenden Pfade melden.

Empfohlenes CI-Snippet (ersetzt den Block mit den drei Varianten). Die `if`-Klauseln sorgen dafür, dass nur die jeweils passende Variante ausgeführt wird.

```yaml
# Replace previous "Run Busted ..." block with the following conditional steps.
# Comments in English inside code (per project conventions).

# Ensure busted output dir exists (cross-platform)
- name: Ensure busted output dir exists
  shell: pwsh
  run: |
    # Create output dir in a cross-platform way
    New-Item -ItemType Directory -Path tests/lua/output -Force | Out-Null

# 1) Native Linux: install busted (if not preinstalled) and run it.
- name: Run Busted natively on Linux (install if needed)
  if: runner.os == 'Linux'
  shell: bash
  run: |
    # If busted exists, run it; otherwise install required packages and busted locally
    if command -v busted >/dev/null 2>&1; then
      echo "busted found in PATH — running tests"
      busted --pattern="*.spec.lua" --lpath="./?.lua" --output-junit=tests/lua/output/busted.xml tests/lua || true
    else
      echo "busted not found — installing dependencies and busted (local install)"
      sudo apt-get update -y
      sudo apt-get install -y lua5.3 liblua5.3-dev luarocks build-essential
      # install busted into the user's local luarocks tree
      luarocks install --lua-version=5.3 --local busted
      echo "${HOME}/.luarocks/bin" >> $GITHUB_PATH
      # run tests (do not fail the workflow on test failures; the reporter handles results)
      busted --pattern="*.spec.lua" --lpath="./?.lua" --output-junit=tests/lua/output/busted.xml tests/lua || true
    fi

# 2) Container (Docker/Podman) - portable fallback, works on Windows or Linux if runtime present.
- name: Run Busted inside container (Docker/Podman) - portable
  if: runner.os == 'Windows' || runner.os == 'Linux'
  shell: pwsh
  run: |
    $out = "tests/lua/output"
    # prefer podman, fallback to docker
    $tool = if (Get-Command podman -ErrorAction SilentlyContinue) { "podman" } elseif (Get-Command docker -ErrorAction SilentlyContinue) { "docker" } else { "" }
    if ($tool -eq "") {
      Write-Host "No container runtime found (docker/podman). Skipping container-based busted."
      exit 0
    }
    Write-Host "Using container runtime: $tool"
    # On Windows, GitHub expands ${{ github.workspace }} at workflow parsing time.
    $ws = '${{ github.workspace }}'
    # Run a short-lived Ubuntu container, install busted and run tests; output is written back to workspace
    & $tool run --rm -v "$ws:/work" -w /work ubuntu:22.04 bash -lc `
      "set -e; apt-get update -qq; apt-get install -y -qq lua5.3 liblua5.3-dev luarocks build-essential; luarocks install --local busted; mkdir -p /work/tests/lua/output; busted --pattern='*.spec.lua' --lpath='./?.lua' --output-junit=/work/tests/lua/output/busted.xml tests/lua || true"

# 3) Native Windows: run busted if preinstalled on the Windows runner
- name: Run Busted (PowerShell) if installed on Windows runner
  if: runner.os == 'Windows'
  shell: pwsh
  run: |
    # If busted is installed on the Windows runner (rare), run it; otherwise skip.
    if (Get-Command busted -ErrorAction SilentlyContinue) {
      Write-Host "busted found on Windows runner: running tests..."
      & busted --pattern="*.spec.lua" --lpath="./?.lua" --output-junit=tests/lua/output/busted.xml tests/lua
    } else {
      Write-Host "busted not found on Windows runner; skipping Lua tests. Consider using container fallback or install busted on the runner."
    }
```

Erklärung / Empfehlungen zu obigem Snippet

* Die **Linux-native** Step installiert nur falls nötig. Sie nutzt `--local` für luarocks, deshalb keine Root-Luarocks-Install erforderlich (aber `liblua5.3-dev` und `build-essential` erfordern sudo). Nach der lokalen luarocks-Installation wird `~/.luarocks/bin` in `$GITHUB_PATH` geschrieben, damit `busted` erreichbar ist.
* Die **Container-Variante** ist portabel — wenn Docker/Podman auf dem Runner zur Verfügung steht, wird ein Ubuntu-Container kurz gestartet, installiert Lua + luarocks + busted lokal im Container, und schreibt das Ergebnis nach `/work/tests/lua/output/busted.xml` (also zurück in das gemountete Arbeitsverzeichnis). Vorteil: Host muss nichts installieren.
* Die **Windows-native** Option prüft nur und läuft nur, wenn bereits `busted` installiert ist. Falls Windows-Runner dauerhaft verwendet werden soll, empfiehlt sich auf dem Runner eine dauerhafte Installation von Lua + luarocks + busted oder die Nutzung der Container-Variante.
* Alle Varianten schreiben `tests/lua/output/busted.xml` — damit kann der Upload/Reporting-Step konsistent auf diese Datei verweisen.

Weitere Hinweise

* Lokales Testen: vor dem Push lokal `busted --output-junit=tests/lua/output/busted.xml tests/lua` ausführen, um sicherzustellen, dass die XML entsteht und valide ist.
* Caches: wenn native Linux-Installationen oft gebraucht werden, kann `~/.luarocks` gecached werden, oder man verwendet ein dediziertes Runner-Image mit busted bereits vorinstalliert.
* Rechte: bei `luarocks install --local` ist kein sudo notwendig; die nativen Debian-Pakete (`liblua5.3-dev` etc.) brauchen allerdings sudo.
* Pfad-Ersetzung: im Container-Step wird `${{ github.workspace }}` vom Runner expanded — das ergibt auf Windows Pfade, die Docker unter Umständen korrekt mountet; falls Mounting-Probleme auftreten, auf Linux-Runner ausweichen oder Pfad-Konversion prüfen.

Fazit / Empfehlung

* Die **Container-Variante** ist in CI die robusteste (kein dauerhafter Installationsaufwand auf Runner, plattformunabhängig).
* Wenn auf eigenen Self-hosted Runnern konstant gearbeitet wird, lohnt sich ein vorinstallierter Runner (Self-hosted) mit busted — dann sind native Steps am schnellsten.
* Wenn man mehrere Umgebungen unterstützen will, ist der obige bedingte Ansatz (runner.os checks) korrekt und zuverlässig.

Wenn gewünscht, passe ich die komplette `.github/workflows/ci.yml` mit diesen Änderungen an (inkl. Erzeugung/Upload des Artifact und Test-Report-Workflow), oder erstelle ein kurzes Debug-Script, mit dem man lokal bzw. auf Runner prüfen kann, ob die XML-Datei korrekt erzeugt wird. Welche Option bevorzugt werden soll?
