import AppKit
import QuickLookUI

@MainActor
final class QuickLookController: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var url: URL?
    private var closeObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) não suportado")
    }

    func preview(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.reloadData()
            return
        }
        beginPreviewPanelControl(panel)
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        panel.orderOut(nil)
        endPreviewPanelControl(panel)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        NotchPanelController.current?.pushLoweredLevel()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restorePanelLevel() }
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        restorePanelLevel()
        panel.dataSource = nil
        panel.delegate = nil
    }

    private func restorePanelLevel() {
        guard let closeObserver else { return }
        NotificationCenter.default.removeObserver(closeObserver)
        self.closeObserver = nil
        NotchPanelController.current?.popLoweredLevel()
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { url == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { url as NSURL? }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        .zero
    }
}
