# Dies ist eine Testdatei

Für das Nvim-Plugin `mdview`.
saöldöäaslödläöasldäölas
## Powershell

**Unter PowerShell ist es möglich**, das Verhalten neuer Instanzen so zu steuern, dass sie den **aktuellen Arbeitsordner (Working Directory)** der aufrufenden Shell übernehmen. Allerdings hängt das **Wie** davon ab, wie genau du die neue Shell öffnest:

-

### **1. PowerShell-Fenster in aktuellem Pfad öffnen (manuell)**

Wenn du z. B. in einem Terminal in `C:\configs` bist und dort `powershell` eingibst, startet standardmäßig **eine neue PowerShell-Instanz im gleichen Verzeichnis**.

```powershell
PS C:\configs> powershell
PS C:\configs>
```

→ **Dieses Verhalten ist bereits so gewünscht.**

---

### **2. Neue PowerShell über GUI (z. B. Kontextmenü, Verknüpfung, Taskleiste)**

Diese starten meist im Standardverzeichnis (`C:\Users\<Name>`, `$HOME`), **nicht** im aktuellen Ordner deiner Shell.

#### Lösung: Manuell konfigurierte Verknüpfung

1. Rechtsklick auf die PowerShell-Verknüpfung (Desktop, Startmenü etc.)
2. Eigenschaften → Ziel:

   ```text
   C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoExit -Command "Set-Location 'C:\configs'"
   ```
3. Oder dynamisch über `%CD%` (funktioniert nur in `.cmd`- oder `.bat`-Skripten):

   ```bat
   powershell.exe -NoExit -Command "Set-Location '%CD%'"
   ```

---

### **3. Neue PowerShell-Instanz aus einem Skript heraus im gleichen Verzeichnis**

Du kannst z. B. aus einer PowerShell-Sitzung heraus eine **neue Instanz im aktuellen Pfad starten**:

```powershell
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$PWD'"
```

* `$PWD` ist der aktuelle Pfad der aufrufenden Shell.
* `-NoExit` verhindert, dass die Shell sofort schließt.

---

### **4. Für Windows Terminal (wt.exe)**

Wenn du `wt` verwendest, kannst du es so starten:

```powershell
wt -d .
```

Oder explizit:

```powershell
wt -d "$PWD"
```

---

### **5. Für VSCode (integrierte Shell)**

VSCode kann den Startpfad für das integrierte Terminal so setzen:

```jsonc
// settings.json
"terminal.integrated.cwd": "${fileDirname}"
```

---

### Fazit

| Methode                    | Pfad übernommen?    | Bemerkung                          |
| -------------------------- | ------------------- | ---------------------------------- |
| `powershell` im Terminal   | ✅                   | funktioniert wie erwartet          |
| `Start-Process powershell` | ✅                   | nur mit `-NoExit` + `Set-Location` |
| Kontextmenü/GUI            | ❌ (außer angepasst) | Startet meist im Home              |
| `wt -d "$PWD"`             | ✅                   | ideal für Windows Terminal         |

