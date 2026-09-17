import Foundation

enum ConvertPreset: String, CaseIterable {
    case mp4H264
    case m4aAAC
    case movProRes422
    case pdfFromImages
    case jpgFromPDF
    case pngFromImage
    case jpgFromImage

    var label: String {
        switch self {
        case .mp4H264: "Vídeo MP4 (H.264)"
        case .m4aAAC: "Áudio M4A (AAC)"
        case .movProRes422: "Vídeo MOV (ProRes 422)"
        case .pdfFromImages: "PDF a partir das imagens"
        case .jpgFromPDF: "JPG por página"
        case .pngFromImage: "Imagem PNG"
        case .jpgFromImage: "Imagem JPG"
        }
    }

    var outputExtension: String {
        switch self {
        case .mp4H264: "mp4"
        case .m4aAAC: "m4a"
        case .movProRes422: "mov"
        case .pdfFromImages: "pdf"
        case .jpgFromPDF: "jpg"
        case .pngFromImage: "png"
        case .jpgFromImage: "jpg"
        }
    }

    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    private static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aiff", "caf"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]
    private static let pdfExtensions: Set<String> = ["pdf"]

    static func presets(forExtension ext: String) -> [ConvertPreset] {
        let normalized = ext.lowercased()
        if videoExtensions.contains(normalized) { return [.mp4H264, .m4aAAC, .movProRes422] }
        if audioExtensions.contains(normalized) { return [.m4aAAC] }
        if imageExtensions.contains(normalized) { return [.pdfFromImages, .pngFromImage, .jpgFromImage] }
        if pdfExtensions.contains(normalized) { return [.jpgFromPDF] }
        return []
    }

    static func partition(_ urls: [URL]) -> (supported: [URL], unsupported: [URL]) {
        var supported: [URL] = []
        var unsupported: [URL] = []
        for url in urls {
            if presets(forExtension: url.pathExtension).isEmpty {
                unsupported.append(url)
            } else {
                supported.append(url)
            }
        }
        return (supported, unsupported)
    }
}
