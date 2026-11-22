#!/usr/bin/env bash
set -euo pipefail

# Package an already-built debug executable without replacing the installed app.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# .build/debug links to the debug products on every SwiftPM build layout.
DEBUG_DIR="$ROOT_DIR/.build/debug"
test -x "$DEBUG_DIR/Upkeep"
# Remove fixture bundles from earlier runs (older than an hour, so open ones stay).
find /private/tmp -maxdepth 1 -name 'upkeep-ui-fixture.*' -mmin +60 -exec rm -rf {} + 2>/dev/null || true
# Each fixture bundle gets its own bundle ID, and macOS saves its window state in a
# preferences file named after it. Remove those along with the old bundles.
find "$HOME/Library/Preferences" -maxdepth 1 -name 'test.upkeep.ui-fixture.*.plist' -mmin +60 -delete 2>/dev/null || true
FIXTURE_DIR="$(mktemp -d /private/tmp/upkeep-ui-fixture.XXXXXX)"
APP_BUNDLE="$FIXTURE_DIR/Upkeep UI Fixture.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$DEBUG_DIR/Upkeep" "$APP_BUNDLE/Contents/MacOS/UpkeepUIFixture"
if test -d "$DEBUG_DIR/Upkeep_Upkeep.bundle"; then
    /usr/bin/ditto "$DEBUG_DIR/Upkeep_Upkeep.bundle" "$APP_BUNDLE/Contents/Resources/Upkeep_Upkeep.bundle"
fi
python3 - "$APP_BUNDLE/Contents/Info.plist" <<'PY'
import plistlib
import sys
import uuid
with open(sys.argv[1], "wb") as destination:
    plistlib.dump({
        "CFBundleIdentifier": "test.upkeep.ui-fixture." + uuid.uuid4().hex,
        "CFBundleName": "Upkeep UI Fixture",
        "CFBundleDisplayName": "Upkeep UI Fixture",
        "CFBundleExecutable": "UpkeepUIFixture",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "CFBundleShortVersionString": "1.0",
        "LSMinimumSystemVersion": "14.0",
        "NSHighResolutionCapable": True,
    }, destination)
PY
/usr/bin/codesign --force --sign - "$APP_BUNDLE"
printf '%s\n' "$APP_BUNDLE"
