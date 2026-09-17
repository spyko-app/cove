import AppKit
import QuickLookUI

/// Controlador do `QLPreviewPanel` pra pré-visualizar um resultado da busca
/// sem sair da ilha. Implementa o protocolo de controle de painel do
/// QuickLook (`acceptsPreviewPanelControl`/`begin`/`end`) como um `NSResponder`
/// próprio — é ele quem instala `dataSource`/`delegate` e devolve o painel
/// pro nível certo, em vez de depender da cadeia de responders da janela.
///
/// O painel do notch vive no nível `.screenSaver` (`NotchPanel.swift:214`,
/// mesmo truque de `NotchActions.popMenu`); o `QLPreviewPanel` nasce num
/// nível mais baixo e ficaria atrás da ilha se não abaixássemos os painéis
/// enquanto o preview está aberto — restaura ao fechar (`willCloseNotification`
/// no painel compartilhado, e também em `dismiss()`).
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

    // MARK: - QLPreviewPanelController (categoria em NSResponder)

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
        // `closeObserver` como guarda de idempotência: willClose e
        // endPreviewPanelControl podem chamar isto duas vezes pro mesmo
        // painel — o contador de pushLoweredLevel/popLoweredLevel não é
        // tolerante a chamada dupla como `setPanelsLevel` direto era.
        guard let closeObserver else { return }
        NotificationCenter.default.removeObserver(closeObserver)
        self.closeObserver = nil
        NotchPanelController.current?.popLoweredLevel()
    }

    // MARK: - QLPreviewPanelDataSource / Delegate

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { url == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { url as NSURL? }
    }

    /// Sem frame de origem conhecido (linha da lista SwiftUI não expõe rect
    /// de tela facilmente) — `.zero` faz o painel abrir com fade simples.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        .zero
    }
}
