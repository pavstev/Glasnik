import AppKit
import Foundation

// Draws the Šapat app icon — a copper Cyrillic "Ш" (the letter that opens "шапат",
// whisper) on a stone squircle — at every iconset size, then `iconutil` packs it into
// Resources/Sapat.icns. Run from the repo root:
//   swift scripts/make-icon.swift && iconutil -c icns -o Resources/Sapat.icns Sapat.iconset

let stone = NSColor(srgbRed: 0.137, green: 0.125, blue: 0.110, alpha: 1)        // #23201C
let copperDeep = NSColor(srgbRed: 0.788, green: 0.494, blue: 0.278, alpha: 1)   // #C97E47
let copperLight = NSColor(srgbRed: 0.886, green: 0.647, blue: 0.435, alpha: 1)  // #E2A56F

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixels)
    let inset = s * 0.08
    let side = s - inset * 2
    let tile = NSRect(x: inset, y: inset, width: side, height: side)
    let radius = side * 0.2237
    stone.setFill()
    NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius).fill()

    let fontSize = side * 0.56
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let text = NSAttributedString(string: "Ш", attributes: [.font: font, .foregroundColor: copperLight])
    let textSize = text.size()
    let origin = NSPoint(x: (s - textSize.width) / 2, y: (s - textSize.height) / 2 - s * 0.02)
    text.draw(at: origin)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "Sapat.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in sizes {
    let data = drawIcon(pixels: px).representation(using: .png, properties: [:])!
    try! data.write(to: iconset.appendingPathComponent("\(name).png"))
}
print("Wrote Sapat.iconset")
