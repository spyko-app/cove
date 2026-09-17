import AppKit
import SwiftUI

/// Janela do editor de captura: setas, retângulo, borrão, badges numeradas
/// e fundo/padding, com exportação pra PNG via `ImageRenderer`.
@MainActor
final class CaptureEditorManager: NSObject, NSWindowDelegate {
    static let shared = CaptureEditorManager()
    private var window: NSWindow?

    func open(image url: URL, onExport: @escaping (URL) -> Void) {
        if window != nil { close() }
        guard let image = NSImage(contentsOf: url) else { return }
        let w = NSWindow(contentViewController: NSHostingController(
            rootView: CaptureEditorRoot(image: image, sourceURL: url, onExport: { [weak self] out in
                onExport(out)
                self?.close()
            }, onCancel: { [weak self] in self?.close() })))
        w.title = "Editar captura"
        w.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.setContentSize(NSSize(width: 900, height: 640))
        w.minSize = NSSize(width: 640, height: 420)
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window = w
    }

    private func close() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private enum BackgroundChoice: String, CaseIterable, Identifiable {
    case none = "Nenhum"
    case dark = "Escuro"
    case light = "Claro"
    case gradient = "Gradiente"
    var id: String { rawValue }

    var style: BackgroundStyle {
        switch self {
        case .none: .none
        case .dark: .solid("#1C1C1E")
        case .light: .solid("#F2F2F7")
        case .gradient: .gradient("aurora")
        }
    }
}

private let annotationColors: [String] = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#0A84FF"]

struct CaptureEditorRoot: View {
    let image: NSImage
    let sourceURL: URL
    let onExport: (URL) -> Void
    let onCancel: () -> Void

