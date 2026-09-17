import ApplicationServices
import AVFoundation
import CoreGraphics
import EventKit
import Foundation
import Speech

@MainActor
final class PermissionState: ObservableObject {
    @Published private(set) var accessibility = false
    @Published private(set) var calendar = false
    @Published private(set) var screenRecording = false
    @Published private(set) var microphone = false
    @Published private(set) var speech = false
    @Published private(set) var notifications = false
    @Published var audioCapture = false
    @Published var bluetooth = false

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

    nonisolated static func summary(_ states: [String: Bool]) -> String {
        let total = states.count
        let granted = states.values.filter { $0 }.count
        return "\(granted) de \(total) concedidas"
    }
}
