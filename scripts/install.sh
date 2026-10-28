#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$ROOT/dist/Monkey.app}"
TARGET="$HOME/Library/Input Methods/Monkey.app"
BUNDLE_ID='org.monkey.inputmethod.Monkey'
[[ -d "$SOURCE" ]] || { echo "App not found: $SOURCE. Run scripts/build-app.sh first." >&2; exit 1; }
SOURCE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")"
[[ "$SOURCE_ID" == "$BUNDLE_ID" ]] || { echo 'Refusing to install an unrelated app.' >&2; exit 1; }
codesign --verify --deep --strict "$SOURCE"
if [[ -e "$TARGET" ]]; then
    [[ ! -L "$TARGET" ]] || { echo "Refusing to replace a symlink: $TARGET" >&2; exit 1; }
    EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET/Contents/Info.plist")"
    [[ "$EXISTING_ID" == "$BUNDLE_ID" ]] || { echo "A different app already exists at $TARGET" >&2; exit 1; }
fi
mkdir -p "$(dirname "$TARGET")"
STAGE="$(mktemp -d "$(dirname "$TARGET")/.monkey-install.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$SOURCE" "$STAGE/Monkey.app"
if [[ -d "$TARGET" ]]; then
    "$TARGET/Contents/MacOS/MonkeyInputMethod" --quit || true
    mv "$TARGET" "$STAGE/PreviousMonkey.app"
fi
if ! mv "$STAGE/Monkey.app" "$TARGET"; then
    [[ ! -d "$STAGE/PreviousMonkey.app" ]] || mv "$STAGE/PreviousMonkey.app" "$TARGET"
    exit 1
fi

REGISTERED=true
"$TARGET/Contents/MacOS/MonkeyInputMethod" --register || REGISTERED=false
"$TARGET/Contents/MacOS/MonkeyInputMethod" --enable || REGISTERED=false
printf '\nInstalled: %s\n' "$TARGET"
if [[ "$REGISTERED" == true ]]; then
    printf 'Registration and enable commands completed. The current input source was not changed.\n'
else
    printf 'macOS did not finish registering/enabling the input source in this session.\n'
fi
printf 'Select Monkey 拼音 from the input menu. If absent or typing fails, log out and back in, then add it in System Settings → Keyboard → Text Input → Edit.\n'
printf 'Settings: open -a "%s" --args --settings\n' "$TARGET"
printf 'Signing details: %s/Contents/Resources/BUILD-INFO.txt\n' "$TARGET"
