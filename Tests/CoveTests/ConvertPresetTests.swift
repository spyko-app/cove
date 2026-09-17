import Foundation
import Testing
@testable import Cove

struct ConvertPresetTests {
    @Test func videoExtensionsMapToVideoPresets() {
        #expect(ConvertPreset.presets(forExtension: "mov") == [.mp4H264, .m4aAAC, .movProRes422])
        #expect(ConvertPreset.presets(forExtension: "mp4") == [.mp4H264, .m4aAAC, .movProRes422])
        #expect(ConvertPreset.presets(forExtension: "m4v") == [.mp4H264, .m4aAAC, .movProRes422])
    }

    @Test func audioExtensionsMapToAudioPreset() {
        for ext in ["m4a", "mp3", "wav", "aiff", "caf"] {
            #expect(ConvertPreset.presets(forExtension: ext) == [.m4aAAC])
        }
    }

    @Test func imageExtensionsMapToImagePresets() {
        for ext in ["png", "jpg", "jpeg", "heic", "tiff", "gif"] {
            #expect(ConvertPreset.presets(forExtension: ext) == [.pdfFromImages, .pngFromImage, .jpgFromImage])
        }
    }

    @Test func pdfExtensionMapsToJPGPreset() {
        #expect(ConvertPreset.presets(forExtension: "pdf") == [.jpgFromPDF])
    }

    @Test func unknownExtensionReturnsEmpty() {
        #expect(ConvertPreset.presets(forExtension: "docx") == [])
        #expect(ConvertPreset.presets(forExtension: "") == [])
    }

    @Test func caseInsensitiveExtension() {
        #expect(ConvertPreset.presets(forExtension: "MOV") == [.mp4H264, .m4aAAC, .movProRes422])
        #expect(ConvertPreset.presets(forExtension: "PDF") == [.jpgFromPDF])
        #expect(ConvertPreset.presets(forExtension: "PnG") == [.pdfFromImages, .pngFromImage, .jpgFromImage])
    }

    @Test func partitionSeparatesSupportedFromUnsupported() {
        let supportedURL = URL(fileURLWithPath: "/tmp/video.mov")
        let unsupportedURL = URL(fileURLWithPath: "/tmp/doc.docx")
        let noExtURL = URL(fileURLWithPath: "/tmp/noext")
        let result = ConvertPreset.partition([supportedURL, unsupportedURL, noExtURL])
        #expect(result.supported == [supportedURL])
        #expect(result.unsupported == [unsupportedURL, noExtURL])
    }

    @Test func partitionWithAllSupportedReturnsEmptyUnsupported() {
        let urls = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.pdf")]
        let result = ConvertPreset.partition(urls)
        #expect(result.supported == urls)
        #expect(result.unsupported.isEmpty)
    }

    @Test func outputExtensions() {
        #expect(ConvertPreset.mp4H264.outputExtension == "mp4")
        #expect(ConvertPreset.m4aAAC.outputExtension == "m4a")
        #expect(ConvertPreset.movProRes422.outputExtension == "mov")
        #expect(ConvertPreset.pdfFromImages.outputExtension == "pdf")
        #expect(ConvertPreset.jpgFromPDF.outputExtension == "jpg")
        #expect(ConvertPreset.pngFromImage.outputExtension == "png")
        #expect(ConvertPreset.jpgFromImage.outputExtension == "jpg")
    }
}
