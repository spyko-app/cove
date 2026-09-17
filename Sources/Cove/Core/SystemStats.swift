import Darwin
import Foundation

nonisolated enum StatsFormat {
    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 0
        return f
    }()

    static func bytes(_ b: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(b)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        }
        let n = numberFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        return "\(n) \(units[unitIndex])"
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        bytes(UInt64(max(bytesPerSecond, 0))) + "/s"
    }

    static func percent(_ p: Double) -> String {
        "\(Int(p.clamped(to: 0...100).rounded()))%"
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

@MainActor
final class SystemStats: ObservableObject {
    @Published private(set) var cpuPercent: Double = 0
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var diskFree: UInt64 = 0
    @Published private(set) var diskTotal: UInt64 = 0
    @Published private(set) var networkUpRate: Double = 0
    @Published private(set) var networkDownRate: Double = 0

    private var timer: Timer?
    private var lastCPUTicks: (used: UInt64, total: UInt64)?
    private var lastNetSample: (up: UInt64, down: UInt64, date: Date)?
    private lazy var activeCount = ActiveCount(onFirst: { [weak self] in self?.start() },
                                                onLast: { [weak self] in self?.stop() })

    func retain() { activeCount.retain() }
    func release() { activeCount.release() }

    private func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        lastCPUTicks = nil
        lastNetSample = nil
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleDisk()
        sampleNetwork()
    }

    private func sampleCPU() {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount
        )
        guard result == KERN_SUCCESS, let infoArray else { return }
        defer {
            let size = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), size)
        }

        let cpuLoad = infoArray.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { ptr in
            UnsafeBufferPointer(start: ptr, count: Int(infoCount))
        }

        var used: UInt64 = 0
        var total: UInt64 = 0
        for i in 0..<Int(cpuCount) {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt64(cpuLoad[base + Int(CPU_STATE_USER)])
            let system = UInt64(cpuLoad[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(cpuLoad[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(cpuLoad[base + Int(CPU_STATE_IDLE)])
            used += user + system + nice
            total += user + system + nice + idle
        }

        if let last = lastCPUTicks {
            let usedDelta = used >= last.used ? used - last.used : 0
            let totalDelta = total >= last.total ? total - last.total : 0
            if totalDelta > 0 {
                cpuPercent = (Double(usedDelta) / Double(totalDelta)) * 100
            }
        }
        lastCPUTicks = (used, total)
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let used = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
        memoryUsed = used
        memoryTotal = ProcessInfo.processInfo.physicalMemory
    }

    private func sampleDisk() {
        let root = URL(fileURLWithPath: "/")
        guard let values = try? root.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ]) else { return }
        if let available = values.volumeAvailableCapacityForImportantUsage {
            diskFree = UInt64(max(available, 0))
        }
        if let total = values.volumeTotalCapacity {
            diskTotal = UInt64(max(total, 0))
        }
    }

    private func sampleNetwork() {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return }
        defer { freeifaddrs(ifaddrPtr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            defer { cursor = addr.pointee.ifa_next }
            let flags = Int32(addr.pointee.ifa_flags)
            guard flags & IFF_LOOPBACK == 0, flags & IFF_UP != 0 else { continue }
            guard addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = addr.pointee.ifa_data
            else { continue }
            let netData = data.withMemoryRebound(to: if_data.self, capacity: 1) { $0.pointee }
            totalIn += UInt64(netData.ifi_ibytes)
            totalOut += UInt64(netData.ifi_obytes)
        }

        let now = Date()
        if let last = lastNetSample {
            let elapsed = now.timeIntervalSince(last.date)
            if elapsed > 0 {
                let downDelta = totalIn >= last.down ? totalIn - last.down : 0
                let upDelta = totalOut >= last.up ? totalOut - last.up : 0
                networkDownRate = Double(downDelta) / elapsed
                networkUpRate = Double(upDelta) / elapsed
            }
        }
        lastNetSample = (up: totalOut, down: totalIn, date: now)
    }
}
