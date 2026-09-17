import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import IOKit
import LocalAuthentication
import Security

/// T2.0 — as três provas que gateiam o Rosto, rodadas pelo DONO (regra 5: o
/// agente nunca bloqueia a tela dele). Dispara só com `COVE_ROSTO_SPIKE`
/// no ambiente do .app empacotado; escreve em
/// ~/Library/Logs/Cove/rosto-spike.log. Apagado no fim de T2.
///
/// Valores: `1` = as três provas (a, b, c); `a` = só câmera no lock;
/// `b` = só cofre (Keychain); `c` = só Touch ID (LAContext). Combinações
/// (`bc`) também valem.
@MainActor
enum RostoSpike {
    private static var mode: String { ProcessInfo.processInfo.environment["COVE_ROSTO_SPIKE"] ?? "" }
    static var isRequested: Bool { !mode.isEmpty && mode != "0" }
    private static func wants(_ prova: Character) -> Bool { mode == "1" || mode.contains(prova) }

    private static var logURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Cove")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rosto-spike.log")
    }

    private static func log(_ s: String) {
        let line = "\(Date().formatted(.iso8601)) \(s)\n"
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: logURL) }
    }

    static func run() {
        guard isRequested, AppEnvironment.isBundledApp else { return }
        log("== spike início · modo=\(mode) · bundle=\(Bundle.main.bundlePath)")
        // Clamshell (incondicional: vale pras três provas). Tampa fechada →
        // sensor Touch ID inacessível (a política biométrica devolve -4 no CLI
        // E no bundle) e câmera embutida coberta: nenhum resultado decide nada.
        // Repetir com a tampa aberta.
        log("== tampa fechada=\(lidClosed().map(String.init) ?? "?") (true → repetir com a tampa aberta; -4 em [c] e frame preto em [a] não provam nada)")
        if wants("c") { log("[c] touchID canEvaluate=\(touchIDAvailable())") }
        if wants("b") { log("[b] keychain caminho=\(keychainPath())  (A = data-protection+biometryCurrentSet ok; B = fallback legado)") }
        guard wants("a") else { log("== spike fim — cole este arquivo no chat"); return }
        log("[a] câmera: bloqueie a tela nos próximos 15 s; capturando por 45 s…")
        Task { @MainActor in await cameraUnderLock() }
    }

    static func touchIDAvailable() -> String {
        let ctx = LAContext()
        var err: NSError?
        let ok = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        return ok ? "true biometry=\(ctx.biometryType.rawValue) stateHash=\(ctx.domainState.biometry.stateHash?.count ?? 0)B"
                  : "false erro=\(err?.code ?? 0) \(err?.localizedDescription ?? "")"
    }

    /// `AppleClamshellState` do IOPMrootDomain (nil = não conseguiu ler).
    static func lidClosed() -> Bool? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        return IORegistryEntryCreateCFProperty(svc, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    /// Mesma sondagem que vira `SecureCredential.probePath()` em T2.
    static func keychainPath() -> String {
        guard let ac = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.biometryCurrentSet], nil) else { return "B (SecAccessControl nil)" }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.cove.notch.rosto",
                                   kSecAttrAccount as String: "sonda-cofre", kSecUseDataProtectionKeychain as String: true]
        var add = base
        add[kSecAttrAccessControl as String] = ac
        add[kSecValueData as String] = Data([1])
        let status = SecItemAdd(add as CFDictionary, nil)
        SecItemDelete(base as CFDictionary)
        return (status == errSecSuccess || status == errSecDuplicateItem) ? "A (status \(status))" : "B (status \(status))"
    }

    static func cameraUnderLock() async {
        let cam = FaceCamera()
        // Permissão ANTES do start(): com `.notDetermined` e a tela já bloqueada,
        // o prompt de TCC fica pendurado até o desbloqueio e o resultado sairia
        // `comLock=0` por engano — o log precisa distinguir os dois casos.
        log("[a] permissão câmera antes=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue) (0 indeterminada · 1 restrita · 2 negada · 3 concedida)")
        do { try await cam.start() } catch { log("[a] start falhou: \(error.localizedDescription)"); return }
        var frames = 0, lockedFrames = 0, lastID: UInt64 = 0
        var size = CGSize.zero
        let end = Date().addingTimeInterval(45)
        var sawLock = false
        while Date() < end {
            try? await Task.sleep(for: .milliseconds(100))
            let locked = SystemEvents.isScreenActuallyLocked()
            if locked { sawLock = true }
            if let f = cam.latest, f.id != lastID {
                lastID = f.id; frames += 1; size = f.nativeSize
                if locked { lockedFrames += 1 }
            }
        }
        await cam.stop()
        // Qual câmera entregou: `builtInDevice()` cai em `AVCaptureDevice.default`
        // se não achar a embutida — com a tampa fechada isso pode ser a webcam
        // do monitor ou o iPhone, e o (a) "passaria" medindo o dispositivo errado.
        let camID = cam.cameraUniqueID ?? "?"
        let camNome = cam.cameraUniqueID.flatMap { AVCaptureDevice(uniqueID: $0)?.localizedName } ?? "?"
        log("[a] frames=\(frames) comLock=\(lockedFrames) nativo=\(Int(size.width))×\(Int(size.height)) viuLock=\(sawLock) efeitos=\(FaceCamera.ambientEffectsActive()) câmera=\"\(camNome)\" id=\(camID)")
        log("[a] idle teclado agora=\(CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown))s (verificar se o secure input do loginwindow zera)")
        log("== spike fim — cole este arquivo no chat")
    }
}
