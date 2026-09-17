import Foundation

/// Extrai o link de reunião (Zoom/Meet/Teams/FaceTime/Webex/Whereby) de um
/// evento de calendário — puro, sem EventKit, fácil de testar.
enum MeetingLink {
    private static let hosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com",
        "facetime.apple.com", "webex.com", "whereby.com",
    ]

    /// Primeira URL http(s) de um host conhecido nas notas, senão na
    /// localização, senão a `url` do evento (qualquer host).
    static func extract(from notes: String?, url: URL?, location: String?) -> URL? {
        if let notes, let found = firstMeetingURL(in: notes) { return found }
        if let location, let found = firstMeetingURL(in: location) { return found }
        return url
    }

    private static func firstMeetingURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, isMeetingHost(url) { return url }
        }
        return nil
    }

    private static func isMeetingHost(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}
