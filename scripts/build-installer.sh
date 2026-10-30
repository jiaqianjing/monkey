#!/bin/bash
set -euo pipefail

# Standalone builder: deliberately does not call build-app.sh or install.sh.
# Production payloads must already be Developer ID signed, notarized and stapled.
MONKEY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD="${MONKEY_PAYLOAD_APP:-$MONKEY_ROOT/dist/Monkey.app}"
OUTPUT="${MONKEY_INSTALLER_OUTPUT:-$MONKEY_ROOT/dist/Monkey Installer.app}"
DEVELOPMENT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --development) DEVELOPMENT=1; shift ;;
        --skip-build) shift ;; # Contract with notarize-release.sh; no main build ever occurs.
        --source-app) PAYLOAD="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --help|-h)
            printf '%s\n' 'Usage: build-installer.sh [--skip-build] [--development] [--source-app APP] [--output APP]'
            printf '%s\n' 'Production: MONKEY_PAYLOAD_APP, MONKEY_INSTALLER_OUTPUT, MONKEY_SIGNING_IDENTITY.'
            printf '%s\n' 'Development is a non-installing UI/resource preview signed ad hoc.'
            exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done
[[ "$(uname -s)" == Darwin ]] || { printf 'Build the installer on macOS.\n' >&2; exit 1; }
[[ -d "$PAYLOAD" && ! -L "$PAYLOAD" ]] || { printf 'Missing or symlink payload: %s\n' "$PAYLOAD" >&2; exit 1; }
[[ "$(basename "$OUTPUT")" == 'Monkey Installer.app' && ! -L "$OUTPUT" ]] || {
    printf 'Output must be a regular bundle named Monkey Installer.app.\n' >&2; exit 1;
}
PAYLOAD_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PAYLOAD/Contents/Info.plist")"
PAYLOAD_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PAYLOAD/Contents/Info.plist")"
[[ "$PAYLOAD_ID" == 'org.monkey.inputmethod.Monkey' && "$PAYLOAD_EXECUTABLE" == MonkeyInputMethod ]] || {
    printf 'Refusing an unrelated payload.\n' >&2; exit 1;
}
codesign --verify --deep --strict "$PAYLOAD"
TEAM="$(codesign --display --verbose=4 "$PAYLOAD" 2>&1 | awk -F= '/^TeamIdentifier=/ {print $2; exit}')"
IDENTITY="${MONKEY_SIGNING_IDENTITY:-}"
APP_REQUIREMENT='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and identifier "org.monkey.inputmethod.Monkey"'
if [[ "$DEVELOPMENT" == 0 ]]; then
    [[ -n "$IDENTITY" && "$IDENTITY" != '-' ]] || {
        printf 'A Developer ID Application identity is required. Use --development only for a non-installing local preview.\n' >&2; exit 1;
    }
    [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || { printf 'Payload has no valid signing Team ID.\n' >&2; exit 1; }
    codesign --verify --deep --strict --test-requirement "=$APP_REQUIREMENT" "$PAYLOAD"
    # This is the first notarization boundary. Only the publisher runs stapler;
    # the installer will not need Xcode, credentials or a network connection.
    xcrun stapler validate "$PAYLOAD"
else
    printf 'Building a DEVELOPMENT PREVIEW. Installation is disabled in this app.\n'
    TEAM=''
fi

OUTPUT_PARENT="$(dirname "$OUTPUT")"
mkdir -p "$OUTPUT_PARENT"
OUTPUT_PARENT="$(cd "$OUTPUT_PARENT" && pwd)"
OUTPUT="$OUTPUT_PARENT/Monkey Installer.app"
if [[ -e "$OUTPUT" ]]; then
    EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$OUTPUT/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$EXISTING_ID" == org.monkey.inputmethod.Installer ]] || {
        printf 'Refusing to replace an unrelated output bundle: %s\n' "$OUTPUT" >&2; exit 1;
    }
fi
STAGE="$(mktemp -d "$OUTPUT_PARENT/.monkey-installer-build.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Monkey Installer.app"
CONTENTS="$APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$STAGE/Payload"
ditto "$PAYLOAD" "$STAGE/Payload/Monkey.app"
codesign --verify --deep --strict "$STAGE/Payload/Monkey.app"
if [[ "$DEVELOPMENT" == 0 ]]; then
    COPIED_REQUIREMENT="$APP_REQUIREMENT and certificate leaf[subject.OU] = \"$TEAM\""
    codesign --verify --deep --strict --test-requirement "=$COPIED_REQUIREMENT" "$STAGE/Payload/Monkey.app"
    xcrun stapler validate "$STAGE/Payload/Monkey.app"