    @State private var doc = AnnotationDocument()
    @State private var tool: AnnotationTool = .arrow
    @State private var color: String = annotationColors[0]
    @State private var background: BackgroundChoice = .none
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var previewCanvasSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geo in
                let canvasSize = fittedSize(in: geo.size)
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Canvas { context, size in
                        draw(in: &context, size: size, referenceWidth: size.width)
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .background(backgroundView)
                    .gesture(dragGesture(canvasSize: canvasSize))
                }
                .onAppear { previewCanvasSize = canvasSize }
                .onChange(of: canvasSize) { _, new in previewCanvasSize = new }
            }
            .padding(16)
        }
        .frame(minWidth: 640, minHeight: 420)
        .onChange(of: background) { _, new in doc.background = new.style }
        .background {
            KeyCatcher(
                onUndo: { doc.undo() },
                onExport: { export() },
                onCopy: { copyToPasteboard() },
                onCancel: onCancel
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Picker("Ferramenta", selection: $tool) {
                Label("Seta", systemImage: "arrow.up.right").tag(AnnotationTool.arrow)
                Label("Retângulo", systemImage: "rectangle").tag(AnnotationTool.rect)
                Label("Borrão", systemImage: "aqi.medium").tag(AnnotationTool.blur)
                Label("Número", systemImage: "1.circle").tag(AnnotationTool.badge)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .frame(width: 180)

            HStack(spacing: 6) {
                ForEach(annotationColors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.white, lineWidth: color == hex ? 2 : 0))
                        .onTapGesture { color = hex }
                }
            }

            Picker("Fundo", selection: $background) {
                ForEach(BackgroundChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 140)

            HStack(spacing: 6) {
                Text("Padding")
                Slider(value: $doc.padding, in: 0...80, step: 1).frame(width: 100)
            }

            Spacer()

            Button("Desfazer") { doc.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("Copiar") { copyToPasteboard() }
                .keyboardShortcut("c", modifiers: .command)
            Button("Exportar") { export() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
            Button("Cancelar") { onCancel() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(12)
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch doc.background {
        case .none:
            Color.clear
        case .solid(let hex):
            Color(hex: hex)
        case .gradient:
            LinearGradient(colors: [Color(hex: "#5E5CE6"), Color(hex: "#FF375F")],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return available }
        let scale = min(available.width / imgSize.width, available.height / imgSize.height, 1)
        return CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
    }

    private func dragGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: tool == .badge ? 0 : 2)
            .onChanged { value in
                if dragStart == nil { dragStart = value.startLocation }
                dragCurrent = value.location
            }
            .onEnded { value in
                let start = dragStart ?? value.startLocation
                let end = tool == .badge ? start : value.location
                doc.add(tool: tool, from: normalize(start, in: canvasSize), to: normalize(end, in: canvasSize), color: color)
                dragStart = nil
                dragCurrent = nil
            }
    }

    private func normalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: point.x / size.width, y: point.y / size.height)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, referenceWidth: CGFloat) {
        let scale = AnnotationDocument.strokeScale(exportWidth: size.width, previewWidth: referenceWidth)
        context.draw(Image(nsImage: image), in: CGRect(origin: .zero, size: size))
        for annotation in doc.annotations {
            drawAnnotation(annotation, in: &context, size: size, scale: scale)
        }
        if let start = dragStart, let current = dragCurrent, tool != .badge {
            var previewContext = context
            let preview = Annotation(tool: tool, from: normalize(start, in: size), to: normalize(current, in: size), color: color)
            drawAnnotation(preview, in: &previewContext, size: size, scale: scale)
        }
    }

    private func drawAnnotation(_ a: Annotation, in context: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        let from = CGPoint(x: a.from.x * size.width, y: a.from.y * size.height)
        let to = CGPoint(x: a.to.x * size.width, y: a.to.y * size.height)
        let strokeColor = Color(hex: a.color)
        switch a.tool {
        case .arrow:
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(strokeColor), lineWidth: 3 * scale)
            drawArrowHead(from: from, to: to, in: &context, color: strokeColor, scale: scale)
        case .rect:
            let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                               width: abs(to.x - from.x), height: abs(to.y - from.y))
            context.stroke(Path(rect), with: .color(strokeColor), lineWidth: 3 * scale)
        case .blur:
            let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                               width: abs(to.x - from.x), height: abs(to.y - from.y))
            guard rect.width > 1, rect.height > 1 else { return }
            let cropRect = CGRect(x: rect.minX / size.width * image.size.width,
                                   y: (1 - rect.maxY / size.height) * image.size.height,
                                   width: rect.width / size.width * image.size.width,
                                   height: rect.height / size.height * image.size.height)
            if let cropped = crop(image, to: cropRect) {
                context.clip(to: Path(rect))
                context.draw(Image(nsImage: cropped).interpolation(.high), in: rect)
            }
        case .badge:
            let radius: CGFloat = 12 * scale
            let center = from
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                 width: radius * 2, height: radius * 2)),
                         with: .color(strokeColor))
            if let number = a.number {
                context.draw(Text("\(number)").font(.system(size: 12 * scale, weight: .bold)).foregroundColor(.white),
                             at: center)
            }
        }
    }

    private func drawArrowHead(from: CGPoint, to: CGPoint, in context: inout GraphicsContext, color: Color, scale: CGFloat) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let length: CGFloat = 12 * scale
        let spread: CGFloat = .pi / 7
        let p1 = CGPoint(x: to.x - length * cos(angle - spread), y: to.y - length * sin(angle - spread))
        let p2 = CGPoint(x: to.x - length * cos(angle + spread), y: to.y - length * sin(angle + spread))
        var head = Path()
        head.move(to: to)
        head.addLine(to: p1)
        head.move(to: to)
        head.addLine(to: p2)
        context.stroke(head, with: .color(color), lineWidth: 3 * scale)
    }

    private func crop(_ image: NSImage, to rect: CGRect) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = cgImage.cropping(to: rect) else { return nil }
        let blurred = applyBlur(cropped)
        return NSImage(cgImage: blurred ?? cropped, size: rect.size)
    }

    private func applyBlur(_ cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(12, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        return context.createCGImage(output, from: ciImage.extent)
    }

    private func renderedImage() -> NSImage {
        let canvasSize = image.size
        let padding = doc.padding
        let totalSize = CGSize(width: canvasSize.width + padding * 2, height: canvasSize.height + padding * 2)
        let referenceWidth = previewCanvasSize.width > 0 ? previewCanvasSize.width : canvasSize.width
        let content = ZStack {
            backgroundView
            Canvas { context, _ in
                context.translateBy(x: padding, y: padding)
                draw(in: &context, size: canvasSize, referenceWidth: referenceWidth)
            }
            .frame(width: totalSize.width, height: totalSize.height)
        }
        .frame(width: totalSize.width, height: totalSize.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.nsImage ?? image
    }

    private func export() {
        let rendered = renderedImage()
        guard let tiff = rendered.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let dir = AppSupport.file("captures")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = ExportNaming.uniqueExportName(base: base) { candidate in
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path)
        }
        let out = dir.appendingPathComponent(name)
        try? png.write(to: out)
        onExport(out)
    }

    private func copyToPasteboard() {
        let rendered = renderedImage()
        guard let tiff = rendered.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }
}

private extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        if s.count < 6 { s = "000000" }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

/// Repassa atalhos de teclado (⌘Z/⌘S/⌘C/Esc) pro editor via `NSView` invisível.
private struct KeyCatcher: NSViewRepresentable {
    let onUndo: () -> Void
    let onExport: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let v = KeyCatcherView()
        v.onUndo = onUndo
        v.onExport = onExport
        v.onCopy = onCopy
        v.onCancel = onCancel
        return v
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onUndo = onUndo
        nsView.onExport = onExport
        nsView.onCopy = onCopy
        nsView.onCancel = onCancel
    }
}

private final class KeyCatcherView: NSView {
    var onUndo: (() -> Void)?
    var onExport: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers else {
            if event.keyCode == 53 { onCancel?(); return }
            super.keyDown(with: event)
            return
        }
        switch chars {
        case "z": onUndo?()
        case "s": onExport?()
        case "c": onCopy?()
        default: super.keyDown(with: event)
        }
    }
}
