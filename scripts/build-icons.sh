#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build"
STAGE="$(mktemp -d "$ROOT/.build/monkey-icons.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
swift - "$ROOT" <<'SWIFT'
import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = NSImage(contentsOf: root.appendingPathComponent("Resources/MenuBarIcon.svg")) else {
    fatalError("Cannot load the menu-bar mark")
}
final class IconView: NSView {
    let image: NSImage
    init(_ image: NSImage) { self.image = image; super.init(frame: .init(x: 0, y: 0, width: 18, height: 18)) }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
let view = IconView(image)
try view.dataWithPDF(inside: view.bounds).write(to: root.appendingPathComponent("Resources/monkey.pdf"))
SWIFT
printf 'Built AppIcon.icns and the monochrome input-source mark.\n'
