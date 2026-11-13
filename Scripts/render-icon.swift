// Renders an SVG to a square PNG with a transparent background.
// usage: swift Scripts/render-icon.swift <in.svg> <out.png> <pixels>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let size = Int(arguments[3]), size > 0,
      let image = NSImage(contentsOfFile: arguments[1])
else {
    FileHandle.standardError.write(Data("usage: render-icon.swift <in.svg> <out.png> <pixels>\n".utf8))
    exit(64)
}
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    exit(1)
}
bitmap.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}
try png.write(to: URL(fileURLWithPath: arguments[2]))
