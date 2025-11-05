# Test Harness für Line-Diff-Funktion in mdview.nvim

Dieses kleine Markdown-Dokument beschreibt, wie man das `diff_harness.lua` ausführt, um die Line-Diff-Funktion (`mdview.util.diff`) zu testen und die Ergebnisse zu verifizieren.

---

## 1. Voraussetzungen

* Neovim 0.9+ (für `vim.loop` / luv)
* Lua 5.1+ (LuaJIT)
* Das `mdview.nvim` Repository ausgecheckt und lauffähig
* Die Module:

  * `mdview.util.diff` (Line-Diff Funktion)
  * `mdview.util.apply` (Hilfsfunktion `apply_patch` zum Testen der Patches)

---

## 2. Ziel

* Verifizieren, dass die Line-Diff-Funktion korrekte Patch-Informationen liefert.
* Benchmark der Laufzeit für verschiedene Szenarien.
* Testen der Konsistenz, indem die Patches auf den ursprünglichen Inhalt angewendet werden und das Ergebnis mit dem neuen Inhalt verglichen wird.

---

## 3. Test-Szenarien

Im Harness sind mehrere Szenarien vordefiniert:

| Szenario               | Beschreibung                                      |
| ---------------------- | ------------------------------------------------- |
| `empty_to_small`       | Leere Datei → kleine Datei (10 Zeilen)            |
| `no_change`            | Keine Änderung zwischen `old` und `new`           |
| `single_insert_middle` | Eine Zeile wird mittig eingefügt                  |
| `single_delete_middle` | Eine Zeile wird mittig gelöscht                   |
| `replace_block`        | Block von Zeilen wird ersetzt                     |
| `large_append`         | Anhängen vieler Zeilen am Ende                    |
| `many_small_changes`   | Viele kleine Änderungen verteilt über 1000 Zeilen |

---

## 4. Ausführung

1. Öffne Neovim im Root-Verzeichnis von `mdview.nvim`.
2. Lade die Datei `diff_harness.lua` über `:luafile`:

```vim
:luafile lua/mdview/test/diff_harness.lua
```

3. Alternativ direkt aus Lua starten:

```bash
nvim --headless -c "luafile lua/mdview/test/diff_harness.lua" -c "qa"
```

4. Die Konsole zeigt für jedes Szenario:

```
[test] <Szenario>: ok=true diffs=<Anzahl> time_ms=<Millisekunden> changed=<Zeilen> ratio=<Verhältnis>
```

5. Am Ende eine Zusammenfassung:

```
[summary] cases=<Anzahl> total_time_ms=<Millisekunden>
```

---

## 5. Analyse der Ergebnisse

* `ok=true`: Der Patch hat das `old_lines` korrekt zu `new_lines` transformiert.
* `diffs=<Anzahl>`: Anzahl der Patch-Operationen.
* `time_ms`: Dauer der Berechnung in Millisekunden.
* `changed`: Anzahl der geänderten Zeilen.
* `ratio`: Verhältnis geänderter Zeilen zu Gesamtzeilen (0–1).

---

## 6. Hinweise

* Bei Fehlern werden Lua-Errors mit Details zur gescheiterten Operation ausgegeben.
* Um die Diff-Funktion zu verbessern, kann man alternative Algorithmen wie LCS (Myers) verwenden.
* Die Funktion `apply_patch` muss korrekt implementiert sein, um die Patches auf `old_lines` anzuwenden.

---

## 7. Debugging

* Aktivierung von detailliertem Logging in `diff.lua`:

```lua
print(vim.inspect(diffs))
```

* Prüfen, ob `patched` exakt dem neuen Inhalt entspricht:

```lua
for i, line in ipairs(new_lines) do
  assert(line == patched[i], "Line mismatch at "..i)
end
```

---

## 8. Zusammenfassung

Mit `diff_harness.lua` lassen sich:

* Funktionalität und Korrektheit der Line-Diff-Funktion prüfen.
* Performance messen und Optimierungen ableiten.
* Regressionen erkennen, wenn sich die Diff-Logik ändert.

---

## Literatur

* Lua `vim.loop` / luv Dokumentation
* EmmyLua Typannotation für Tables und Arrays
* Myers diff Algorithmus als Referenzimplementierung

