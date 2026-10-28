#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" != '--skip-build' ]]; then
    "$ROOT/scripts/build-app.sh"
fi
APP="$ROOT/dist/Monkey.app"
[[ -d "$APP" ]] || { echo "Missing $APP" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
ARCH="$(uname -m)"
NAME="Monkey-$VERSION-macos-$ARCH"
STAGE="$(mktemp -d "$ROOT/dist/.monkey-package.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
FOLDER="$STAGE/$NAME"
mkdir -p "$FOLDER/scripts"
ditto "$APP" "$FOLDER/Monkey.app"
cp "$ROOT/scripts/install.sh" "$ROOT/scripts/uninstall.sh" "$FOLDER/scripts/"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$FOLDER/"
cat > "$FOLDER/Install.command" <<'SH'
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/scripts/install.sh" "$ROOT/Monkey.app"
SH
cat > "$FOLDER/Uninstall.command" <<'SH'
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/scripts/uninstall.sh"
SH
chmod +x "$FOLDER/Install.command" "$FOLDER/Uninstall.command" "$FOLDER/scripts/"*.sh
{
    printf 'Monkey %s — macOS %s or later — %s\n\n' "$VERSION" "$MINIMUM" "$ARCH"
    printf 'Run Install.command to install to ~/Library/Input Methods/Monkey.app.\n'
    printf 'It registers/enables Monkey but does not change your current input source.\n'
    printf 'If Monkey is absent from the input menu or typing does not work, log out and back in.\n'
    printf 'Settings: open -a "$HOME/Library/Input Methods/Monkey.app" --args --settings\n\n'
    printf 'This development release has NOT been notarized by Apple.\n'
    printf 'See Monkey.app/Contents/Resources/BUILD-INFO.txt for its signature and runtime requirements.\n'
    printf 'Read docs/install.md in the source repository for Gatekeeper and source-build options.\n\n'
    cat "$APP/Contents/Resources/BUILD-INFO.txt"
} > "$FOLDER/READ-ME.txt"
ditto -c -k --sequesterRsrc --keepParent "$FOLDER" "$ROOT/dist/$NAME.zip"
if [[ "${MONKEY_CREATE_DMG:-1}" == 1 ]]; then
    hdiutil create -volname "Monkey $VERSION" -srcfolder "$FOLDER" -ov -format UDZO "$ROOT/dist/$NAME.dmg"
fi
(
    cd "$ROOT/dist"
    shasum -a 256 "$NAME.zip" > "$NAME.sha256"
    if [[ -f "$NAME.dmg" ]]; then
        shasum -a 256 "$NAME.dmg" >> "$NAME.sha256"
    fi
)
printf '\nRelease files:\n'
ls -lh "$ROOT/dist/$NAME.zip" "$ROOT/dist/$NAME.sha256"
[[ ! -f "$ROOT/dist/$NAME.dmg" ]] || ls -lh "$ROOT/dist/$NAME.dmg"
