import ApplicationServices
import AVFoundation
import CoreGraphics
import EventKit
import Foundation
import Speech

/// Estado assíncrono das permissões do sistema, pro tour de onboarding.
/// Nunca bloqueia a main thread: cada checagem roda em `Task.detached` e só
/// publica o resultado de volta na main actor. Pedir a permissão em si
/// (accessibility, calendário) continua uma ação explícita do usuário.
@MainActor
final class PermissionState: ObservableObject {
    @Published private(set) var accessibility = false
    @Published private(set) var calendar = false
    @Published private(set) var screenRecording = false
    @Published private(set) var microphone = false
    @Published private(set) var speech = false
    @Published private(set) var notifications = false
    /// Não têm checagem TCC pública — refletem só a ação local do usuário nesta sessão.
    @Published var audioCapture = false
    @Published var bluetooth = false

    /// Reavalia todas as permissões sem travar a UI.
    func refresh(notificationsAvailable: Bool) async {
        notifications = notificationsAvailable

        async let ax = Task.detached { AXIsProcessTrusted() }.value
        async let cal = Task.detached { EKEventStore.authorizationStatus(for: .event) == .fullAccess }.value
        async let screen = Task.detached { CGPreflightScreenCaptureAccess() }.value
        async let mic = Task.detached { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }.value
        async let sp = Task.detached { SFSpeechRecognizer.authorizationStatus() == .authorized }.value

        accessibility = await ax
        calendar = await cal
        screenRecording = await screen
        microphone = await mic
        speech = await sp
    }

    /// "3 de 6 concedidas" — puro, sem estado do objeto, fácil de testar.
    nonisolated static func summary(_ states: [String: Bool]) -> String {
        let total = states.count
        let granted = states.values.filter { $0 }.count
        return "\(granted) de \(total) concedidas"
    }
}
