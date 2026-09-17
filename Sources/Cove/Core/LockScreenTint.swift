import AppKit
import ImageIO

enum LockScreenTint {
    static let sampleX: ClosedRange<Double> = 0.30...0.70
    static let sampleY: ClosedRange<Double> = 0.05...0.45
    static let saturationScale: CGFloat = 0.55
    static let minBrightness: CGFloat = 0.88
    static let darkenThreshold: CGFloat = 0.72
    static let darkBrightness: CGFloat = 0.22
    private static let thumbnailSize = 64

    @MainActor private static var cache: [String: NSColor] = [:]

    private static func cacheKey(url: URL, dark: Bool) -> String { "\(url.path)#\(dark ? "d" : "l")" }

    @MainActor
    static func cached(for url: URL, dark: Bool) -> NSColor? { cache[cacheKey(url: url, dark: dark)] }

    @MainActor
    static func store(_ color: NSColor, for url: URL, dark: Bool) { cache[cacheKey(url: url, dark: dark)] = color }

    @MainActor
    static var isDarkAppearance: Bool {
        (NSApp?.effectiveAppearance).map { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua } ?? false
    }

    static func color(forWallpaperAt url: URL, dark: Bool = false) -> NSColor? {
        guard let (rgba, w, h) = thumbnailRGBA(url: url, dark: dark),
              let (r, g, b) = average(rgba: rgba, width: w, height: h, x: sampleX, y: sampleY)
        else { return nil }
        let base = NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        let (th, ts, tb) = tint(h: hue, s: sat, b: bri)
        return NSColor(calibratedHue: th, saturation: ts, brightness: tb, alpha: 1)
    }

    static func tint(h: CGFloat, s: CGFloat, b: CGFloat) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        let sat = min(max(s * saturationScale, 0), 1)
        if b >= darkenThreshold { return (h, sat, darkBrightness) }
        return (h, sat, min(max(b, minBrightness), 1))
    }

    static func isLight(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return true }
        return rgb.brightnessComponent >= 0.5
    }

    static func average(rgba: [UInt8], width: Int, height: Int,
                        x: ClosedRange<Double>, y: ClosedRange<Double>) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        let x0 = Int(Double(width) * x.lowerBound), x1 = Int(Double(width) * x.upperBound)
        let y0 = Int(Double(height) * y.lowerBound), y1 = Int(Double(height) * y.upperBound)
        var r = 0, g = 0, b = 0, n = 0
        for row in y0..<max(y1, y0 + 1) where row < height {
            for col in x0..<max(x1, x0 + 1) where col < width {
                let i = (row * width + col) * 4
                r += Int(rgba[i]); g += Int(rgba[i + 1]); b += Int(rgba[i + 2]); n += 1
            }
        }
        guard n > 0 else { return nil }
        return (CGFloat(r) / CGFloat(n * 255), CGFloat(g) / CGFloat(n * 255), CGFloat(b) / CGFloat(n * 255))
    }

    private static let appleNamespace = "http://ns.apple.com/namespace/1.0/"

    static func frameIndex(fromPlist data: Data, dark: Bool) -> Int? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any] else { return nil }
        let ap = (root["ap"] as? [String: Any]) ?? root
        guard let i = ap[dark ? "d" : "l"] as? Int, i >= 0 else { return nil }
        return i
    }

    static func frameIndex(fromBase64 text: String, dark: Bool) -> Int? {
        guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return frameIndex(fromPlist: data, dark: dark)
    }

    static func frameIndex(source src: CGImageSource, dark: Bool) -> Int {
        let count = CGImageSourceGetCount(src)
        guard count > 1, let md = CGImageSourceCopyMetadataAtIndex(src, 0, nil) else { return 0 }
        let tags = CGImageMetadataCopyTags(md) as? [CGImageMetadataTag] ?? []
        for name in ["apr", "solar"] {
            guard let tag = tags.first(where: {
                      (CGImageMetadataTagCopyNamespace($0) as String?) == appleNamespace
                          && (CGImageMetadataTagCopyName($0) as String?) == name
                  }),
                  let text = CGImageMetadataTagCopyValue(tag) as? String,
                  let i = frameIndex(fromBase64: text, dark: dark), i < count
            else { continue }
            return i
        }
        return 0
    }

    private static func thumbnailRGBA(url: URL, dark: Bool) -> ([UInt8], Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        let frame = frameIndex(source: src, dark: dark)
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, frame, opts as CFDictionary) else { return nil }
        let w = img.width, h = img.height
        guard w > 0, h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (data, w, h) : nil
    }
}
