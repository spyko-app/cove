import SwiftUI

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
