import AppKit

// Renders a 1024x1024 app-icon PNG: an SF Symbol bird on a dark rounded-rect.
// Run: swift scripts/make-icon.swift <output.png>

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon-1024.png"

let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: side, height: side)
let background = NSBezierPath(roundedRect: rect, xRadius: side * 0.2237, yRadius: side * 0.2237)
background.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.15, alpha: 1),
    NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.32, alpha: 1),
])!
gradient.draw(in: rect, angle: -90)

let symbolName = ["bird.fill", "bird", "bell.fill"].first {
    NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
} ?? "bell.fill"

let sizeConfig = NSImage.SymbolConfiguration(pointSize: side * 0.5, weight: .semibold)
let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
let config = sizeConfig.applying(colorConfig)

if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let symbolSize = symbol.size
    let origin = NSPoint(x: (side - symbolSize.width) / 2, y: (side - symbolSize.height) / 2)
    symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render PNG\n".utf8))
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) using symbol '\(symbolName)'")
