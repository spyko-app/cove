import CoreAudio
import Foundation

/// Volume/mute do dispositivo de saída padrão via CoreAudio, com listener —
/// alimenta o HUD de volume da ilha (substituto do HUD nativo).
@MainActor
final class AudioService {
    var onVolumeChange: ((Float, _ muted: Bool) -> Void)?

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    // 'vmvc' — kAudioHardwareServiceDeviceProperty_VirtualMainVolume (o header
    // AudioHardwareService não é exposto no Swift moderno)
    private static var volumeAddr = AudioObjectPropertyAddress(
        mSelector: AudioObjectPropertySelector(0x766D_7663),
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static var muteAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static var defaultOutAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    init() {
        attach()
        // troca de dispositivo padrão → re-anexa
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.attach() }
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutAddr, .main, block)
    }

    private func attach() {
        if deviceID != kAudioObjectUnknown, let old = listenerBlock {
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.volumeAddr, .main, old)
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.muteAddr, .main, old)
        }
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutAddr, 0, nil, &size, &id
        ) == noErr else { return }
        deviceID = id
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.emit() }
        }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(deviceID, &Self.volumeAddr, .main, block)
        AudioObjectAddPropertyListenerBlock(deviceID, &Self.muteAddr, .main, block)
    }

    var volume: Float {
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(deviceID, &Self.volumeAddr, 0, nil, &size, &v)
        return v
    }

    var muted: Bool {
        var m: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &Self.muteAddr, 0, nil, &size, &m)
        return m == 1
    }

    private func emit() {
        onVolumeChange?(volume, muted)
    }

    func setVolume(_ v: Float) {
        var vv = min(max(v, 0), 1)
        let size = UInt32(MemoryLayout<Float32>.size)
        _ = withUnsafeMutablePointer(to: &vv) {
            AudioObjectSetPropertyData(deviceID, &Self.volumeAddr, 0, nil, size, $0)
        }
    }

    func setMuted(_ m: Bool) {
        var mm: UInt32 = m ? 1 : 0
        _ = withUnsafeMutablePointer(to: &mm) {
            AudioObjectSetPropertyData(deviceID, &Self.muteAddr, 0, nil,
                                       UInt32(MemoryLayout<UInt32>.size), $0)
        }
    }
}
