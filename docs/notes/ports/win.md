Das Verhalten deutet darauf hin, dass das, was `netstat` zeigt, **keine normalen aktiven Prozesse** sind, die man einfach mit `Stop-Process` killen kann, sondern Kernel-verwaltete TCP-Zustände (z. B. `TIME_WAIT` / „WARTEND“) oder Verbindungen, bei denen `OwningProcess` nicht aufgelöst wird. Kurz: **man kann nicht „alle Einträge“ töten**, weil viele gar keinen Prozess haben, der dafür verantwortlich ist.

Was jetzt systematisch zu prüfen und zu tun ist — Schritt für Schritt (Windows, PowerShell; als Administrator ausführen wenn möglich):

1. Prüfen, ob es überhaupt einen *Listener* (ein Prozess, der auf Port 43219 lauscht)

```powershell
Get-NetTCPConnection -LocalPort 43219 -State Listen | Format-Table LocalAddress,LocalPort,State,OwningProcess -AutoSize
```

Wenn diese Abfrage nichts zurückgibt, existiert aktuell kein Prozess, der aktiv auf 43219 lauscht. Die `WARTEND`-Einträge sind dann wahrscheinlich clientseitige Sockets in TIME_WAIT / CLOSE_WAIT etc.

2. Alle Verbindungen *zu* diesem Remote-Port auflisten (zeigt die lokalen ephemeral-Ports und OwningProcess)

```powershell
Get-NetTCPConnection | Where-Object { $_.RemotePort -eq 43219 } | Format-Table LocalAddress,LocalPort,RemoteAddress,RemotePort,State,OwningProcess -AutoSize
```

oder äquivalent (kompakter)

```powershell
Get-NetTCPConnection | Where-Object RemotePort -eq 43219 | Select LocalPort,State,OwningProcess | Sort-Object LocalPort -Unique
```

* Wenn `OwningProcess` ≠ 0 für einige Zeilen: das sind echte Prozesse, die man beenden kann.
* Wenn `OwningProcess` == 0 für alle Zeilen: das sind Kernel-/TCP-states (TIME_WAIT o.ä.) oder nicht auflösbare PIDs — die lassen sich nicht per `Stop-Process` töten.

3. Prozesse beenden (nur für Einträge mit OwningProcess ≠ 0)

```powershell
Get-NetTCPConnection -RemotePort 43219 -ErrorAction SilentlyContinue |
  Where-Object { $_.OwningProcess -ne 0 } |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
```

Das killt die tatsächlichen Prozesse, wenn welche vorhanden sind.

4. Wenn alle Einträge `OwningProcess == 0` bleiben

* Das heißt: **TIME_WAIT / WARTEND**-Zustände, die vom TCP-Stack verwaltet werden.
* Diese verschwinden automatisch nach einiger Zeit (Windows default ~240s). Man kann sie nicht per `taskkill` entfernen.

Optionen in diesem Fall:

* Warte ab (am sichersten). TIME_WAIT ist normal und harmlos.
* Neustart des Systems oder Neustart des Netzwerktreibers (bringt sofortige Bereinigung).
* Registry-Änderung zur Verkürzung von TIME_WAIT (riskant, erfordert Reboot):

  ```powershell
  # Beispiel: setze TcpTimedWaitDelay auf 30 Sekunden (WERT in Sekunden; 30 ist beispielhaft)
  New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "TcpTimedWaitDelay" -PropertyType DWord -Value 30 -Force
  ```

  Hinweis: Änderung erfordert Reboot; nicht empfohlen auf Produktivmaschinen ohne Verständnis der Nebenwirkungen.

5. Wenn ein Listener existiert, aber OwningProcess nicht stimmt / 0

* Möglicherweise fehlen Administratorrechte. Starte PowerShell als Administrator und wiederhole Punkt (1–3).
* Tools wie TCPView (Sysinternals) oder Process Explorer können besser auflösen und anzeigen, welche Prozesse Sockets halten:

  * Download TCPView: [https://docs.microsoft.com/sysinternals/downloads/tcpview](https://docs.microsoft.com/sysinternals/downloads/tcpview)
  * TCPView zeigt pro Verbindung PID + Prozessname; dort kann man per UI Prozesse beenden.

6. Kurzbefehle zum schnellen Test / Cleanup (als Admin)

* Suche Listener / Prozesse:

```powershell
# Listener anzeigen
Get-NetTCPConnection -LocalPort 43219 -State Listen

# Alle Verbindungen zu Port 43219 inkl. OwningProcess
Get-NetTCPConnection | Where-Object { $_.RemotePort -eq 43219 -or $_.LocalPort -eq 43219 } | Format-Table LocalPort,RemotePort,State,OwningProcess -AutoSize
```

* Kill-Befehl (kill only non-zero owning processes):

```powershell
Get-NetTCPConnection -LocalPort 43219 -ErrorAction SilentlyContinue |
  Where-Object { $_.OwningProcess -ne 0 } |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
```

7. Diagnostik, wenn’s weiterhin hängt

* Starte PowerShell als Administrator und führe:

```powershell
# prüfe, ob es ein listening process gibt
Get-NetTCPConnection -LocalPort 43219 -State Listen

# prüfe Prozessliste für node (häufiger culprit)
Get-Process -Name node -ErrorAction SilentlyContinue | Format-Table Id,ProcessName,StartTime -AutoSize

# zeige alle Verbindungen mit PID und Prozessname via netstat + tasklist
netstat -ano | findstr 43219
# dann für eine gefundene PID:
tasklist /FI "PID eq <PID>"
```

* Wenn `netstat` immer noch viele `WARTEND`-Zeilen zeigt, aber `Get-NetTCPConnection` keine OwningProcess liefert, ist das TIME_WAIT, und nichts weiter zu tun außer abwarten oder reboot.

Zusammenfassung / Empfehlung konkret für dein Listing:

* Führe die obigen PowerShell-Abfragen (als Admin) aus.
* Wenn `OwningProcess` für Einträge ≠ 0 ist: killen mit dem Einzeiler (Stop-Process).
* Wenn `OwningProcess` für alle `0` ist: das sind TIME_WAIT/WARTEND-Verbindungen → warten oder reboot; alternativ Registry-Änderung (TcpTimedWaitDelay) mit Bedacht.

----

## Es liegt ein einzelner aktiver Listener auf Port 43219 vorhanden

Prozess:

```sh
node.exe (PID 15688)
```

Alle anderen Einträge sind TIME_WAIT (OwningProcess = 0) und verschwinden automatisch.
Gelöst wird das Problem, indem man **nur diesen einen Prozess beendet**.

PowerShell als Administrator:

```
Stop-Process -Id 15688 -Force
```

oder generisch, falls die PID variiert:

```
Get-NetTCPConnection -LocalPort 43219 -State Listen |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id $_ -Force }
```

Damit wird der Listener geschlossen. Die TIME_WAIT-Einträge sind danach nach kurzer Zeit weg.

---
