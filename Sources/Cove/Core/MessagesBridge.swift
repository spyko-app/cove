import AppKit
import Foundation
import ScriptingBridge

/// Erros de envio via Messages.app — descrições já em pt-BR pro banner da UI.
enum MessagesError: Error, LocalizedError {
    case notRunning
    case recipientNotFound

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Abra o Mensagens antes de responder."
        case .recipientNotFound: return "Contato não encontrado no Mensagens."
        }
    }
}

/// Deriva o "handle" (telefone/e-mail) de uma notificação espelhada do
/// Mensagens — o título da notificação do iMessage é o NOME do contato, não
/// o handle, então na maioria dos casos não dá pra derivar com segurança.
/// Só resolve quando o título já parece um telefone ou e-mail; senão `nil`
/// (a UI cai pro nome como chave de busca em `participants`).
enum MessageTarget {
    /// DDI por região — só os mais comuns; fora da tabela devolve nil (sem chute).
    static func countryCallingCode(for region: String?) -> String? {
        switch region {
        case "BR": "55"
        case "US", "CA": "1"
        case "PT": "351"
        case "AR": "54"
        case "GB": "44"
        default: nil
        }
    }

    private static let phoneRegex = try! NSRegularExpression(pattern: #"^\+?[0-9 ()\-]{6,}$"#)

    static func handle(fromNotificationTitle title: String, body: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("@") { return trimmed.lowercased() }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if phoneRegex.firstMatch(in: trimmed, range: range) != nil {
            let hasDigit = trimmed.contains(where: \.isNumber)
            guard hasDigit else { return nil }
            let digits = trimmed.filter(\.isNumber)
            // Sem "+" explícito, número local (10–11 dígitos) ganha o DDI da região
            // atual (Mensagens guarda handles em E.164). Com "+" o DDI já veio.
            if !trimmed.hasPrefix("+"), (10...11).contains(digits.count),
               let ddi = Self.countryCallingCode(for: Locale.current.region?.identifier) {
                return "+" + ddi + digits
            }
            return "+" + digits
        }
        return nil
    }
}

/// Ponte ScriptingBridge com Messages.app — só ENVIA (`send:to:`), nunca lê
/// `chat.db` (T34: prova manual, leitura só das notificações já espelhadas
/// pelo `NotificationMirror`). Segue o mesmo padrão do `PlayerBridge`:
/// `SBApplication(bundleIdentifier:)` + KVC dinâmico, sem header gerado, e
/// nunca auto-lança o app — `isAvailable` exige `isRunning`. A 1ª chamada de
/// `send` dispara o TCC de Automation (`NSAppleEventsUsageDescription`).
@MainActor
final class MessagesBridge {
    static let bundleID = "com.apple.MobileSMS"

    /// App instalado E rodando — nunca auto-lança pra oferecer "responder".
    var isAvailable: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) != nil && isRunning
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    /// Envia `text` pro participante cujo handle/nome bate com `handle`.
    /// Busca em `participants` (KVC `handle`/`name`/`fullName` — Messages
    /// expõe os três) porque o handle nem sempre é derivável da notificação.
    func send(_ text: String, toHandle handle: String) throws {
        guard isRunning else { throw MessagesError.notRunning }
        guard let app = SBApplication(bundleIdentifier: Self.bundleID) else { throw MessagesError.notRunning }
        guard let buddy = participant(in: app, matching: handle) else { throw MessagesError.recipientNotFound }
        _ = app.perform(NSSelectorFromString("send:to:"), with: text, with: buddy)
    }

    private func participant(in app: SBApplication, matching handle: String) -> AnyObject? {
        guard let participants = app.value(forKey: "participants") as? SBElementArray else { return nil }
        for element in participants {
            guard let participant = element as? SBObject else { continue }
            let h = participant.value(forKey: "handle") as? String
            let name = participant.value(forKey: "name") as? String
            let fullName = participant.value(forKey: "fullName") as? String
            if h == handle || name == handle || fullName == handle {
                return participant
            }
        }
        return nil
    }
}
