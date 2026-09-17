import Foundation

/// Clima via Open-Meteo (grátis, sem chave, sem WeatherKit/team Apple).
/// Localização por IP (ip-api.com) — zero TCC. Atualiza a cada 30 min.
@MainActor
final class WeatherService: ObservableObject {
    struct Weather: Equatable {
        var tempC: Double
        var code: Int

        /// WMO weather code → SF Symbol
        var symbol: String {
            switch code {
            case 0: "sun.max.fill"
            case 1, 2: "cloud.sun.fill"
            case 3: "cloud.fill"
            case 45, 48: "cloud.fog.fill"
            case 51...67, 80...82: "cloud.rain.fill"
            case 71...77, 85, 86: "cloud.snow.fill"
            case 95...99: "cloud.bolt.rain.fill"
            default: "cloud.fill"
            }
        }
    }

    @Published var current: Weather?

    private var loopTask: Task<Void, Never>?

    /// Liga o loop de 30min. Idempotente — chamar de novo com o loop já
    /// rodando não faz nada (evita fetch duplicado quando `showWeather` é
    /// alternado várias vezes).
    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { await refreshLoop() }
    }

    /// Desliga o loop e derruba o último valor — a feature está invisível
    /// (`showWeather == false`), não faz sentido continuar batendo na rede.
    func stop() {
        loopTask?.cancel()
        loopTask = nil
        current = nil
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(30 * 60))
        }
    }

    private func refresh() async {
        do {
            // 1) coordenadas por IP — HTTPS obrigatório (ATS bloqueia HTTP;
            // ip-api.com free é HTTP-only e falhava silencioso)
            let (locData, _) = try await URLSession.shared.data(
                from: URL(string: "https://ipwho.is/")!)
            guard let loc = try JSONSerialization.jsonObject(with: locData) as? [String: Any],
                  let lat = loc["latitude"] as? Double, let lon = loc["longitude"] as? Double
            else { return }
            // 2) Open-Meteo
            let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code")!
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = obj["current"] as? [String: Any],
                  let temp = cur["temperature_2m"] as? Double,
                  let code = cur["weather_code"] as? Int
            else { return }
            current = Weather(tempC: temp, code: code)
        } catch {
            // sem rede: mantém último valor
        }
    }
}
