//
//  LockScreenBridge.swift
//  Cove
//
//  Ilha visível na tela de bloqueio via API PRIVADA do SkyLight (window
//  server): um "space" próprio em nível absoluto 400 — o mesmo em que a
//  Central de Notificações desenha por cima do loginwindow — e a janela do
//  painel é movida pra dentro dele SÓ enquanto a tela está bloqueada.
//
//  Adaptado de Lakr233/SkyLightWindow (MIT) — https://github.com/Lakr233/SkyLightWindow
//  via jonnyoo/glance `NotchOverlay/NotchSkyLight.swift` (MIT) — https://github.com/jonnyoo/glance
//
//  RISCO: `dlopen` de framework privado + símbolos C não documentados. A Apple
//  pode mudar/remover em qualquer macOS e o uso desqualifica a Mac App Store
//  (o Cove já é Developer ID fora da loja — mesmo trilho do MediaRemote).
//  `shared` é `nil` se qualquer símbolo faltar: o app degrada pra "ilha some
//  na tela de bloqueio" em vez de crashar.
//

import AppKit

/// Regra PURA de quando a janela vai pro space do lock: só com a tela de
/// fato bloqueada, o toggle ligado e a bridge carregada. Testável sem
/// WindowServer (a bridge em si não é).
enum LockScreenPolicy {
    static func shouldDelegate(locked: Bool, enabled: Bool, bridgeAvailable: Bool) -> Bool {
        locked && enabled && bridgeAvailable
    }

    /// Tipos que NÃO podem nem entrar no slot de peek com a tela bloqueada.
    /// Notificação espelhada (remetente ou corpo) por cima do loginwindow
    /// furaria o "Mostrar prévias: quando desbloqueado" do macOS — HUDs,
    /// mídia, bateria e evento (redigido) continuam, como a spec §1 promete.
    static func allowsPeek(kindKey: String, locked: Bool) -> Bool {
        !(locked && kindKey == "notification")
    }
}

@MainActor
final class LockScreenBridge {
    /// Nível absoluto em que a Central de Notificações renderiza com a tela
    /// bloqueada — acima do `screenLock` simples, por isso é o usado aqui.
    private static let notificationCenterAtScreenLock: Int32 = 400

    /// `nil` = framework/símbolo não carregou → "sem ilha no lock", nunca crash.
    static let shared: LockScreenBridge? = LockScreenBridge()

    /// Pra UI/log sem espalhar `.shared` (o acesso já carrega a bridge, é lazy).
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
        // O `1` é obrigatório: qualquer outro valor faz o Finder desenhar os
        // ícones da mesa dentro deste space.
        space = spaceCreate(connection, 1, 0)
        _ = setAbsoluteLevel(connection, space, Self.notificationCenterAtScreenLock)
        _ = showSpaces(connection, [space] as CFArray)
        Self.dlog("bridge carregada — conn=\(connection) space=\(space) level=\(Self.notificationCenterAtScreenLock)")
    }

    /// Move `window` pro space elevado (visível no lock). Chame só com a
    /// tela de fato bloqueada e a janela já ordenada (windowNumber válido).
    /// Tira a janela de TODOS os outros spaces — ver `undelegate`.
    func delegate(_ window: NSWindow) {
        let r = addWindowsAndRemoveFromSpaces(connection, space, [window.windowNumber] as CFArray, 7)
        Self.dlog("delegate win=\(window.windowNumber) → \(r)")
    }

    /// Tira `window` do space elevado. Na sonda (tela destravada, macOS 26.6)
    /// o WindowServer devolveu a janela sozinho aos spaces de usuário pelo
    /// `collectionBehavior` (`canJoinAllSpaces`), com o mesmo `windowNumber`;
    /// o `orderOut` + `orderFrontRegardless` que o chamador faz em seguida é
    /// rede de segurança (provado inofensivo) pra o unlock real divergir.
    /// Diagnóstico: `SLSCopySpacesForWindows(conn, 7, [win])` devolve `[]`
    /// enquanto delegada — o space custom não entra na máscara 7.
    func undelegate(_ window: NSWindow) {
        let r = removeWindowsFromSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
        Self.dlog("undelegate win=\(window.windowNumber) → \(r)")
    }
}
