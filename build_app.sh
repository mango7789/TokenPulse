#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "Building TokenPulse (release)..."
swift build -c release

BIN_PATH="$ROOT_DIR/.build/release/TokenPulse"
APP_DIR="$ROOT_DIR/TokenPulse.app"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/TokenPulse"
chmod +x "$APP_DIR/Contents/MacOS/TokenPulse"

# Generate a clean native macOS AppIcon.icns
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
swift - "$ICONSET_DIR" <<'SWIFT'
import AppKit
import Foundation

let outDir = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, name) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    let inset = CGFloat(px) * 0.08
    let card = rect.insetBy(dx: inset, dy: inset)
    let radius = card.width * 0.22
    let bgPath = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)

    let grad = NSGradient(colors: [
        NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.20, alpha: 1.0),
        NSColor(calibratedRed: 0.13, green: 0.19, blue: 0.32, alpha: 1.0)
    ])!
    grad.draw(in: bgPath, angle: -45)

    // Subtle border
    NSColor.white.withAlphaComponent(0.14).setStroke()
    bgPath.lineWidth = max(1, CGFloat(px) * 0.015)
    bgPath.stroke()

    // Pulse waveform
    let w = card.width
    let h = card.height
    let ox = card.minX
    let oy = card.minY
    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: ox + w * 0.14, y: oy + h * 0.50))
    wave.line(to: NSPoint(x: ox + w * 0.30, y: oy + h * 0.50))
    wave.line(to: NSPoint(x: ox + w * 0.40, y: oy + h * 0.74))
    wave.line(to: NSPoint(x: ox + w * 0.52, y: oy + h * 0.24))
    wave.line(to: NSPoint(x: ox + w * 0.64, y: oy + h * 0.64))
    wave.line(to: NSPoint(x: ox + w * 0.73, y: oy + h * 0.50))
    wave.line(to: NSPoint(x: ox + w * 0.86, y: oy + h * 0.50))
    wave.lineCapStyle = .round
    wave.lineJoinStyle = .round
    wave.lineWidth = max(1.5, CGFloat(px) * 0.068)

    NSColor(calibratedRed: 0.29, green: 0.76, blue: 0.98, alpha: 1.0).setStroke()
    wave.stroke()

    // Accent dot
    let dotR = max(1.5, CGFloat(px) * 0.055)
    let dotRect = NSRect(x: ox + w * 0.86 - dotR, y: oy + h * 0.50 - dotR, width: dotR * 2, height: dotR * 2)
    NSColor(calibratedRed: 0.28, green: 0.88, blue: 0.55, alpha: 1.0).setFill()
    NSBezierPath(ovalIn: dotRect).fill()

    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: (outDir as NSString).appendingPathComponent(name)))
    }
}
SWIFT

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>TokenPulse</string>
    <key>CFBundleDisplayName</key>
    <string>TokenPulse</string>
    <key>CFBundleIdentifier</key>
    <string>com.mango.TokenPulse</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleExecutable</key>
    <string>TokenPulse</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "Packaged: $APP_DIR"
