import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size
    let inset = s * 0.06
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.16, alpha: 1),
        NSColor(calibratedRed: 0.30, green: 0.30, blue: 0.36, alpha: 1),
    ])!.draw(in: squircle, angle: 90)
    squircle.addClip()

    NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
    NSRect(x: 0, y: s * 0.72, width: s, height: s * 0.3).fill()

    let iW = s * 0.56, iH = s * 0.20
    let island = NSBezierPath(roundedRect: NSRect(x: (s - iW) / 2, y: s * 0.72 - iH + s * 0.02,
                                                  width: iW, height: iH),
                              xRadius: iH * 0.42, yRadius: iH * 0.42)
    NSColor.black.setFill()
    island.fill()

    NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.55, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.26, y: s * 0.585, width: s * 0.11, height: s * 0.11),
                 xRadius: s * 0.025, yRadius: s * 0.025).fill()
    NSColor.white.setFill()
    let heights: [CGFloat] = [0.05, 0.09, 0.12, 0.08, 0.05]
    for (i, h) in heights.enumerated() {
        let x = s * 0.56 + CGFloat(i) * s * 0.035
        NSBezierPath(roundedRect: NSRect(x: x, y: s * 0.64 - h * s / 2, width: s * 0.018, height: h * s),
                     xRadius: s * 0.009, yRadius: s * 0.009).fill()
    }

    NSColor.white.withAlphaComponent(0.85).setFill()
    let big: [CGFloat] = [0.10, 0.18, 0.28, 0.20, 0.34, 0.16, 0.24, 0.12]
    for (i, h) in big.enumerated() {
        let x = s * 0.20 + CGFloat(i) * s * 0.083
        NSBezierPath(roundedRect: NSRect(x: x, y: s * 0.36 - h * s / 2, width: s * 0.045, height: h * s),
                     xRadius: s * 0.0225, yRadius: s * 0.0225).fill()
    }
    image.unlockFocus()
    return image
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                   ("512x512", 512), ("512x512@2x", 1024)] as [(String, Int)] {
    let img = draw(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: out.appendingPathComponent("icon_\(name).png"))
}
print("iconset em \(out.path)")
