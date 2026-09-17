import AppKit
import CoreWLAN
import Darwin
import Foundation
import Network

/// Wi-Fi, hotspot e drives externos — peek na ilha. SSID pode vir nil sem
/// permissão de Localização no macOS 14+; nunca pedimos essa permissão aqui.
@MainActor
final class NetworkHUDService: NSObject {
    struct NetState: Equatable {
        var wifiPowered = true
        var wifiSSID: String?
        var hotspotOn = false
        var mountedDrives: Set<String> = []
    }

    /// Janela de graça após o boot: monta/desmonta em massa (Time Machine,
    /// shares de rede reconectando) não deve virar peek na ilha.
    private static let mountGracePeriod: TimeInterval = 5

    var onActivity: ((NotchActivity) -> Void)?

    private(set) var state = NetState()
    /// false quando o CoreWLAN recusou o monitoramento (raro, mas silencioso
    /// antes) — a UI de Ajustes mostra um aviso quando isto é false.
    private(set) var wifiMonitoringAvailable = true
    private let wifiClient = CWWiFiClient.shared()
    private let pathMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let pathQueue = DispatchQueue(label: "cove.networkhud.path")
    private let launchTime = Date()
    private let isWifiHUDEnabled: () -> Bool
    private var hotspotPollTimer: Timer?

    init(isWifiHUDEnabled: @escaping () -> Bool = { true }) {
        self.isWifiHUDEnabled = isWifiHUDEnabled
        super.init()
        if let iface = wifiClient.interface() {
            state.wifiPowered = iface.powerOn()
            state.wifiSSID = iface.ssid()
        }
        wifiClient.delegate = self
        do {
            try wifiClient.startMonitoringEvent(with: .ssidDidChange)
            try wifiClient.startMonitoringEvent(with: .powerDidChange)
            try wifiClient.startMonitoringEvent(with: .linkDidChange)
        } catch {
            FileHandle.standardError.write(Data("NetworkHUDService: falha ao monitorar Wi-Fi: \(error)\n".utf8))
            wifiMonitoringAvailable = false
        }

        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.refreshHotspotState() }
        }
        pathMonitor.start(queue: pathQueue)

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isWifiHUDEnabled() else { return }
                self.refreshHotspotState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hotspotPollTimer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(volumeMounted(_:)),
            name: NSWorkspace.didMountNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(volumeUnmounted(_:)),
            name: NSWorkspace.didUnmountNotification, object: nil)
    }

    deinit {
        pathMonitor.cancel()
        hotspotPollTimer?.invalidate()
    }

    /// Estado anterior → novo → atividade emitida (nil quando nada mudou de fato).
    static func activity(previous: NetState, next: NetState) -> NotchActivity? {
        if previous.wifiPowered != next.wifiPowered {
            return .wifi(ssid: next.wifiPowered ? next.wifiSSID : nil, connected: next.wifiPowered)
        }
        if next.wifiPowered, previous.wifiSSID != next.wifiSSID {
            return .wifi(ssid: next.wifiSSID, connected: next.wifiSSID != nil)
        }
        if previous.hotspotOn != next.hotspotOn {
            return .hotspot(on: next.hotspotOn)
        }
        if previous.mountedDrives != next.mountedDrives {
            if let name = next.mountedDrives.subtracting(previous.mountedDrives).first {
                return .drive(name: name, mounted: true)
            }
            if let name = previous.mountedDrives.subtracting(next.mountedDrives).first {
                return .drive(name: name, mounted: false)
            }
        }
        return nil
    }

    /// Filtro puro pro peek de montagem: só reporta mídia removível/ejetável
    /// LOCAL (pendrive/HD externo), fora da janela de graça do boot — nunca
    /// Time Machine, .dmg, share de rede ou volume montado logo no launch.
    static func shouldReport(removable: Bool, ejectable: Bool, local: Bool, sinceLaunch: TimeInterval) -> Bool {
        guard sinceLaunch >= mountGracePeriod, local else { return false }
        return removable || ejectable
    }

    /// Puro: bridge100(+) UP com IPv4 = este Mac compartilhando internet
    /// (Personal Hotspot / Internet Sharing). Não confunde com Wi-Fi metered.
    static func isHotspotInterface(name: String, isUp: Bool, hasIPv4: Bool) -> Bool {
        name.hasPrefix("bridge") && isUp && hasIPv4
    }

    private func transition(_ mutate: (inout NetState) -> Void) {
        let previous = state
        var next = previous
        mutate(&next)
        state = next
        if let a = Self.activity(previous: previous, next: next) {
            onActivity?(a)
        }
    }

    private func refreshHotspotState() {
        transition { $0.hotspotOn = Self.detectHotspotActive() }
    }

    private static func detectHotspotActive() -> Bool {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return false }
        defer { freeifaddrs(ifaddrPtr) }

        var byName: [String: (up: Bool, hasIPv4: Bool)] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = ptr?.pointee {
            let name = String(cString: iface.ifa_name)
            let up = (Int32(iface.ifa_flags) & IFF_UP) == IFF_UP
            let hasIPv4 = iface.ifa_addr?.pointee.sa_family == sa_family_t(AF_INET)
            var entry = byName[name] ?? (up: false, hasIPv4: false)
            entry.up = entry.up || up
            entry.hasIPv4 = entry.hasIPv4 || hasIPv4
            byName[name] = entry
            ptr = iface.ifa_next
        }
        return byName.contains { name, v in isHotspotInterface(name: name, isUp: v.up, hasIPv4: v.hasIPv4) }
    }

    @objc private func volumeMounted(_ note: Notification) {
        guard let name = note.userInfo?[NSWorkspace.localizedVolumeNameUserInfoKey] as? String else { return }
        let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
        let values = try? url?.resourceValues(forKeys: [
            .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey,
        ])
        let sinceLaunch = Date().timeIntervalSince(launchTime)
        guard Self.shouldReport(
            removable: values?.volumeIsRemovable ?? false,
            ejectable: values?.volumeIsEjectable ?? false,
            local: values?.volumeIsLocal ?? false,
            sinceLaunch: sinceLaunch
        ) else { return }
        transition { $0.mountedDrives.insert(name) }
    }

    @objc private func volumeUnmounted(_ note: Notification) {
        guard let name = note.userInfo?[NSWorkspace.localizedVolumeNameUserInfoKey] as? String else { return }
        guard state.mountedDrives.contains(name) else { return }
        transition { $0.mountedDrives.remove(name) }
    }
}

extension NetworkHUDService: CWEventDelegate {
    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            guard let self, let iface = self.wifiClient.interface(withName: interfaceName) else { return }
            self.transition { $0.wifiSSID = iface.ssid() }
        }
    }

    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            guard let self, let iface = self.wifiClient.interface(withName: interfaceName) else { return }
            self.transition { $0.wifiPowered = iface.powerOn() }
        }
    }

    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            guard let self, let iface = self.wifiClient.interface(withName: interfaceName) else { return }
            self.transition { $0.wifiSSID = iface.ssid() }
        }
    }
}
