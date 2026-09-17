import SwiftUI

/// Linha de letra atual, no lugar do nome do artista no card expandido.
/// Interpola o `elapsed` a partir de `lastElapsedUpdate` pra achar a linha certa
/// sem precisar de um novo tick de MediaRemote a cada segundo.
struct CurrentLyricLine: View {
    @ObservedObject var media: MediaRemoteService
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let interpolated = media.nowPlaying.isPlaying
                ? media.nowPlaying.elapsed + context.date.timeIntervalSince(media.lastElapsedUpdate)
                : media.nowPlaying.elapsed
            let index = LRCParser.currentIndex(lyrics.lines, at: max(0, interpolated))
            let text = index.map { lyrics.lines[$0].text } ?? ""
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .id(index)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: index)
        }
    }
}
