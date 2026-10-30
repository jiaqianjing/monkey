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
    printf 'If macOS blocks Install.command, click Done, then System Settings > Privacy & Security > Open Anyway for this file, only if you trust the download.\n'
    printf 'Monkey.app may require its own confirmation. If registration was blocked, run Install.command again after allowing the app.\n'
    printf 'See Monkey.app/Contents/Resources/BUILD-INFO.txt for its signature and runtime requirements.\n'
    printf 'Full installation and Gatekeeper steps: https://github.com/jiaqianjing/monkey/blob/main/docs/install-advanced.md#gatekeeper\n\n'
    cat "$APP/Contents/Resources/BUILD-INFO.txt"
} > "$FOLDER/READ-ME.txt"
ditto -c -k --sequesterRsrc --keepParent "$FOLDER" "$ROOT/dist/$NAME.zip"
if [[ "${MONKEY_CREATE_DMG:-1}" == 1 ]]; then
    DMG="$ROOT/dist/$NAME.dmg"
    if ! hdiutil create -volname "Monkey $VERSION" -srcfolder "$FOLDER" -ov -format UDZO "$DMG"; then
        rm -f "$DMG"
        # Newer macOS releases provide a replacement image CLI. Keep hdiutil
        # first for older systems, and do not fail a valid ZIP if imaging fails.
        if diskutil image create from --help >/dev/null 2>&1; then
            if ! diskutil image create from --format UDZO --volumeName "Monkey $VERSION" "$FOLDER" "$DMG"; then
                rm -f "$DMG"
            fi
        fi
        if [[ ! -f "$DMG" ]]; then
            printf 'DMG was not generated because the system image service failed; the ZIP remains available.\n' >&2
        fi
    fi
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
