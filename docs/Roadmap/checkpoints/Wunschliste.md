# Wunschliste / Features (Architektur-Vorschläge)

1. MDViewStart mit Datei-Argumenten
   * Man kann `:MDViewStart /path/to/file.md` erlauben; der Launcher/initial_push ruft dann eine initiale `render?key=<normalized>` oder startet eine gezielte Push-Action.
   * API: `nvim_create_user_command("MDViewStart", fn, { nargs = "?", complete = "file" })`.

1. Verhalten beim Buffer-Wechsel (aktualisieren vs. neuer Tab vs. kein Update)
   * Konfigurationsoptionen (already present): `browser_behavior = "reuse" | "new_tab" | "manual"`.
   * Implementation: Beim BufferChange entscheidet `live_push` ob es `push_buffer` ausführt und zusätzlich ob `launcher` den Browserhandle benutzt, um eine neue URL zu öffnen (new tab) oder nur `ws_client.send_markdown` für den vorhandenen preview.

3. Click-to-navigate (Links/anchors im Browser navigieren zu anderen files)
   Drei mögliche Implementierungen, mit Vor/Nachteilen:

   * A) Server dient Dateisystem (static file serving) und Client wandelt links in `/render?key=normalized_path` um.
     * Vorteil: simpel, server braucht nur Leserechte im CWD.
     * Nachteil: evtl. Sicherheitsaspekte (nur serve unter projekt-root), eventuell viele Dateien.

    * B) Client auf Link-Klick sendet WebSocket-Nachricht an die Neovim-Extension/Daemon, welche dann die Datei lädt und per `/render?key=...` pusht.
         * Vorteil: keine zusätzlichen Date-Server nötig, Neovim bleibt single source of truth.
         * Nachteil: benötigt ein bidirektionales Protokoll zwischen Client ↔ Neovim (WS already present to server, aber server → Neovim bridge muss implementiert oder Runner erweitert werden).

    * C) Kombiniert: Server kennt workspace-root und liefert `/file?path=...` beschränkt auf cwd. Client klickt Link -> fetch `/file?path=...` -> server liest file and responds with markdown or redirect to `/render?key=...`.
         * Empfehlung: B oder C sind am flexibelsten; C ist einfacher, wenn server bereits im Projekt-CWD gestartet wird.

---

## Sicherheits- und UX-Hinweise

* Bei Server-Seiten-Serving: man kann den erlaubten Root einschränken (nur project root), und Pfad-Normalisierung verwenden, um Directory-Traversal zu vermeiden.
* Bei automatischem Öffnen neuer Browser-Tabs: man kann eine Nutzer-Option anbieten, da viele Nutzer nur ein Tab wollen.

---
