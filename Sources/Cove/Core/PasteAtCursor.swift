import AppKit
import CoreGraphics
import os

/// Cola texto no app frontal via ⌘V sintético (CGEvent), restaurando o
/// clipboard anterior 300ms depois. Exige Acessibilidade (`AXIsProcessTrusted`);
/// sem permissão o chamador cai em "copiado" (só pasteboard, sem colar).
@MainActor
enum PasteAtCursor {
    private static let logger = Logger(subsystem: "app.cove.notch", category: "paste")
    /// Último app frontal que NÃO é o Cove — usado quando a própria
    /// ilha está em foco no momento do clique (ex.: RecordCard) e precisamos
    /// colar no app que estava aberto antes.
    private(set) static var lastForeignFrontmost: NSRunningApplication?

    /// Chamado logo após cada escrita própria no pasteboard geral (texto temporário
    /// e restauração), pra o `ClipboardStore` não reingerir o próprio trânsito.
    /// Ligado em `NotchCoordinator.init` a `clipboard.acknowledgeOwnWrite()`.
    static var onOwnWrite: (@MainActor () -> Void)?

    /// Task de restauração em voo — pastes disparados em sequência rápida
    /// cancelam a restauração anterior e esperam ela terminar antes de escrever
    /// o próprio texto, pra nunca fotografar um pasteboard transiente.
    private static var inFlight: Task<Void, Never>?

    private static var tracking = false

    static func startTrackingFrontmost() {
        guard !tracking else { return }
        tracking = true
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                Task { @MainActor in lastForeignFrontmost = app }
            }
        }
    }

    /// Regra pura: cola só se confiado, há um app frontal, e ele não é o próprio Cove.
    static func shouldPaste(trusted: Bool, frontmostBundleID: String?, selfBundleID: String) -> Bool {
        guard trusted, let frontmostBundleID else { return false }
        return frontmostBundleID != selfBundleID
    }

    /// Cola `text` no app frontal (ou no último app não-Cove, se a ilha
    /// estiver em foco). Retorna false se não deu pra colar (chamador cai em copiar).
    @discardableResult
    static func paste(_ text: String) -> Bool {
        let selfBundleID = Bundle.main.bundleIdentifier ?? "app.cove.notch"
        var target = NSWorkspace.shared.frontmostApplication
        if target?.bundleIdentifier == selfBundleID {
            target = lastForeignFrontmost
        }
        guard shouldPaste(trusted: AXIsProcessTrusted(), frontmostBundleID: target?.bundleIdentifier, selfBundleID: selfBundleID)
        else { return false }

        let pb = NSPasteboard.general
        let previous = inFlight

        let activated = target?.activate(options: []) ?? false
        guard activated else {
            logger.error("activation failed for target app \(target?.bundleIdentifier ?? "nil", privacy: .public)")
            return false
        }

        inFlight = Task {
            // Espera a restauração anterior terminar (ou cancela e aguarda o
            // cleanup dela) antes de fotografar o pasteboard — senão duas
            // pastes em menos de 450ms podem snapshotar o texto transiente
            // da paste anterior em vez do clipboard real do usuário.
            if let previous {
                previous.cancel()
                await previous.value
            }

            let snapshot = snapshotItems(pb)

            pb.clearContents()
            pb.setString(text, forType: .string)
            onOwnWrite?()

            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else {
                restore(pb, snapshot)
                onOwnWrite?()
                return
            }
            postCommandV()
            try? await Task.sleep(nanoseconds: 300_000_000)
            restore(pb, snapshot)
            onOwnWrite?()
        }
        return true
    }

    private static func snapshotItems(_ pb: NSPasteboard) -> [[String: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type.rawValue] = data }
            }
            return dict
        }
    }

    private static func restore(_ pb: NSPasteboard, _ snapshot: [[String: Data]]) {
        pb.clearContents()
        let items = snapshot.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        guard !items.isEmpty else { return }
        pb.writeObjects(items)
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logger.error("event creation nil: CGEventSource failed")
            return
        }
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        guard let down, let up else {
            logger.error("event creation nil: CGEvent for ⌘V failed")
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
