
## Busted

Hier ist eine präzise Übersicht, wie man beides handhabt: Podman für die Container-Variante und Busted auf einem Windows-Runner.

---

## 1. Podman für Cross-Plattform CI (Windows/Linux)

### Windows

1. **Podman installieren**

   * Lade die Windows-Version von Podman herunter:
     [https://podman.io/getting-started/installation](https://podman.io/getting-started/installation)
   * Empfohlen: **Windows 10/11 mit WSL2 Backend**.
   * Alternativ kann Docker Desktop genutzt werden, Podman CLI ist weitgehend kompatibel.

2. **Nach der Installation**

   * Prüfen:

     ```powershell
     podman --version
     ```
   * WSL2-Distribution muss korrekt eingerichtet sein. Podman nutzt diese, um Linux-Container zu starten.
   * Die CI-Variante im Workflow prüft automatisch:

     ```powershell
     $tool = if (Get-Command podman -ErrorAction SilentlyContinue) { "podman" } elseif (Get-Command docker -ErrorAction SilentlyContinue) { "docker" } else { "" }
     ```

3. **Optional**: Podman in Windows-Path setzen, falls CI Runner Powershell nicht automatisch findet.

---

### Linux

* Auf Ubuntu/Debian:

  ```bash
  sudo apt update
  sudo apt install -y podman
  podman --version
  ```
* Danach funktioniert der gleiche Workflow-Step wie unter Windows.

---

## 2. Busted auf Windows installieren

### Voraussetzungen

* Lua 5.3 oder 5.4 für Windows (LuaBinaries oder über Scoop/Chocolatey)
* LuaRocks für Windows (läuft nativ)

### Schritt-für-Schritt

1. **Scoop installieren** (falls noch nicht vorhanden)

   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   iwr -useb get.scoop.sh | iex
   ```

2. **Lua und LuaRocks installieren**

   ```powershell
   scoop install lua53
   scoop install luarocks
   ```

3. **Busted installieren**

   ```powershell
   luarocks install busted
   ```

4. **Prüfen**

   ```powershell
   busted --version
   ```

   * Danach kann die Windows-native Step im Workflow `busted` finden und ausführen.

---

### Hinweise / Tipps

* Auf Windows empfiehlt sich eher die **Container-Variante** (Docker/Podman), um Probleme mit lokalen Abhängigkeiten zu vermeiden.
* Native Installation auf Windows ist machbar, erfordert aber Lua + LuaRocks Setup.
* Auf Linux kann man entweder native Installation (`apt install lua5.3 ...`) nutzen oder die Container-Variante.

---

Wenn gewünscht, kann ich direkt eine **fertige Schritt-für-Schritt-Anleitung erstellen**, die in GitHub Actions sowohl Windows- als auch Linux-Runner automatisch Podman/Docker nutzt, und nur native Busted-Installation für Linux optional macht.

Willst du, dass ich das mache?
