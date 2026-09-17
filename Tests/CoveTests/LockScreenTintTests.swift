import ImageIO
import XCTest
@testable import Cove

final class LockScreenTintTests: XCTestCase {

    func testTintKeepsHueScalesSaturationRaisesBrightness() {
        let out = LockScreenTint.tint(h: 0.72, s: 0.8, b: 0.4)
        XCTAssertEqual(out.h, 0.72, accuracy: 0.0001)
        XCTAssertEqual(out.s, 0.8 * 0.55, accuracy: 0.0001)
        XCTAssertEqual(out.b, 0.88, accuracy: 0.0001)
    }

    func testTintDarkensWhenWallpaperBandIsLight() {
        let out = LockScreenTint.tint(h: 0.1, s: 0.2, b: 0.9)
        XCTAssertEqual(out.h, 0.1, accuracy: 0.0001)
        XCTAssertEqual(out.s, 0.11, accuracy: 0.0001)
        XCTAssertEqual(out.b, 0.22, accuracy: 0.0001)
    }

    func testTintThresholdEdges() {
        XCTAssertEqual(LockScreenTint.tint(h: 0, s: 0, b: 0.72).b, 0.22, accuracy: 0.0001)
        XCTAssertEqual(LockScreenTint.tint(h: 0, s: 0, b: 0.719).b, 0.88, accuracy: 0.0001)
        XCTAssertEqual(LockScreenTint.tint(h: 0, s: 0, b: 1).b, 0.22, accuracy: 0.0001)
    }

    func testTintClampsSaturationToUnitRange() {
        let out = LockScreenTint.tint(h: 0.5, s: 3, b: 0.5)
        XCTAssertEqual(out.s, 1, accuracy: 0.0001)
        XCTAssertEqual(out.b, 0.88, accuracy: 0.0001)
        XCTAssertEqual(LockScreenTint.tint(h: 0.5, s: 3, b: 0.95).s, 1, accuracy: 0.0001)
    }

    func testTintOfGrayStaysGray() {
        let out = LockScreenTint.tint(h: 0, s: 0, b: 0.3)
        XCTAssertEqual(out.s, 0, accuracy: 0.0001)
        XCTAssertEqual(out.b, 0.88, accuracy: 0.0001)
    }

    func testIsLightForFallbackWhiteAndBothTintOutputs() {
        XCTAssertTrue(LockScreenTint.isLight(.white))
        XCTAssertFalse(LockScreenTint.isLight(.black))
        let light = LockScreenTint.tint(h: 0.6, s: 0.5, b: 0.3)
        XCTAssertTrue(LockScreenTint.isLight(NSColor(calibratedHue: light.h, saturation: light.s, brightness: light.b, alpha: 1)))
        let dark = LockScreenTint.tint(h: 0.6, s: 0.5, b: 0.9)
        XCTAssertFalse(LockScreenTint.isLight(NSColor(calibratedHue: dark.h, saturation: dark.s, brightness: dark.b, alpha: 1)))
    }

    private let sonomaAPR = "YnBsaXN0MDDSAQIDBFFsUWQQABABCA0PERMAAAAAAAABAQAAAAAAAAAFAAAAAAAAAAAAAAAAAAAAFQ=="

    func testFrameIndexFromRealAPRMetadata() {
        XCTAssertEqual(LockScreenTint.frameIndex(fromBase64: sonomaAPR, dark: false), 0)
        XCTAssertEqual(LockScreenTint.frameIndex(fromBase64: sonomaAPR, dark: true), 1)
    }

