#!/bin/bash
set -euo pipefail

TARGET="$HOME/Library/Input Methods/Monkey.app"
if [[ ! -e "$TARGET" ]]; then
    printf 'Monkey is not installed at %s\n' "$TARGET"
    exit 0
fi
[[ ! -L "$TARGET" ]] || { echo "Refusing to remove a symlink: $TARGET" >&2; exit 1; }
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET/Contents/Info.plist")"
[[ "$IDENTIFIER" == 'org.monkey.inputmethod.Monkey' ]] || { echo 'Refusing to remove an unrelated app.' >&2; exit 1; }
"$TARGET/Contents/MacOS/MonkeyInputMethod" --disable || true
"$TARGET/Contents/MacOS/MonkeyInputMethod" --quit || true
rm -rf "$TARGET"
printf 'Removed %s\n' "$TARGET"
printf 'Your learned words, preferences and ChatGPT connection were preserved. Disconnect ChatGPT from Monkey settings before uninstalling if you want to remove its saved credentials.\n'
printf 'Log out and back in if macOS still shows the old input source.\n'
