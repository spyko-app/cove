import Foundation
import IOBluetooth
import IOKit

final class BluetoothService: NSObject {
    var onDeviceEvent: (@Sendable (_ name: String, _ connected: Bool) -> Void)?

    override init() {
        super.init()
        IOBluetoothDevice.register(forConnectNotifications: self,
                                   selector: #selector(deviceConnected(_:device:)))
        for d in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        where d.isConnected() {
            d.register(forDisconnectNotification: self,
                       selector: #selector(deviceDisconnected(_:device:)))
        }
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification,
                                       device: IOBluetoothDevice) {
        onDeviceEvent?(device.name ?? "Dispositivo", true)
        device.register(forDisconnectNotification: self,
                        selector: #selector(deviceDisconnected(_:device:)))
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification,
                                          device: IOBluetoothDevice) {
        onDeviceEvent?(device.name ?? "Dispositivo", false)
        note.unregister()
    }

    static func appleDeviceBattery(named name: String) -> (left: Int?, right: Int?, case_: Int?)? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleDeviceManagementHIDEventService"), &iter) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iter) }
        while case let entry = IOIteratorNext(iter), entry != 0 {
            defer { IOObjectRelease(entry) }
            func prop(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue()
            }
            guard let product = prop("Product") as? String,
                  product.localizedCaseInsensitiveContains(name)
                    || name.localizedCaseInsensitiveContains(product)
            else { continue }
            return (prop("BatteryPercentLeft") as? Int,
                    prop("BatteryPercentRight") as? Int,
                    prop("BatteryPercentCase") as? Int)
        }
        return nil
    }
}
