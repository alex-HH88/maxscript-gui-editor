# MAXScript GUI Editor

> Visual Rollout & MacroScript Designer for Autodesk 3ds Max

A tool for visually designing 3ds Max rollout dialogs and generating clean MAXScript or MacroScript code — available in two editions:

| Edition | Description |
|---|---|
| **MAXScript Edition** | Runs directly inside 3ds Max as a MacroScript (no Python required) |
| **Python Standalone** | Full desktop app (PySide6) with drag & drop, WYSIWYG canvas, and live TCP bridge to 3ds Max |

---

## Downloads

| File | Contents |
|---|---|
| `maxscript-gui-editor-<version>.zip` | MAXScript Edition — installer + source |
| `maxscript-gui-editor-python-<version>.zip` | Python Standalone Edition + Bridge + Installers |

---

## MAXScript Edition

### Requirements
- 3ds Max 2022 or newer

### Installation
1. Extract the ZIP.
2. Drag `installer-<version>.ms` onto the 3ds Max viewport **or** open it via `Scripting → Run Script`.
3. The installer copies the tool to your User Scripts folder and registers it under `Customize → Toolbars → Category: Tools`.

### Features
- Add, delete, and reorder 23 control types (button, spinner, combobox, colorpicker, …)
- Edit all control properties (position, size, label, range, items, …)
- Event handler editor with per-event code blocks
- 20-level undo / redo
- Save / load layouts as `.dat` files
- Generate Rollout-only or full MacroScript output
- Live preview via `rolloutCreator`

---

## Python Standalone Edition

### Requirements
- Python 3.9+
- PySide6 (installed automatically by the installer)

### Quick Start
```bash
# Windows
double-click install.bat

# Linux / macOS
bash install.sh

# Manual
pip install PySide6
python main.py
```

### Features
- **Drag & Drop** from control palette directly onto the WYSIWYG canvas
- **Grid-snap** (4 px) while dragging
- **WYSIWYG preview** — controls rendered as coloured Qt widgets
- **50-level undo / redo** (`Ctrl+Z` / `Ctrl+Y`)
- **Save / Load** layouts as readable JSON
- **Generate Code** — Rollout or full MacroScript (`F5`)
- **Copy to Clipboard** (`Ctrl+Shift+C`)
- **Send to Max** — live TCP bridge to a running 3ds Max instance (`F6`)
- Properties panel with 4 tabs: Control · Events · Rollout · MacroScript
- Event handler editor with per-event code blocks

### TCP Bridge to 3ds Max

The Python app can send generated code directly into a running 3ds Max session:

**Step 1 — Start the listener in 3ds Max:**
```
Scripting → Run Script → max_bridge_listener.ms
```
The MAXScript Listener prints:
```
=== MAXScript Bridge Listener started on port 27120 ===
```

**Step 2 — Connect from the Python app:**
- Menu: `Code → Bridge Settings…` — set host/port (default: `127.0.0.1:27120`)
- Click **"⬤ Ping"** to verify the connection
- Click **"▶ Send to Max"** or press `F6`

The code is executed in 3ds Max within ~50 ms.

**Stop the listener:**
```maxscript
stopBridgeListener()
```

### Build standalone EXE (Windows, no Python needed)
```bash
pip install pyinstaller
pyinstaller maxscript_gui_editor.spec
# → dist/MAXScriptGUIEditor/MAXScriptGUIEditor.exe
```

---

## Project Structure

```
src/
  gui_editor.ms               MAXScript Edition — main script
  lib/
    gui_lib.ms                Helper functions (optional)
deploy/
  install.ms                  MAXScript installer
docs/
  INSTALL_DE.txt              German install guide
  INSTALL_EN.txt              English install guide
python_app/
  main.py                     Python app entry point
  requirements.txt            PySide6
  install.bat                 Windows installer (venv + shortcut)
  install.sh                  Linux / macOS installer
  maxscript_gui_editor.spec   PyInstaller spec (standalone EXE)
  max_bridge_listener.ms      MAXScript TCP listener for 3ds Max
  app/
    models.py                 Data models (JSON-serializable dataclasses)
    code_generator.py         MAXScript code generator
    canvas.py                 WYSIWYG QGraphicsView canvas
    properties_panel.py       Dynamic properties panel (PySide6)
    bridge.py                 TCP bridge client
    main_window.py            Main application window
build.sh                      Build script — bumps version, builds ZIPs, pushes
push.sh                       GitHub push helper
```

---

## Supported Control Types

`button` · `checkbutton` · `checkbox` · `colorpicker` · `combobox` · `edittext` · `groupbox` · `imgTag` · `label` · `listbox` · `mapbutton` · `materialbutton` · `multilistbox` · `pickbutton` · `progressbar` · `radiobuttons` · `slider` · `spinner` · `timer` · `bitmap` · `curvecontrol` · `angle` · `hyperlink`

---

## Improvements over DW Interactive Rollout Builder v1.4

- Fixed 3 known bugs (deleteItem `.labels` → `.items`, `col` → `val`, undefined `rdo` reference)
- Working event handler editor (DW had a non-functional stub)
- MacroScript output mode (new)
- Python Standalone with true drag & drop WYSIWYG canvas (new)
- Live TCP bridge to 3ds Max (new)
- JSON save format (portable, diff-friendly)
- 50-level undo/redo vs. DW's none

---

## License

MIT — free for personal and commercial use.

## Author

[alex-HH88](https://github.com/alex-HH88)
