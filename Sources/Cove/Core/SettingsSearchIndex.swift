import Foundation

struct SettingsSearchIndex {
    struct Entry {
        let pane: String
        let title: String
        let keywords: [String]
    }

    let entries: [Entry]

    func matches(_ query: String) -> [String] {
        let q = Self.normalize(query)
        guard !q.isEmpty else {
            return entries.reduce(into: [String]()) { acc, e in
                if !acc.contains(e.pane) { acc.append(e.pane) }
            }
        }
        var seen = Set<String>()
        var result: [String] = []
        for e in entries {
            guard !seen.contains(e.pane) else { continue }
            let haystacks = [e.title] + e.keywords
            if haystacks.contains(where: { Self.normalize($0).contains(q) }) {
                seen.insert(e.pane)
                result.append(e.pane)
            }
        }
        return result
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

extension SettingsSearchIndex {
    static let coveNotch = SettingsSearchIndex(entries: [
        Entry(pane: "Geral", title: "Geral", keywords: [
            "login", "captura", "editor", "hover", "gesto", "haptico",
            "tela cheia", "fullscreen", "onboarding", "refazer",
        ]),
        Entry(pane: "Aparência", title: "Aparência", keywords: [
            "estilo", "hud", "glass", "vidro", "duracao", "peek", "slider",
            "branco", "accent", "glow", "teclado", "wifi", "disco", "vpn",
        ]),
        Entry(pane: "Telas", title: "Telas", keywords: [
            "monitor", "display", "tela", "externa", "interna",
            "notch simulado", "mostrar em", "ilha larga",
            "tela de bloqueio", "bloqueio", "lock screen", "bloqueada",
            "widgets", "relogio", "cadeado", "alcove", "foco", "clima",
            "bateria", "midia tocando", "proximo evento", "timer",
        ]),
        Entry(pane: "HUDs e eventos", title: "HUDs e eventos", keywords: [
            "bateria", "energia", "economia", "limiar", "bluetooth", "airpods",
            "wifi", "hotspot", "drive", "vpn", "foco", "dnd", "nao perturbe",
            "brilho", "backlight", "volume", "chime", "som", "lock",
            "bloqueio", "desbloqueio", "notificacao", "acesso total ao disco",
            "fda", "hud nativo",
        ]),
        Entry(pane: "Ilha expandida", title: "Ilha expandida", keywords: [
            "now playing", "musica", "waveform", "faixa", "media", "letras",
            "lyrics", "arte", "calendario", "evento", "agenda",
            "time to leave", "clima", "weather", "apps fixados", "pinned",
            "busca", "buscar ou perguntar", "puxar", "gesto",
        ]),
        Entry(pane: "Droplets", title: "Droplets", keywords: [
            "droplet", "hotkey", "atalho", "ordem", "pagina",
        ]),
        Entry(pane: "Ações rápidas", title: "Ações rápidas", keywords: [
            "atalho", "ring", "grade", "high alert", "testar", "capturar",
            "ocr", "cor", "gravar tela", "pomodoro",
        ]),
        Entry(pane: "Cesta", title: "Cesta", keywords: [
            "cesta", "shelf", "widget", "quick actions", "obsidian", "vault",
            "airdrop", "finder", "compactar",
        ]),
        Entry(pane: "Clipboard", title: "Clipboard", keywords: [
            "copia", "colar", "historico", "retencao", "limite",
        ]),
        Entry(pane: "Permissões", title: "Permissões", keywords: [
            "acessibilidade", "calendario", "microfone", "fala", "gravacao de tela",
            "disco", "automation", "mensagens", "spotify", "pedir",
        ]),
        Entry(pane: "Atualizações", title: "Atualizações", keywords: [
            "canal", "nightly", "estavel", "versao", "update", "verificar",
        ]),
        Entry(pane: "Sobre", title: "Sobre", keywords: ["versao"]),
    ])
}
