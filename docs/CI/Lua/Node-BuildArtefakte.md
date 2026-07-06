# Node Build-Artefakte für Lua

## Table of content

  - [1. Node Build-Artefakte für Lua](#1-node-build-artefakte-fr-lua)
  - [2. Self-hosted Runner mit Node + Lua vorinstalliert](#2-self-hosted-runner-mit-node-lua-vorinstalliert)

---

## 1. Node Build-Artefakte für Lua

In deinem CI-Setup werden Node/TypeScript und Lua/Neovim getrennt getestet. Der Punkt „Node Build-Artefakte für Lua“ bezieht sich auf die Möglichkeit, dass Lua-Tests oder Lua-Checks **nur minimal von Node/TypeScript abhängig sind** – z. B. weil manche Lua-Tests Plugins oder Scripts laden, die bereits von Node gebaut wurden (z. B. Client-Bundles, JSON-Dateien, Markdown-Renderer).

**Details:**

* Dein Lua-Code (z. B. `lua/mdview/init.lua`) kann theoretisch Funktionen aufrufen, die Node generiert hat, oder Bundles lesen. Wenn diese Artefakte noch nicht gebaut sind, würden Lua-Tests fehlschlagen.
* Beispiel: Ein Lua-Modul lädt ein JSON-Bundle, das vorher mit Node/Vite gebuildet wurde. Dann muss der Node-Build **vorher** fertig sein, sonst fehlt die Datei.
* In der CI-Pipeline:

  ```yaml
  needs: node
  ```

  sorgt dafür, dass der Node-Job **abgeschlossen** ist, bevor der Lua-Job startet, sodass alle Artefakte vorhanden sind.

**Konsequenzen:**

* Wenn dein Lua-Code unabhängig von Node ist, könnte man Node- und Lua-Jobs theoretisch parallel starten.
* Sobald Lua aber auf Artefakte aus Node angewiesen ist, **muss Node vorher laufen**. Sonst fehlschlägt die CI.



