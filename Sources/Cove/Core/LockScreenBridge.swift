import AppKit

enum LockScreenPolicy {
    static func shouldDelegate(locked: Bool, enabled: Bool, bridgeAvailable: Bool) -> Bool {
        locked && enabled && bridgeAvailable
    }

    static func allowsPeek(kindKey: String, locked: Bool) -> Bool {
        !(locked && kindKey == "notification")
    }
}

@MainActor
final class LockScreenBridge {
    private static let notificationCenterAtScreenLock: Int32 = 400

    static let shared: LockScreenBridge? = LockScreenBridge()

    static var isAvailable: Bool { shared != nil }

    private let connection: Int32
    private let space: Int32

    private typealias F_SLSMainConnectionID = @convention(c) () -> Int32
    private typealias F_SLSSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias F_SLSSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias F_SLSShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias F_SLSSpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

    private let addWindowsAndRemoveFromSpaces: F_SLSSpaceAddWindowsAndRemoveFromSpaces
    private let removeWindowsFromSpaces: F_SLSRemoveWindowsFromSpaces

    private static let debug = ProcessInfo.processInfo.environment["COVE_DEBUG"] != nil
    static func dlog(_ m: String) {
        if debug { FileHandle.standardError.write("[lockscreen] \(m)\n".data(using: .utf8)!) }
    }

    private init?() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            RTLD_NOW
        ) else {
            Self.dlog("dlopen(SkyLight) falhou — bridge indisponível")
            return nil
        }
        guard
            let mainConnectionSym = dlsym(handle, "SLSMainConnectionID"),
            let spaceCreateSym = dlsym(handle, "SLSSpaceCreate"),
            let setLevelSym = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let showSpacesSym = dlsym(handle, "SLSShowSpaces"),
            let addRemoveSym = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces"),
            let removeSym = dlsym(handle, "SLSRemoveWindowsFromSpaces")
        else {
            Self.dlog("dlsym de símbolo SLS* falhou — bridge indisponível")
            return nil
        }

        let mainConnectionID = unsafeBitCast(mainConnectionSym, to: F_SLSMainConnectionID.self)
        let spaceCreate = unsafeBitCast(spaceCreateSym, to: F_SLSSpaceCreate.self)
        let setAbsoluteLevel = unsafeBitCast(setLevelSym, to: F_SLSSpaceSetAbsoluteLevel.self)
        let showSpaces = unsafeBitCast(showSpacesSym, to: F_SLSShowSpaces.self)
        addWindowsAndRemoveFromSpaces = unsafeBitCast(addRemoveSym, to: F_SLSSpaceAddWindowsAndRemoveFromSpaces.self)
        removeWindowsFromSpaces = unsafeBitCast(removeSym, to: F_SLSRemoveWindowsFromSpaces.self)

        connection = mainConnectionID()
        space = spaceCreate(connection, 1, 0)
        _ = setAbsoluteLevel(connection, space, Self.notificationCenterAtScreenLock)
        _ = showSpaces(connection, [space] as CFArray)
        Self.dlog("bridge carregada — conn=\(connection) space=\(space) level=\(Self.notificationCenterAtScreenLock)")
    }

    func delegate(_ window: NSWindow) {
        let r = addWindowsAndRemoveFromSpaces(connection, space, [window.windowNumber] as CFArray, 7)
        Self.dlog("delegate win=\(window.windowNumber) → \(r)")
    }

    func undelegate(_ window: NSWindow) {
        let r = removeWindowsFromSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
        Self.dlog("undelegate win=\(window.windowNumber) → \(r)")
    }
}
