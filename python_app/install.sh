#!/usr/bin/env bash
# MAXScript GUI Editor — Linux / macOS Installer
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MAXScript GUI Editor"
INSTALL_DIR="$HOME/.local/share/maxscript-gui-editor"

echo ""
echo "  ============================================="
echo "   $APP_NAME — Installer"
echo "  ============================================="
echo ""

# --- Python check ---
PYTHON=""
for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null; then
        VER=$("$cmd" -c "import sys; print(sys.version_info>=(3,9))" 2>/dev/null)
        if [ "$VER" = "True" ]; then
            PYTHON="$cmd"
            break
        fi
    fi
done

if [ -z "$PYTHON" ]; then
    echo "[ERROR] Python 3.9+ not found."
    echo "        Install via your package manager:"
    echo "          Ubuntu/Debian : sudo apt install python3 python3-venv"
    echo "          macOS         : brew install python3"
    exit 1
fi
echo "  [OK] Python: $($PYTHON --version)"

# --- Create install dir ---
mkdir -p "$INSTALL_DIR"
echo "  Install directory: $INSTALL_DIR"

# --- Copy files ---
echo "  Copying application files..."
cp -r "$SCRIPT_DIR/app"                    "$INSTALL_DIR/"
cp    "$SCRIPT_DIR/main.py"                "$INSTALL_DIR/"
cp    "$SCRIPT_DIR/requirements.txt"       "$INSTALL_DIR/"
[ -f "$SCRIPT_DIR/max_bridge_listener.ms" ] && \
    cp "$SCRIPT_DIR/max_bridge_listener.ms" "$INSTALL_DIR/"
echo "  [OK] Files copied."

# --- Virtual environment ---
VENV="$INSTALL_DIR/venv"
if [ ! -f "$VENV/bin/activate" ]; then
    echo "  Creating virtual environment..."
    $PYTHON -m venv "$VENV"
    echo "  [OK] venv created."
fi

# --- Install PySide6 ---
echo "  Installing PySide6 (may take a minute)..."
"$VENV/bin/pip" install --upgrade pip -q
"$VENV/bin/pip" install -r "$INSTALL_DIR/requirements.txt" -q
echo "  [OK] PySide6 installed."

# --- Launcher script ---
LAUNCHER="$HOME/.local/bin/maxscript-gui-editor"
mkdir -p "$HOME/.local/bin"
cat > "$LAUNCHER" << EOF
#!/usr/bin/env bash
cd "$INSTALL_DIR"
exec "$VENV/bin/python" main.py "\$@"
EOF
chmod +x "$LAUNCHER"
echo "  [OK] Launcher: $LAUNCHER"

# --- .desktop file (Linux only) ---
if [[ "$OSTYPE" == "linux"* ]]; then
    DESK_DIR="$HOME/.local/share/applications"
    mkdir -p "$DESK_DIR"
    cat > "$DESK_DIR/maxscript-gui-editor.desktop" << EOF
[Desktop Entry]
Name=MAXScript GUI Editor
Comment=Visual Rollout Designer for 3ds Max
Exec=$LAUNCHER
Terminal=false
Type=Application
Categories=Development;
EOF
    echo "  [OK] Desktop entry created."
fi

# --- macOS app launcher ---
if [[ "$OSTYPE" == "darwin"* ]]; then
    APP_BUNDLE="$HOME/Applications/MAXScript GUI Editor.app"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    cat > "$APP_BUNDLE/Contents/MacOS/launch" << EOF
#!/usr/bin/env bash
cd "$INSTALL_DIR"
exec "$VENV/bin/python" main.py
EOF
    chmod +x "$APP_BUNDLE/Contents/MacOS/launch"
    cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MAXScript GUI Editor</string>
  <key>CFBundleExecutable</key><string>launch</string>
  <key>CFBundleIdentifier</key><string>com.alex-hh88.maxscript-gui-editor</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
    echo "  [OK] macOS app bundle: $APP_BUNDLE"
fi

echo ""
echo "  ============================================="
echo "   Installation complete!"
echo ""
echo "   Launch:  maxscript-gui-editor"
[ -f "$DESK_DIR/maxscript-gui-editor.desktop" ] && \
    echo "            or via Applications menu"
[ -d "$HOME/Applications/MAXScript GUI Editor.app" ] && \
    echo "            or via ~/Applications"
echo ""
echo "   3ds Max bridge:"
echo "     Scripting > Run Script >"
echo "     $INSTALL_DIR/max_bridge_listener.ms"
echo "  ============================================="
echo ""
