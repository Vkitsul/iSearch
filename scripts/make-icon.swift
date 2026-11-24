// Draws the 1024×1024 app icon and writes it to the PNG path given as the first argument.
import AppKit

let size = 1024
guard CommandLine.arguments.count > 1,
      let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      ),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fatalError("usage: make-icon.swift <output.png>")
}
NSGraphicsContext.current = context

// The standard macOS icon shape leaves a margin around the rounded square.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186).addClip()
NSGradient(
    starting: NSColor(calibratedRed: 0.87, green: 0.47, blue: 0.31, alpha: 1),
    ending: NSColor(calibratedRed: 0.62, green: 0.26, blue: 0.20, alpha: 1)
)?.draw(in: tile, angle: -90)

NSColor.white.setStroke()
let lens = NSBezierPath(ovalIn: NSRect(x: 322, y: 382, width: 340, height: 340))
lens.lineWidth = 62
lens.stroke()
let handle = NSBezierPath()
handle.move(to: NSPoint(x: 400, y: 408))
handle.line(to: NSPoint(x: 268, y: 276))
handle.lineWidth = 78
handle.lineCapStyle = .round
handle.stroke()

context.flushGraphics()
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("could not encode the PNG")
}
try data.write(to: URL(filePath: CommandLine.arguments[1]))
