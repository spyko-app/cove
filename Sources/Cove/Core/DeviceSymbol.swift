import Foundation

enum DeviceSymbol {
    static func symbol(for name: String, connected: Bool) -> String {
        let n = name.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { n.contains($0) } }
        if has(["airpods max"]) { return "airpods.max" }
        if has(["airpods pro"]) { return "airpods.pro" }
        if has(["airpods"]) { return "airpods" }
        if has(["beats", "headphone", "buds", "wh-", "wf-", "fone", "earbud"]) { return "headphones" }
        if has(["flip", "charge", "speaker", "jbl", "bose", "sonos", "boom", "caixa", "soundlink", "marshall", "homepod"]) {
            return "hifispeaker.fill"
        }
        if has(["keyboard", "teclado"]) { return "keyboard" }
        if has(["mouse"]) { return "computermouse.fill" }
        if has(["trackpad"]) { return "rectangle.and.hand.point.up.left.fill" }
        if has(["watch"]) { return "applewatch" }
        if has(["iphone"]) { return "iphone" }
        if has(["controller", "controle", "dualsense", "xbox", "joy-con"]) { return "gamecontroller.fill" }
        return connected ? "dot.radiowaves.left.and.right" : "dot.radiowaves.left.and.right"
    }
}
