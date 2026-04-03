#!/bin/bash
# build.sh — Bump version, build ZIP, commit and push
# Usage: bash build.sh [version]
#        bash build.sh 1.02       (explicit)
#        bash build.sh            (auto-bump +0.01)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

NEW_VERSION="$1"
MAIN_SCRIPT="src/gui_editor.ms"

# --- Auto-bump ---
if [ -z "$NEW_VERSION" ]; then
    CURRENT=$(grep 'TOOLS_VERSION = "' "$MAIN_SCRIPT" | grep -o '"[0-9.]*"' | tr -d '"')
    if [ -z "$CURRENT" ]; then
        echo "ERROR: Could not read current version from $MAIN_SCRIPT"
        exit 1
    fi
    DOTS=$(echo "$CURRENT" | tr -cd '.' | wc -c)
    if [ "$DOTS" -ge 2 ]; then
        BASE=$(echo "$CURRENT" | cut -d. -f1-2)
        PATCH=$(echo "$CURRENT" | cut -d. -f3)
        NEW_VERSION="${BASE}.$(printf '%02d' $((10#$PATCH + 1)))"
    else
        NEW_VERSION=$(awk "BEGIN { printf \"%.2f\", $CURRENT + 0.01 }")
    fi
fi

echo "=== Building MAXScript GUI Editor v${NEW_VERSION} ==="

# --- 1. Set version in all source files ---
for f in src/gui_editor.ms deploy/install.ms; do
    [ -f "$f" ] && sed -i "s/TOOLS_VERSION = \"[^\"]*\"/TOOLS_VERSION = \"${NEW_VERSION}\"/" "$f"
done

# --- 2. Verify ---
echo "--- Version check ---"
for f in src/gui_editor.ms deploy/install.ms; do
    [ -f "$f" ] || continue
    FOUND=$(grep "TOOLS_VERSION = \"${NEW_VERSION}\"" "$f" || true)
    if [ -n "$FOUND" ]; then
        echo "OK: $f -> v${NEW_VERSION}"
    else
        echo "ERROR: Version mismatch in $f"
        exit 1
    fi
done

# --- 3. Build MAXScript ZIP ---
ZIP_NAME="maxscript-gui-editor-${NEW_VERSION}.zip"
STAGING=$(mktemp -d)
mkdir -p "$STAGING/src/lib"

cp deploy/install.ms          "$STAGING/installer-${NEW_VERSION}.ms"
cp src/gui_editor.ms          "$STAGING/src/"
[ -f src/lib/gui_lib.ms ] && cp src/lib/gui_lib.ms "$STAGING/src/lib/"
for txt in docs/*.txt; do [ -f "$txt" ] && cp "$txt" "$STAGING/"; done

(cd "$STAGING" && zip -r "${SCRIPT_DIR}/${ZIP_NAME}" . -x "*.DS_Store")
rm -rf "$STAGING"
echo "Built: ${ZIP_NAME}"

# --- 3b. Build Python App ZIP ---
PY_ZIP_NAME="maxscript-gui-editor-python-${NEW_VERSION}.zip"
PY_STAGING=$(mktemp -d)
mkdir -p "$PY_STAGING/app"

cp -r python_app/app/       "$PY_STAGING/app/"
cp    python_app/main.py             "$PY_STAGING/"
cp    python_app/requirements.txt    "$PY_STAGING/"
cp    python_app/install.bat         "$PY_STAGING/"
cp    python_app/install.sh          "$PY_STAGING/"
cp    python_app/max_bridge_listener.ms "$PY_STAGING/"
cp    python_app/maxscript_gui_editor.spec "$PY_STAGING/"
for txt in docs/*.txt; do [ -f "$txt" ] && cp "$txt" "$PY_STAGING/"; done
[ -f README.md ] && cp README.md "$PY_STAGING/"

# Remove __pycache__ from ZIP
(cd "$PY_STAGING" && find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null; \
 zip -r "${SCRIPT_DIR}/${PY_ZIP_NAME}" . -x "*.DS_Store" -x "*/__pycache__/*" -x "*/.pyc")
rm -rf "$PY_STAGING"
echo "Built: ${PY_ZIP_NAME}"

# --- 4. Remove old ZIPs ---
for old in "${SCRIPT_DIR}"/maxscript-gui-editor-*.zip; do
    [ "$old" = "${SCRIPT_DIR}/${ZIP_NAME}" ] && continue
    [ "$old" = "${SCRIPT_DIR}/${PY_ZIP_NAME}" ] && continue
    [ -f "$old" ] || continue
    git rm --cached "$old" 2>/dev/null || true
    rm -f "$old"
    echo "Removed old ZIP: $(basename $old)"
done

# --- 5. Commit and push ---
git add -A
git commit -m "$(cat <<EOF
v${NEW_VERSION}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"

bash push.sh
echo "=== Done: v${NEW_VERSION} — ${ZIP_NAME} ==="
