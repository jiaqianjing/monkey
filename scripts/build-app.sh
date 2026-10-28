#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Darwin ]] || { echo "Monkey must be built on macOS." >&2; exit 1; }

if [[ ! -d Vendor/Rime/lib ]] || ! compgen -G 'Vendor/Rime/lib/*.dylib' >/dev/null; then
    "$ROOT/scripts/bootstrap-rime.sh"
fi
[[ -d Resources/Rime ]] || { echo "Missing Resources/Rime. Run scripts/bootstrap-rime.sh." >&2; exit 1; }

swift build -c release --product MonkeyInputMethod
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p "$ROOT/dist"
STAGE="$(mktemp -d "$ROOT/dist/.monkey-build.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Monkey.app"
CONTENTS="$APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
cp "$BIN_DIR/MonkeyInputMethod" "$CONTENTS/MacOS/MonkeyInputMethod"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/monkey.pdf" "$CONTENTS/Resources/monkey.pdf"
ditto "$ROOT/Resources/Rime" "$CONTENTS/Resources/Rime"
for locale in en zh-Hans; do
    ditto "$ROOT/Resources/$locale.lproj" "$CONTENTS/Resources/$locale.lproj"
done
for resource_bundle in "$BIN_DIR"/*.bundle; do
    [[ -d "$resource_bundle" ]] || continue
    ditto "$resource_bundle" "$CONTENTS/Resources/$(basename "$resource_bundle")"
done
for library in "$ROOT/Vendor/Rime/lib"/*.dylib; do
    [[ -e "$library" ]] || continue
    cp -L "$library" "$CONTENTS/Frameworks/$(basename "$library")"
done
chmod u+w "$CONTENTS/Frameworks/"*.dylib
mkdir -p "$CONTENTS/Resources/Licenses"
cp LICENSE THIRD_PARTY_NOTICES.md "$CONTENTS/Resources/Licenses/"
if [[ -d Vendor/Rime/licenses ]]; then
    ditto Vendor/Rime/licenses "$CONTENTS/Resources/Licenses/Runtime"
fi
if [[ -f Vendor/Rime/BUILD-MANIFEST.txt ]]; then
    cp Vendor/Rime/BUILD-MANIFEST.txt "$CONTENTS/Resources/Licenses/"
fi

# The bootstrapper relocates all non-system dylibs. Verify that the app does not
# accidentally depend on the developer's Homebrew installation.
python3 - "$CONTENTS" <<'PY'
import pathlib, re, subprocess, sys
contents = pathlib.Path(sys.argv[1])
libraries = list((contents / 'Frameworks').glob('*.dylib'))
images = [contents / 'MacOS/MonkeyInputMethod', *libraries]
arch = subprocess.check_output(['uname', '-m'], text=True).strip()
minimum = (13, 0)
for path in images:
    architectures = subprocess.check_output(['lipo', '-archs', str(path)], text=True).split()
    if arch not in architectures:
        raise SystemExit(f'{path.name} does not contain the build architecture {arch}')
    commands = subprocess.check_output(['otool', '-l', str(path)], text=True)
    for block in commands.split('Load command '):
        if 'cmd LC_BUILD_VERSION' in block:
            match = re.search(r'\bminos\s+([0-9.]+)', block)
        elif 'cmd LC_VERSION_MIN_MACOSX' in block:
            match = re.search(r'\bversion\s+([0-9.]+)', block)
        else:
            continue
        if match:
            minimum = max(minimum, tuple(map(int, match.group(1).split('.'))))
    linked = subprocess.check_output(['otool', '-L', str(path)], text=True).splitlines()[1:]
    for line in linked:
        if not line.startswith('\t'):
            continue  # otool repeats a header for each universal architecture.
        dependency = line.strip().split(' (compatibility version', 1)[0]
        if dependency.startswith(('/usr/lib/', '/System/Library/')):
            continue
        if dependency.startswith('@loader_path/') and path in libraries:
            if (path.parent / dependency[len('@loader_path/'):]).is_file():
                continue
        if dependency.startswith('@rpath/libswift'):
            continue
        if path in libraries and dependency == '@rpath/' + path.name:
            continue  # LC_ID_DYLIB, not an external dependency.
        raise SystemExit(f'Unbundled dependency in {path.name}: {dependency}')
version = '.'.join(map(str, minimum))
subprocess.check_call(['/usr/libexec/PlistBuddy', '-c', f'Set :LSMinimumSystemVersion {version}', str(contents / 'Info.plist')])
print(f'Validated {len(libraries)} bundled dylibs; actual minimum macOS: {version}')
PY

IDENTITY="${MONKEY_SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Developer ID Application:/ {print $2; exit}' || true)"
fi
SIGN_FLAGS=(--force)
if [[ -n "$IDENTITY" && "$IDENTITY" != '-' ]]; then
    SIGN_FLAGS+=(--sign "$IDENTITY" --options runtime --timestamp)
    SIGNING_STATUS="Developer identity: $IDENTITY; NOT NOTARIZED"
else
    IDENTITY='-'
    SIGN_FLAGS+=(--sign - --timestamp=none)
    SIGNING_STATUS='Ad-hoc signed development build; NOT NOTARIZED'
fi
MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$CONTENTS/Info.plist")"
{
    printf 'Monkey 0.1.0\nArchitecture: %s\nMinimum macOS: %s\n' "$(uname -m)" "$MINIMUM"
    printf 'Built: %s\nSigning: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$SIGNING_STATUS"
    printf 'Commit: %s\n' "$(git rev-parse HEAD 2>/dev/null || printf 'uncommitted source')"
} > "$CONTENTS/Resources/BUILD-INFO.txt"
for library in "$CONTENTS/Frameworks/"*.dylib; do
    codesign "${SIGN_FLAGS[@]}" "$library"
done
codesign "${SIGN_FLAGS[@]}" --entitlements "$ROOT/Resources/entitlements.plist" "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$CONTENTS/Info.plist"

rm -rf "$ROOT/dist/Monkey.app"
mv "$APP" "$ROOT/dist/Monkey.app"
printf '\nBuilt %s\n%s\nMinimum macOS: %s\n' "$ROOT/dist/Monkey.app" "$SIGNING_STATUS" "$MINIMUM"