    func testFrameIndexFromSolarMetadataUsesAP() throws {
        let plist: [String: Any] = ["ap": ["l": 3, "d": 7], "si": [["i": 0, "a": 1.0, "z": 2.0]]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        XCTAssertEqual(LockScreenTint.frameIndex(fromPlist: data, dark: false), 3)
        XCTAssertEqual(LockScreenTint.frameIndex(fromPlist: data, dark: true), 7)
    }

    func testFrameIndexRejectsGarbage() throws {
        XCTAssertNil(LockScreenTint.frameIndex(fromBase64: "n@o-e-base64!!", dark: true))
        XCTAssertNil(LockScreenTint.frameIndex(fromPlist: Data([1, 2, 3]), dark: true))
        let noKeys = try PropertyListSerialization.data(fromPropertyList: ["x": 1], format: .binary, options: 0)
        XCTAssertNil(LockScreenTint.frameIndex(fromPlist: noKeys, dark: false))
        let negative = try PropertyListSerialization.data(fromPropertyList: ["l": -1, "d": 1], format: .binary, options: 0)
        XCTAssertNil(LockScreenTint.frameIndex(fromPlist: negative, dark: false))
    }

    func testFrameIndexOnStaticImageIsZero() throws {
        let url = try solidPNG(hue: 0.75, saturation: 0.9, brightness: 0.5)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(LockScreenTint.frameIndex(source: src, dark: true), 0)
        XCTAssertEqual(LockScreenTint.frameIndex(source: src, dark: false), 0)
    }

    func testSystemDynamicWallpaperPicksFrameByAppearance() throws {
        let path = "/System/Library/Desktop Pictures/Sonoma.heic"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path), "HEIC dinâmico do sistema ausente")
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        try XCTSkipUnless(CGImageSourceGetCount(src) == 2, "Sonoma.heic não tem 2 frames nesta versão")
        XCTAssertEqual(LockScreenTint.frameIndex(source: src, dark: false), 0)
        XCTAssertEqual(LockScreenTint.frameIndex(source: src, dark: true), 1)
        let light = try XCTUnwrap(LockScreenTint.color(forWallpaperAt: URL(fileURLWithPath: path), dark: false))
        let dark = try XCTUnwrap(LockScreenTint.color(forWallpaperAt: URL(fileURLWithPath: path), dark: true))
        XCTAssertNotEqual(light, dark)
    }

    private func splitBuffer(width: Int, height: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for col in 0..<width {
                let i = (row * width + col) * 4
                if row < height / 2 { px[i + 2] = 255 } else { px[i] = 255 }
                px[i + 3] = 255
            }
        }
        return px
    }

    func testAverageSamplesTopBandNotBottom() throws {
        let px = splitBuffer(width: 64, height: 40)
        let avg = try XCTUnwrap(LockScreenTint.average(rgba: px, width: 64, height: 40,
                                                       x: LockScreenTint.sampleX, y: LockScreenTint.sampleY))
        XCTAssertEqual(avg.r, 0, accuracy: 0.001)
        XCTAssertEqual(avg.b, 1, accuracy: 0.001)
    }

    func testAverageOfBottomBandIsRed() throws {
        let px = splitBuffer(width: 64, height: 40)
        let avg = try XCTUnwrap(LockScreenTint.average(rgba: px, width: 64, height: 40, x: 0...1, y: 0.6...1))
        XCTAssertEqual(avg.r, 1, accuracy: 0.001)
        XCTAssertEqual(avg.b, 0, accuracy: 0.001)
    }

    func testAverageMixesHalfAndHalf() throws {
        let px = splitBuffer(width: 10, height: 10)
        let avg = try XCTUnwrap(LockScreenTint.average(rgba: px, width: 10, height: 10, x: 0...1, y: 0...1))
        XCTAssertEqual(avg.r, 0.5, accuracy: 0.001)
        XCTAssertEqual(avg.b, 0.5, accuracy: 0.001)
    }

    func testAverageRejectsShortBufferAndEmptyImage() {
        XCTAssertNil(LockScreenTint.average(rgba: [0, 0, 0], width: 2, height: 2, x: 0...1, y: 0...1))
        XCTAssertNil(LockScreenTint.average(rgba: [], width: 0, height: 0, x: 0...1, y: 0...1))
    }

    func testUnreadableWallpaperGivesNil() {
        XCTAssertNil(LockScreenTint.color(forWallpaperAt: URL(fileURLWithPath: "/nao/existe/wallpaper.heic")))
        XCTAssertNil(LockScreenTint.color(forWallpaperAt: URL(fileURLWithPath: "/tmp")))
    }

    private func solidPNG(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cove-tint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("wall.png")
        let img = NSImage(size: NSSize(width: 8, height: 8))
        img.lockFocus()
        NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        img.unlockFocus()
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
        return url
    }

    func testSolidWallpaperProducesLightenedHue() throws {
        let url = try solidPNG(hue: 0.75, saturation: 0.9, brightness: 0.5)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let tint = try XCTUnwrap(LockScreenTint.color(forWallpaperAt: url))
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tint.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        XCTAssertEqual(h, 0.75, accuracy: 0.03)
        XCTAssertGreaterThanOrEqual(b, 0.87)
        XCTAssertLessThan(s, 0.6)
        XCTAssertTrue(LockScreenTint.isLight(tint))
    }

    func testLightWallpaperProducesDarkTint() throws {
        let url = try solidPNG(hue: 0.12, saturation: 0.15, brightness: 0.96)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let tint = try XCTUnwrap(LockScreenTint.color(forWallpaperAt: url))
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tint.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        XCTAssertEqual(b, 0.22, accuracy: 0.02)
        XCTAssertFalse(LockScreenTint.isLight(tint))
    }
}
