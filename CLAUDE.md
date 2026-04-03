# CLAUDE.md — MAXScript GUI Editor

## Projekt

Allgemeiner UI-Builder für 3ds Max Dialoge — MAXScript Rollout Designer.
Ermöglicht das visuelle Erstellen und Bearbeiten von MAXScript Rollout-Layouts.

GitHub: `alex-HH88/maxscript-gui-editor`

---

## Struktur

```
src/
  gui_editor.ms         # Hauptskript
  lib/
    gui_lib.ms          # Hilfsfunktionen
deploy/
  install.ms            # Installer
docs/
  INSTALL_DE.txt
  INSTALL_EN.txt
tests/
build.sh                # bash build.sh [version]
push.sh                 # GitHub push (Token aus .env)
.env                    # nicht im Repo
```

---

## Regeln

Siehe Memory: `feedback_maxscript.md` und `feedback_build_workflow.md`

### Kurzfassung
- Version: `global TOOLS_VERSION = "1.00"` oben in jedem Skript
- Build: immer `bash build.sh` — nie manuell
- Toolbar: **"Tools"** (projektübergreifend)
- MacroScript-Kategorie: `"Tools"`
- Kompatibilität: 3ds Max 2022+ (`(maxVersion())[1]/1000 >= 27` = 2025+)
- Icons: `_16i/_16a/_24i/_24a.bmp` alle 4 erzeugen
- copyFile: erst deleteFile, dann copyFile, dann verifizieren
