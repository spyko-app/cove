import AudioToolbox
import CoreAudio
import Foundation

/// Waveform AO VIVO do áudio do sistema — Core Audio process tap global
/// (macOS 14.4+): CATapDescription → AudioHardwareCreateProcessTap → aggregate
/// device com o tap → IOProc lê buffers e publica níveis RMS suavizados.
/// TCC: NSAudioCaptureUsageDescription (prompt de captura no 1º uso).
@MainActor
final class WaveformService: ObservableObject {
    /// 5 barras, 0…1, suavizadas.
    @Published var levels: [Float] = Array(repeating: 0, count: 5)
    private(set) var running = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var ring: [Float] = []

    func start() {
        guard !running, AppEnvironment.isBundledApp else { return }  // TCC
        guard let desc = NSClassFromString("CATapDescription") as? NSObject.Type else { return }

        // tap global estéreo, mixdown, excluindo ninguém
        let tapDesc = desc.init()
        tapDesc.setValue(UUID(), forKey: "UUID")
        tapDesc.setValue([], forKey: "processes")
        tapDesc.setValue(true, forKey: "exclusive")  // global: todos exceto lista (vazia)
        tapDesc.setValue(true, forKey: "mixdown")
        tapDesc.setValue(false, forKey: "mono")
        tapDesc.setValue(true, forKey: "privateTap")

        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(tapDesc as? CATapDescription, &tap) == noErr,
              tap != kAudioObjectUnknown else { return }
        tapID = tap

        // aggregate device contendo só o tap
        guard let tapUID = tapDesc.value(forKey: "UUID") as? UUID else { return }
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "CoveTap",
            kAudioAggregateDeviceUIDKey as String: "app.cove.notch.tap",
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [kAudioSubTapUIDKey as String: tapUID.uuidString,
                 kAudioSubTapDriftCompensationKey as String: true]
            ],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &agg) == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            return
        }
        aggregateID = agg

        let handler: AudioDeviceIOBlock = { [weak self] _, inData, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inData))
            var sum: Float = 0
            var count = 0
            for buf in buffers {
                let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
                guard let p = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in stride(from: 0, to: n, by: 16) { sum += p[i] * p[i]; count += 1 }
            }
            guard count > 0 else { return }
            let rms = min(sqrt(sum / Float(count)) * 4, 1)
            Task { @MainActor in self?.push(rms) }
        }
        guard AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil, handler) == noErr,
              AudioDeviceStart(aggregateID, ioProcID) == noErr else {
            stop()
            return
        }
        running = true
    }

    func stop() {
        if let io = ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, io)
            AudioDeviceDestroyIOProcID(aggregateID, io)
        }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        ioProcID = nil
        aggregateID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown
        running = false
        levels = Array(repeating: 0, count: 5)
    }

    private var lastPublish = ContinuousClock.now
    private func push(_ rms: Float) {
        // IO block chega a ~100Hz; publicar @Published nessa taxa = relayout SwiftUI
        // contínuo (15% CPU medido). Acumula e publica a 30Hz, ignorando ruído.
        ring.append(rms)
        if ring.count > 5 { ring.removeFirst(ring.count - 5) }
        let now = ContinuousClock.now
        guard now - lastPublish >= .milliseconds(33) else { return }
        lastPublish = now
        // suaviza: 60% valor novo, 40% anterior
        var out = levels
        for i in 0..<5 {
            let v = i < ring.count ? ring[ring.count - 1 - i] : 0
            out[i] = out[i] * 0.4 + v * 0.6
        }
        if zip(out, levels).contains(where: { abs($0 - $1) > 0.02 }) { levels = out }
    }
}
