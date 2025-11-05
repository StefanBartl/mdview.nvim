# Übersicht: Ansatz von markdown-preview.nvim kurz erklärt

## Table of content

  - [Detaillierte Komponenten und Ablauf](#detaillierte-komponenten-und-ablauf)
  - [Warum markdown-preview so gestaltet ist — Designgründe](#warum-markdown-preview-so-gestaltet-ist-designgrnde)
  - [Vergleich: markdown-preview Ansatz vs. Prozess-/Profil-basiertes Öffnen (dein Ansatz)](#vergleich-markdown-preview-ansatz-vs-prozess-profil-basiertes-ffnen-dein-ansatz)
  - [Vor- und Nachteile beider Strategien — Entscheidungskriterien](#vor-und-nachteile-beider-strategien-entscheidungskriterien)
  - [Praktische Empfehlungen / Hybrid-Strategie](#praktische-empfehlungen-hybrid-strategie)
  - [Beispiel: Minimaler Client-Handler (Browser-Seite)](#beispiel-minimaler-client-handler-browser-seite)
  - [Fazit (kurz): Welche Methode wählen?](#fazit-kurz-welche-methode-whlen)

---

markdown-preview.nvim implementiert eine server-seitige Architektur mit WebSocket-/Socket-Clients (im Browser). Beim Start wird ein lokal laufender HTTP-/WebSocket-Server eröffnet. Für das Öffnen einer Vorschauseite generiert der Server eine URL (z. B. `http://localhost:PORT/page/BUFNr`) und übergibt diese URL an Neovim-Seite, die wiederum entweder:

* eine konfigurierte Vim-Funktion (`g:mkdp_browserfunc`) aufruft, oder
* ein konfiguriertes Browserprogramm (`g:mkdp_browser`) verwendet, oder
* den Default-Mechanismus nutzt, um die URL im System-Browser zu öffnen.

Parallel verwaltet der Server eine Map `clients` pro Buffer-ID; jede Client-Verbindung (Browser-Tab) registriert sich beim Server. Der Server sendet bei Bedarf Events an diese Clients, z. B. `refresh_content`, `change_bufnr` oder `close_page`. Der Client-Code (JavaScript in der Vorschau-Seite) reagiert auf diese Events — z. B. führt ein `window.close()` aus, wenn ein `close_page`-Event empfangen wird.

Diese Architektur trennt Öffnen/Steuern (Neovim/Server) strikt von der eigentlichen Tab-Schließlogik (liegt im Browser-Client und ist kooperativ).

---

## Detaillierte Komponenten und Ablauf

* Server erzeugt URL und verwaltet Clients:

  * `clients[bufnr]` ist eine Liste von Client-Objekten für diesen Buffer.
  * Jeder Client hat Status (z. B. `connected`) und eine Möglichkeit, Events (`emit`) zu empfangen.
* Open-Logik im Server:

  * Prüft, ob „combine preview“ aktiviert ist; kann vorhandene Clients auf neuen Buffer umschalten (emit `change_bufnr`) statt neue Tabs zu öffnen.
  * Erkennt `mkdp_browserfunc`: wenn gesetzt, ruft der Server diese Vim-Funktion auf und übergibt die URL (ermöglicht volle Kontrolle dem Anwender/Plugin).
  * Sonst benutzt `mkdp_browser` (String) oder Default; ruft intern `openUrl(url, browser?)`.
* Close-Logik:

  * `closePage({ bufnr })` sendet an alle verbundenen Clients für diesen Buffer ein `close_page`-Event und entfernt deren Einträge.
  * `closeAllPages()` sendet `close_page` an alle Clients und leert die Map.
* Client-Seite (Browser):

  * Muss `close_page` behandeln (z. B. `window.close()`), damit die Seite sich selbst schließt.
  * Kann zusätzliche Logik enthalten (z. B. Polling, Reconnect, UI-Hinweise).

---

## Warum markdown-preview so gestaltet ist — Designgründe

1. Kooperative Kontrolle: Browser erlauben einem Tab normalerweise nur, sich selbst zu schließen. Indem das Plugin ein `close_page`-Event sendet, lässt man das Tab selbst die Schließaktion durchführen (so wie Browser es verlangen).
2. Flexibilität beim Öffnen: `mkdp_browserfunc` erlaubt Anwendern, beliebige Öffnstrategien zu nutzen (z. B. systemabhängige launcher, spezialflags oder Browser-Plugins).
3. Kombinierbarkeit: `combine_preview` erlaubt ein „single page, multiple buffers“ Verhalten — effizienter für den Nutzer.
4. Plattformunabhängigkeit: Das Server/Client-Pattern vermeidet Prozess-Management-Bugs auf verschiedenen OS; es verlässt sich auf Standard-Browser-APIs im Client.
5. Sicherheit und Nebenwirkungen: Keine Notwendigkeit, Browser-Profile oder neue Prozesse zu erzeugen, die das Nutzerprofil beeinflussen.

---

## Vergleich: markdown-preview Ansatz vs. Prozess-/Profil-basiertes Öffnen (dein Ansatz)

| Thema                     |                                     markdown-preview.nvim (Server + client events) | Prozess-/profilbasiertes Öffnen (z. B. spawn mit temp profile)                                            |
| ------------------------- | ---------------------------------------------------------------------------------: | --------------------------------------------------------------------------------------------------------- |
| Wer schließt das Tab?     |       Der Browser-Client schließt sich selbst auf `close_page`-Event (kooperativ). | Neovim/Plugin beendet externen Browser-Prozess (proaktiv), weil man die gestartete Instanz kontrolliert.  |
| Benötigte Rechte          |                       Keine speziellen Rechte; benutzt normale Browser-Funktionen. | Muss Prozesse starten/stoppen und temporäre Profile anlegen; OS-spezifische Pfade/Flags nötig.            |
| Zuverlässigkeit Schließen | Zuverlässig wenn Client das Event korrekt umsetzt; funktioniert unabhängig vom OS. | Zuverlässig zum Beenden der gestarteten Prozessinstanz; kann aber andere Browser-Tabs nicht beeinflussen. |
| Komplexität               |      Einfachere Integration: Server sendet Events, Client implementiert Verhalten. | Höher: cross-platform process resolution, temp profile management, cleanup.                               |
| Benutzerkonfiguration     |        `mkdp_browserfunc` und `mkdp_browser` bieten Hooks; Plugin bleibt flexibel. | Muss in Plugin konfigurierbar sein (welcher Browser, Flags, cleanup), sonst riskant.                      |
| Seiteneffekte             |               Keine; benutzt bestehende Browser-Instanz oder Benutzer-präferenzen. | Potentiell störend: neue Profile, Browser-Flags, evtl. mehrere Browser-Prozesse.                          |
| Edge-Cases                |  Nutzer hat JS deaktiviert oder Client nicht verbunden → `close_page` wirkt nicht. | Browser kann in System-Scope laufen; jobstop kann die richtige Prozessgruppe verfehlen.                   |

---

## Vor- und Nachteile beider Strategien — Entscheidungskriterien

* Wenn das Ziel ist, möglichst benign und kompatibel zu sein (keine temporären Profile, keine neuen Processes), ist der **server+client event**-Ansatz empfehlenswert. Er ist leichtgewichtig, plattformunabhängig und respektiert Nutzer-Browser-Policies.
* Wenn das Ziel ist, absolute Kontrolle über das Öffnen/Schließen zu haben (z. B. garantierte Schließung ohne Client-Kooperation), dann ist das **prozessbasierte** Vorgehen (eigenes Profil / app-mode / job tracking) in Erwägung zu ziehen — allerdings mit höherem Implementations- und Maintenance-Aufwand und Plattform-Fallen.

---

## Praktische Empfehlungen / Hybrid-Strategie

1. Primär: Implementiere serverseitige `open` + `close_page` Events und sorge dafür, dass die Client-HTML/JS `close_page` zuverlässig behandelt (inkl. Fallbacks). Das deckt die meisten Fälle ab und ist minimal invasiv.
2. Erweiternd: Biete optional eine process-based Öffnungsstrategie (konfigurierbar durch Anwender), die temporäre Profile / app-mode nutzt und den erzeugten Prozess-Handle speichert — nützlich für Benutzer, die explizit wollen, dass Neovim die Instanz beendet.
3. Konfigurations-API: Expose zwei Optionen, z. B. `open_strategy = "client"` (default) oder `"process"`, plus `browser_executable` / `browserfunc` / `stop_closes_browser` Flags.
4. Dokumentation: Erkläre klar die Implikationen beider Modi (privacy, side effects, platform caveats).
5. Fallback: Wenn `close_page` nicht wirkt (Client nicht verbunden), versuche nicht automatisch einen harten Prozess-Kill auf dem System-Browser — das könnte fremde Tabs schließen. Stattdessen nur bei expliziter User-Konfiguration.

---

## Beispiel: Minimaler Client-Handler (Browser-Seite)

```html
<script>
  // Client listens for server events via socket.io / ws and handles close_page.
  socket.on('close_page', () => {
    // Browser allows window.close() only for windows opened by script OR same origin.
    try {
      window.close();
    } catch (e) {
      // fallback: show message asking user to close tab
      console.warn('Preview closed on server; please close this tab.');
    }
  });
</script>
```

Dieser Client-Code ist die Voraussetzung dafür, dass `close_page` wirklich das Tab schließt.

---

## Fazit (kurz): Welche Methode wählen?

* Für die Mehrheit der Plugins ist der **server + client events**-Ansatz (wie markdown-preview.nvim) die beste Wahl: robust, plattformunabhängig, respektvoll gegenüber dem Nutzerprofil.
* Für Fälle, in denen das Plugin eine **deterministische, programmatische Garantie** zum Schließen einer separaten Browser-Instanz braucht (z. B. isolierte App-Fenster), ist das **prozessbasierte** Modell mit temporärem Profil eine Option — solange die Plugin-Konfiguration die Risiken und Plattformunterschiede transparent macht.

---
