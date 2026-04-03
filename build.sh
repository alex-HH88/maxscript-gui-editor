#!/bin/bash
# build.sh — Bump version, build Python ZIP, commit and push
# Usage: bash build.sh [version]
#        bash build.sh 1.10       (explicit)
#        bash build.sh            (auto-bump +0.01)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

NEW_VERSION="$1"
VERSION_FILE="python_app/app/models.py"

# --- Auto-bump from models.py ---
if [ -z "$NEW_VERSION" ]; then
    CURRENT=$(grep 'APP_VERSION' "$VERSION_FILE" 2>/dev/null | grep -o '"[0-9.]*"' | tr -d '"')
    if [ -z "$CURRENT" ]; then
        # fallback: read from src/gui_editor.ms
        CURRENT=$(grep 'TOOLS_VERSION = "' src/gui_editor.ms | grep -o '"[0-9.]*"' | tr -d '"')
    fi
    if [ -z "$CURRENT" ]; then
        echo "ERROR: Could not read current version."
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

echo "=== Building MAXScript GUI Editor (Python Edition) v${NEW_VERSION} ==="

# --- 1. Set version in Python app ---
if grep -q 'APP_VERSION' "$VERSION_FILE"; then
    sed -i "s/APP_VERSION = \"[^\"]*\"/APP_VERSION = \"${NEW_VERSION}\"/" "$VERSION_FILE"
else
    sed -i "1s/^/APP_VERSION = \"${NEW_VERSION}\"\n/" "$VERSION_FILE"
fi

# keep MAXScript files in sync (archived, not actively built)
for f in src/gui_editor.ms deploy/install.ms; do
    [ -f "$f" ] && sed -i "s/TOOLS_VERSION = \"[^\"]*\"/TOOLS_VERSION = \"${NEW_VERSION}\"/" "$f"
done

# --- 2. Verify ---
echo "--- Version check ---"
FOUND=$(grep "APP_VERSION = \"${NEW_VERSION}\"" "$VERSION_FILE" || true)
if [ -n "$FOUND" ]; then
    echo "OK: $VERSION_FILE -> v${NEW_VERSION}"
else
    echo "ERROR: Version not updated in $VERSION_FILE"
    exit 1
fi

# --- 3. Build Python ZIP ---
PY_ZIP_NAME="maxscript-gui-editor-python-${NEW_VERSION}.zip"
PY_STAGING=$(mktemp -d)

cp -r python_app/app                        "$PY_STAGING/app"
cp    python_app/main.py                    "$PY_STAGING/"
cp    python_app/requirements.txt           "$PY_STAGING/"
cp    python_app/install.bat                "$PY_STAGING/"
cp    python_app/install.sh                 "$PY_STAGING/"
cp    python_app/max_bridge_listener.ms     "$PY_STAGING/"
cp    python_app/maxscript_gui_editor.spec  "$PY_STAGING/"
for txt in docs/python/*.txt; do [ -f "$txt" ] && cp "$txt" "$PY_STAGING/"; done
[ -f README.md ] && cp README.md "$PY_STAGING/"

(cd "$PY_STAGING" && find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null; \
 zip -r "${SCRIPT_DIR}/${PY_ZIP_NAME}" . -x "*.DS_Store" -x "*/__pycache__/*" -x "*.pyc")
rm -rf "$PY_STAGING"
echo "Built: ${PY_ZIP_NAME}"

# --- 4. Remove old Python ZIPs ---
for old in "${SCRIPT_DIR}"/maxscript-gui-editor-python-*.zip; do
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
echo "=== Done: v${NEW_VERSION} — ${PY_ZIP_NAME} ==="
