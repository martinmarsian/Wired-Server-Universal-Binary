#!/bin/bash
# Wired Server — vollständiger Release-Workflow
# Signiert, notarisiert und stapelt automatisch.
#
# Verwendung:
#   ./release.sh                          # neuestes xcarchive auf dem Desktop
#   ./release.sh ~/Desktop/MeinOrdner    # bestimmten Archiv-Ordner angeben
#
# Vorher ausfüllen:
APPLE_ID="DEINE@EMAIL.DE"
APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"   # App-spezifisches Passwort von appleid.apple.com

# ── Feste Einstellungen ──────────────────────────────────────────────────────
TEAM_ID="VGB467J8DZ"
CERT="93E11861A3A1A192C0ACC1DD0E090EE4F8CBA40C"
SRCROOT="/Users/maertin/Documents/WiredServer"
ENT="$SRCROOT/Wired Server/Wired Server.entitlements"
HELPER_ENT="$SRCROOT/Wired Server Helper/Wired Server Helper.entitlements"
EXPORT="$HOME/Desktop/WiredServerExport"
ZIP="$EXPORT/WiredServer.zip"

set -euo pipefail

# ── Archiv suchen ─────────────────────────────────────────────────────────────
if [ $# -ge 1 ]; then
    ARCHIVE_DIR="$1"
else
    # Neuestes Verzeichnis auf dem Desktop nehmen, das ein .xcarchive enthält
    ARCHIVE_DIR=$(find "$HOME/Desktop" -maxdepth 1 -mindepth 1 -type d \
        -exec sh -c 'ls "$1"/*.xcarchive 2>/dev/null | head -1' _ {} \; \
        -print 2>/dev/null \
        | sort | tail -1)
fi

if [ -z "$ARCHIVE_DIR" ]; then
    echo "FEHLER: Kein Archiv-Ordner gefunden. Bitte Pfad als Argument angeben."
    exit 1
fi

XCARCHIVE=$(ls -1d "$ARCHIVE_DIR"/*.xcarchive 2>/dev/null | head -1)
if [ -z "$XCARCHIVE" ]; then
    echo "FEHLER: Kein .xcarchive in '$ARCHIVE_DIR' gefunden."
    exit 1
fi

SRC="$XCARCHIVE/Products/Applications/Wired Server.app"
APP="$EXPORT/Wired Server.app"

if [ ! -d "$SRC" ]; then
    echo "FEHLER: App nicht gefunden: $SRC"
    exit 1
fi

if [ "$APPLE_ID" = "DEINE@EMAIL.DE" ] || [ "$APP_PASSWORD" = "xxxx-xxxx-xxxx-xxxx" ]; then
    echo "FEHLER: Bitte APPLE_ID und APP_PASSWORD im Script eintragen."
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          Wired Server — Sign, Notarize & Staple              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Archiv:  $XCARCHIVE"
echo "Export:  $EXPORT"
echo ""

# ── 1. App aus Archiv kopieren ────────────────────────────────────────────────
echo "=== 1/9  App aus Archiv kopieren ==="
rm -rf "$EXPORT"
mkdir -p "$EXPORT"
cp -a "$SRC" "$APP"

# ── 2. wired-Binary (flache Mach-O-Datei) ────────────────────────────────────
echo "=== 2/9  wired binary signieren ==="
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Resources/Wired/wired"

# ── 3. Frameworks im Helper ──────────────────────────────────────────────────
echo "=== 3/9  Frameworks im Helper signieren ==="
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Resources/Wired Server Helper.app/Contents/Frameworks/WiredAppKit.framework"
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Resources/Wired Server Helper.app/Contents/Frameworks/WiredFoundation.framework"

# ── 4. Wired Server Helper.app ───────────────────────────────────────────────
echo "=== 4/9  Wired Server Helper signieren ==="
codesign --force --sign "$CERT" --options runtime \
    --entitlements "$HELPER_ENT" \
    "$APP/Contents/Resources/Wired Server Helper.app"

# ── 5. Sparkle fileop (get-task-allow entfernen) + Autoupdate.app ────────────
echo "=== 5/9  Sparkle fileop signieren (get-task-allow entfernen) ==="
EMPTY_ENT=$(mktemp /tmp/empty-ent.XXXXXX.plist)
printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>' > "$EMPTY_ENT"
codesign --force --sign "$CERT" --options runtime \
    --entitlements "$EMPTY_ENT" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/fileop"
rm -f "$EMPTY_ENT"
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app"

# ── 6. Haupt-Frameworks + Sparkle ────────────────────────────────────────────
echo "=== 6/9  Haupt-Frameworks signieren ==="
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Frameworks/WiredAppKit.framework"
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Frameworks/WiredFoundation.framework"
codesign --force --sign "$CERT" --options runtime \
    "$APP/Contents/Frameworks/Sparkle.framework"

# ── 7. Haupt-App ─────────────────────────────────────────────────────────────
echo "=== 7/9  Haupt-App signieren ==="
codesign --force --sign "$CERT" --options runtime \
    --entitlements "$ENT" \
    "$APP"

# ── 8. Signatur prüfen ────────────────────────────────────────────────────────
echo "=== 8/9  Signatur prüfen ==="
codesign --verify --deep --strict "$APP" && echo "  Signatur OK"
spctl --assess --type execute --verbose "$APP" 2>&1 | grep -E "accepted|rejected|source" || true

# ── 9. Notarisieren ─────────────────────────────────────────────────────────
echo ""
echo "=== 9/9  Zip erstellen und bei Apple notarisieren ==="
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "  Zip: $ZIP"
echo ""

NOTARY_OUTPUT=$(xcrun notarytool submit "$ZIP" \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait 2>&1)

echo "$NOTARY_OUTPUT"

if echo "$NOTARY_OUTPUT" | grep -q "status: Accepted"; then
    echo ""
    echo "=== Notarisierung erfolgreich — Ticket einbetten ==="
    xcrun stapler staple "$APP"
    echo ""
    spctl --assess --type execute --verbose "$APP" 2>&1
    rm -f "$ZIP"
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Fertig! Wired Server.app ist signiert, notarisiert und     ║"
    echo "║  gestapelt. Bereit zur Verteilung:                          ║"
    echo "║  $EXPORT"
    echo "╚══════════════════════════════════════════════════════════════╝"
else
    SUBMISSION_ID=$(echo "$NOTARY_OUTPUT" | grep -oE '[0-9a-f-]{36}' | head -1)
    echo ""
    echo "FEHLER: Notarisierung fehlgeschlagen."
    if [ -n "$SUBMISSION_ID" ]; then
        echo ""
        echo "Details abrufen:"
        echo "  xcrun notarytool log $SUBMISSION_ID \\"
        echo "    --apple-id \"$APPLE_ID\" --password \"$APP_PASSWORD\" --team-id $TEAM_ID"
    fi
    exit 1
fi