fi
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Payload/Monkey.app" "$CONTENTS/Resources/MonkeyPayload.zip"
cp "$MONKEY_ROOT/Installer/Info.plist" "$CONTENTS/Info.plist"
if [[ -f "$PAYLOAD/Contents/Resources/AppIcon.icns" ]]; then
    cp "$PAYLOAD/Contents/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

python3 - "$PAYLOAD/Contents/Info.plist" "$CONTENTS/Info.plist" "$CONTENTS/Resources/MonkeyPayload.zip" "$TEAM" "$DEVELOPMENT" <<'PY'
import hashlib, pathlib, plistlib, sys
payload = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
path = pathlib.Path(sys.argv[2])
info = plistlib.loads(path.read_bytes())
minimum = max((13, 0), tuple(int(part) for part in payload.get('LSMinimumSystemVersion', '13.0').split('.')))
info.update({
    'CFBundleShortVersionString': payload['CFBundleShortVersionString'],
    'CFBundleVersion': payload['CFBundleVersion'],
    'LSMinimumSystemVersion': '.'.join(map(str, minimum)),
    'MonkeyPayloadVersion': payload['CFBundleShortVersionString'],
    'MonkeyPayloadBuild': payload['CFBundleVersion'],
    'MonkeyPayloadSHA256': hashlib.sha256(pathlib.Path(sys.argv[3]).read_bytes()).hexdigest(),
    'MonkeyPayloadTeamIdentifier': sys.argv[4],
    'MonkeyInstallerDevelopmentMode': sys.argv[5] == '1',
})
path.write_bytes(plistlib.dumps(info))
PY
MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$CONTENTS/Info.plist")"
ARCHS="$(lipo -archs "$PAYLOAD/Contents/MacOS/MonkeyInputMethod")"
IMAGES=()
for ARCH in $ARCHS; do
    [[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]] || { printf 'Unsupported payload architecture: %s\n' "$ARCH" >&2; exit 1; }
    IMAGE="$STAGE/MonkeyInstaller-$ARCH"
    xcrun swiftc -swift-version 5 -O -parse-as-library -target "$ARCH-apple-macos$MINIMUM" \
        "$MONKEY_ROOT/Installer/InstallerCore.swift" "$MONKEY_ROOT/Installer/InstallerSelfTest.swift" \
        "$MONKEY_ROOT/Installer/InstallerApp.swift" -framework AppKit -framework Security -o "$IMAGE"
    IMAGES+=("$IMAGE")
done
if [[ "${#IMAGES[@]}" == 1 ]]; then
    cp "${IMAGES[0]}" "$CONTENTS/MacOS/MonkeyInstaller"
else
    lipo -create "${IMAGES[@]}" -output "$CONTENTS/MacOS/MonkeyInstaller"
fi
chmod +x "$CONTENTS/MacOS/MonkeyInstaller"
if [[ "$DEVELOPMENT" == 1 ]]; then
    codesign --force --sign - --timestamp=none "$APP"
else
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
    INSTALLER_REQUIREMENT="anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and identifier \"org.monkey.inputmethod.Installer\" and certificate leaf[subject.OU] = \"$TEAM\""
    codesign --verify --deep --strict --test-requirement "=$INSTALLER_REQUIREMENT" "$APP"
fi
codesign --verify --deep --strict "$APP"
plutil -lint "$CONTENTS/Info.plist"
if [[ -e "$OUTPUT" ]]; then mv "$OUTPUT" "$STAGE/previous-output.app"; fi
if ! mv "$APP" "$OUTPUT"; then
    [[ ! -e "$STAGE/previous-output.app" ]] || mv "$STAGE/previous-output.app" "$OUTPUT"
    exit 1
fi
printf '\nBuilt %s\n' "$OUTPUT"
if [[ "$DEVELOPMENT" == 1 ]]; then
    printf 'Development preview only; installation is disabled.\n'
else
    printf 'Developer ID signed; installer still requires its own notarization and stapling before publication.\n'
fi
