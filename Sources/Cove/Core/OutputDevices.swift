import CoreAudio
import Foundation

@MainActor
final class OutputDevices: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: AudioObjectID
        let name: String
        let transport: UInt32
        var symbol: String {
            switch transport {
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                return name.lowercased().contains("airpods") ? "airpods" : "headphones"
            case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
            case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeDisplayPort,
                 kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeThunderbolt:
                return "hifispeaker"
            default: return "laptopcomputer"
            }
        }
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var current: Device?

    private static var devicesAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private static var defaultAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    init() {
        refresh()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.devicesAddr, .main, block)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultAddr, .main, block)
    }

    func refresh() {
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &Self.devicesAddr, 0, nil, &size) == noErr
        else { return }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.devicesAddr, 0, nil, &size, &ids)
        var defaultID = AudioObjectID(kAudioObjectUnknown)
        var dsize = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultAddr, 0, nil, &dsize, &defaultID)

        devices = ids.compactMap { id in
            guard outputChannels(id) > 0, let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Device(id: id, name: name, transport: uint32(id, kAudioDevicePropertyTransportType))
        }
        current = devices.first { $0.id == defaultID }
    }

    func select(_ d: Device) {
        var id = d.id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultAddr, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &id)
    }

    private func outputChannels(_ id: AudioObjectID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return 0 }
        let list = buf.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func string(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func uint32(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v)
        return v
    }
}
