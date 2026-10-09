import AppKit

// Vector source of truth: native paths, gradients and optical padding. No network,
// font dependency or hand-edited raster is required to reproduce every size.
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: make_icons.swift output-directory")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let size = NSSize(width: 1024, height: 1024)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

let master = NSImage(size: size, flipped: false) { _ in
    let tile = NSRect(x: 72, y: 80, width: 880, height: 880)
    let shape = rounded(tile, 196)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.23)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0.04, 0.27, 0.23).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [color(0.19, 0.61, 0.50), color(0.07, 0.39, 0.33), color(0.035, 0.25, 0.23)])!
        .draw(in: shape, angle: -68)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    color(1, 1, 1, 0.15).setStroke()
    shape.lineWidth = 4
    shape.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // A low-profile ivory keycap: gentle depth, no perspective gimmicks.
    let base = rounded(NSRect(x: 237, y: 252, width: 550, height: 526), 112)
    NSGraphicsContext.saveGraphicsState()
    let keyShadow = NSShadow()
    keyShadow.shadowColor = color(0.01, 0.12, 0.10, 0.37)
    keyShadow.shadowBlurRadius = 38
    keyShadow.shadowOffset = NSSize(width: 0, height: -22)
    keyShadow.set()
    color(0.71, 0.80, 0.74).setFill()
    base.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0.84, 0.89, 0.83), ending: color(0.66, 0.75, 0.70))!
        .draw(in: base, angle: -90)

    let face = rounded(NSRect(x: 239, y: 288, width: 546, height: 508), 108)
    NSGradient(starting: color(1, 0.998, 0.961), ending: color(0.90, 0.935, 0.882))!
        .draw(in: face, angle: -90)
    color(1, 1, 1, 0.85).setStroke()
    face.lineWidth = 3
    face.stroke()

    // Three ascending count strokes, optically centered inside the keycap.
    for (x, height) in [(358.0, 126.0), (467.0, 192.0), (576.0, 258.0)] {
        let stroke = rounded(NSRect(x: x, y: 403, width: 47, height: height), 23.5)
        NSGradient(starting: color(0.10, 0.45, 0.37), ending: color(0.04, 0.29, 0.26))!
            .draw(in: stroke, angle: -90)
    }
    color(0.94, 0.63, 0.25).setFill()
    rounded(NSRect(x: 650, y: 655, width: 34, height: 34), 17).fill()
    return true
}

func writePNG(_ pixels: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Unable to create icon bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    // Render vectors at the destination resolution, not a downscaled cached bitmap.
    master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode icon")
    }
    try data.write(to: url, options: .atomic)
}

try writePNG(1024, to: output.appendingPathComponent("AppIcon.png"))
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try writePNG(points * scale, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
print("Icon master and 10 iconset renditions generated in \(output.path)")
