# Infos

## Table of content

  - [1. **Tags / Labels für Self-Hosted Runner**](#1-tags-labels-fr-self-hosted-runner)
  - [2. **Wechsel zu GitHub-Hosted Runners**](#2-wechsel-zu-github-hosted-runners)
  - [3. Labels ändern](#3-labels-ndern)
  - [4. Labels nachsehen](#4-labels-nachsehen)

---

## 1. **Tags / Labels für Self-Hosted Runner**

   Bei einem self-hosted Runner wird die Zuweisung von „Tags“ bzw. „Labels“ über die Runner-Installation definiert. Das geht so:

   * Auf dem Runner-Host das Setup-Script ausführen, z. B.:

     ```bash
     ./config.sh --url https://github.com/<owner>/<repo> --token <token>
     ```
   * Während der Konfiguration fragt das Script nach **Labels**. Du kannst z. B. angeben:

     ```
     linux,fast,wien,home
     ```

     oder beliebige andere Bezeichner.
   * In deiner Workflow-Datei kannst du dann:

     ```yaml
     runs-on: [self-hosted, linux, fast]
     ```

     GitHub Actions wählt nur Runner aus, die **alle angegebenen Labels** haben.

   Hinweise:

   * Labels sind frei wählbar, z. B. Standort, Gerät, Speed-Level, OS.
   * Das ist unabhängig vom Hostnamen, der nur als Identifier dient. Hostname taucht in GitHub UI unter „Runner“ auf.

---

## 2. **Wechsel zu GitHub-Hosted Runners**

   * Einfach `runs-on:` ändern, z. B.:

     ```yaml
     runs-on: ubuntu-latest
     ```
   * Dann werden die Jobs auf GitHub-Hosted VMs ausgeführt, keine Self-Hosted Runner benötigt.
   * Vorteile: keine eigene Wartung, automatisch aktuelle Images.
   * Nachteil: keine persistente Cache/Installation außer über `actions/cache`.

3. **Hybrid-Szenario**

   * Man kann eine Kombination aus Self-Hosted und Hosted Runners nutzen.
   * Zum Beispiel `runs-on: [self-hosted, fast]` für große Builds oder Geräteabhängige Tests,
     und `runs-on: ubuntu-latest` für schnelle, kleine Checks.

Die Labels auf Self-Hosted Runnern sind also das zentrale Werkzeug, um Jobs gezielt auf Geräte/Standorte zu schicken. Der Hostname wird nur zur Übersicht in GitHub UI genutzt, aber **nicht** für die Runner-Auswahl.

---

## 3. Labels ändern

Die Labels eines Self-Hosted Runners lassen sich nachträglich ändern – auf zwei Wegen:

1. **Über das Konfigurations-Script neu setzen**

   * Auf dem Runner-Host das Setup-Script erneut starten:

     ```bash
     ./config.sh remove   # optional, um den alten Runner zu entfernen
     ./config.sh --url https://github.com/<owner>/<repo> --token <token>
     ```
   * Während der Konfiguration wirst du erneut nach Labels gefragt. Dort neue Tags vergeben, z. B.:

     ```
     linux,fast,wien,home
     ```

2. **Direkt in der GitHub UI ändern**

   * Gehe zu **Settings → Actions → Runners** in deinem Repository oder deiner Organisation.
   * Wähle den Self-Hosted Runner aus.
   * Dort gibt es ein Feld für **Labels** (Tags). Du kannst sie bearbeiten und speichern.

**Hinweise:**

* Änderungen an Labels wirken **nur auf neue Job-Dispatches**. Jobs, die bereits laufen, werden nicht beeinflusst.
* Labels müssen keine festen Formate haben; du kannst OS, Standort, Speed-Level oder andere Eigenschaften als Tags nutzen.

Damit kann man gezielt steuern, welche Jobs auf welchem Self-Hosted Runner landen.

--

## 4. Labels nachsehen

Wenn beim Start des Self-Hosted Runners keine Labels/TAGS angezeigt werden, bedeutet das, dass dem Runner noch **keine benutzerdefinierten Labels** zugewiesen wurden. Standardmäßig meldet ein Runner nur sich selbst als verfügbar, ohne zusätzliche Tags wie `linux`, `fast` etc.

So kannst du Labels setzen und einsehen:

1. **Beim Registrieren eines Runners**
   Bei der Registrierung (`config.cmd` auf Windows, `config.sh` auf Linux/macOS) gibt es die Option `--labels`:

   ```cmd
   config.cmd --url <Repo-URL> --token <TOKEN> --name MyRunner --labels linux,fast
   ```

   Danach meldet sich der Runner mit diesen Labels bei GitHub.

2. **Im GitHub Webinterface**

   * Repository → **Settings → Actions → Runners**
   * Klicke auf den gewünschten Self-Hosted Runner → dort siehst du die **Labels**.
   * Du kannst hier auch Labels **hinzufügen oder entfernen**, ohne den Runner neu zu registrieren.

3. **Nachträgliches Ändern auf dem Runner-Host**

   * Du kannst die Labels lokal nicht direkt ändern, sondern musst den Runner **neu konfigurieren** (`config.cmd remove` → `config.cmd` mit neuen Labels).
   * Alternativ im Webinterface bearbeiten.

Wenn du aktuell keine Labels siehst, hat dein Runner nur das Standardlabel `self-hosted`. Sobald du beim Setup eigene Labels angibst, erscheinen diese auch im Log beim Start.

Du kannst die gesetzten Labels/Tags deines Self-Hosted Runners auf zwei Wegen einsehen:

1. **GitHub Webinterface**

   * Gehe zu **Settings → Actions → Runners** im Repository oder in der Organisation.
   * Dort werden alle Self-Hosted Runner aufgelistet, inklusive Status (online/offline) und **Labels**.

2. **Auf dem Runner-Host selbst**

   * Im Installationsordner des Runners gibt es die Datei `/.runner` bzw. den Konfigurationsordner.
   * Du kannst die Labels mit diesem Befehl auslesen:

     ```bash
     ./svc.sh status  # Windows
     ./run.sh list   # Linux/macOS, je nach Runner-Version
     ```
   * Oder beim Starten/Debuggen des Runners:

     ```bash
     ./run.sh --once
     ```

     werden im Log die Labels angezeigt, die der Runner bei GitHub registriert hat.

Auf diese Weise siehst du, welche Tags aktuell vom Runner gemeldet werden und welche Jobs er annehmen kann.

---
