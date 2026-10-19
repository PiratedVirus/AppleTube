import SwiftUI

/// Apple Music-style lyrics. Timed lyrics (from YouTube Music, else LRCLIB) highlight the sung line, dim and
/// soften the others, scroll themselves, light up word by word when word timing exists, and show breathing
/// dots through instrumental gaps. Tap a line to jump there. Untimed lyrics show in the same type, statically.
struct LyricsView: View {
    let player: WebPlayer
    @State private var result: Loadable<LyricResult> = .loading

    var body: some View {
        Group {
            switch result {
            case .loading:
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed, .loaded(.unavailable):
                Text("Lyrics aren't available for this song.")
                    .font(.title2.bold())
                    .opacity(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case let .loaded(.synced(lyrics)):
                SyncedLyricsScroller(lines: LyricItem.items(from: lyrics), source: lyrics.source, player: player)
            case let .loaded(.plain(lyrics)):
                PlainLyrics(lyrics: lyrics)
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                     .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .task(id: player.videoId) { await load() }
    }

    private func load() async {
        guard let videoId = player.videoId else {
            result = .loaded(.unavailable)
            return
        }
        result = .loading
        result = .loaded(await LyricsFinder.find(videoId: videoId, title: player.title, artist: player.artist, duration: player.duration))
    }
}

/// A timed line, or a gap (intro / instrumental break) shown as dots.
struct LyricItem: Identifiable, Equatable {
    let id: Int
    let startMs: Int
    let endMs: Int
    let text: String
    let words: [TimedWord]?
    var isGap: Bool { text.isEmpty }

    /// Turns lyric lines into display items. Lines are assumed sung for at most ~7s (sources often stretch a
    /// line's duration to the next line), and any silence of 3s+ (intro, empty LRC line, long break) is a gap.
    static func items(from lyrics: SyncedLyrics) -> [LyricItem] {
        let lines = lyrics.lines.sorted { $0.timeInMs < $1.timeInMs }
        var items: [LyricItem] = []
        func add(start: Int, end: Int, text: String, words: [TimedWord]?) {
            items.append(LyricItem(id: items.count, startMs: start, endMs: end, text: text, words: words))
        }
        func addGap(from start: Int, to end: Int) {
            if end - start >= 3000 { add(start: start, end: end, text: "", words: nil) }
        }
        let firstSung = lines.first { !Self.isBlank($0.text) }?.timeInMs ?? 0
        addGap(from: 0, to: firstSung)
        for (index, line) in lines.enumerated() where !Self.isBlank(line.text) && line.timeInMs >= firstSung {
            let nextSung = lines[(index + 1)...].first { !Self.isBlank($0.text) }?.timeInMs ?? Int.max
            let duration = line.duration > 0 ? line.duration : 7000
            let end = min(line.timeInMs + min(duration, 7000), nextSung)
            add(start: line.timeInMs, end: end, text: line.text.trimmingCharacters(in: .whitespaces), words: line.words)
            if nextSung != Int.max { addGap(from: end, to: nextSung) }
        }
        return items
    }

    private static func isBlank(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "♪"
    }
}

private struct SyncedLyricsScroller: View {
    let lines: [LyricItem]
    let source: String
    let player: WebPlayer

    @State private var isUserScrolling = false
    @State private var resumeAutoScroll: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                TimelineView(.animation(minimumInterval: 1 / 20, paused: !player.isPlaying)) { context in
                    let nowMs = Int(player.currentPosition(at: context.date) * 1000)
                    let current = lines.lastIndex { $0.startMs <= nowMs } ?? -1
                    VStack(alignment: .leading, spacing: 26) {
                        Color.clear.frame(height: 40)
                        ForEach(lines) { item in
                            LyricLineView(item: item, index: item.id, current: current, nowMs: nowMs, isUserScrolling: isUserScrolling)
                                .id(item.id)
                                .onTapGesture { player.seek(to: Double(item.startMs) / 1000 + 0.05) }
                        }
                        Text("Lyrics from \(source == "LRCLIB" ? "LRCLIB" : "YouTube Music")")
                            .font(.footnote)
                            .opacity(0.45)
                            .padding(.top, 12)
                        Color.clear.frame(height: 260)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: current) { _, line in
                        guard !isUserScrolling, line >= 0 else { return }
                        withAnimation(.spring(duration: 0.6, bounce: 0.1)) {
                            proxy.scrollTo(line, anchor: UnitPoint(x: 0, y: 0.22))
                        }
                    }
                    .onAppear {
                        if current >= 0 { proxy.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.22)) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                // Manual scrolling pauses auto-scroll and un-blurs every line, like Apple Music; resume after 3s.
                if phase == .interacting || phase == .decelerating {
                    resumeAutoScroll?.cancel()
                    isUserScrolling = true
                } else if phase == .idle, isUserScrolling {
                    resumeAutoScroll = Task {
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        withAnimation { isUserScrolling = false }
                    }
                }
            }
        }
    }
}

private struct LyricLineView: View {
    let item: LyricItem
    let index: Int
    let current: Int
    let nowMs: Int
    let isUserScrolling: Bool

    private var isCurrent: Bool { index == current }

    var body: some View {
        Group {
            if item.isGap {
                GapDots(progress: isCurrent ? Double(nowMs - item.startMs) / Double(max(item.endMs - item.startMs, 1)) : 0)
                    .frame(height: isCurrent ? 34 : 0)
                    .opacity(isCurrent ? 1 : 0)
            } else {
                lineText
                    .font(.system(size: 32, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isCurrent ? 1 : 0.32)
                    .blur(radius: isCurrent || isUserScrolling ? 0 : min(Double(abs(index - current)) * 0.5, 2.5))
                    .scaleEffect(isCurrent ? 1 : 0.97, anchor: .leading)
            }
        }
        .animation(.spring(duration: 0.5), value: isCurrent)
        .animation(.easeOut(duration: 0.3), value: isUserScrolling)
        .contentShape(.rect)
    }

    /// Word-by-word highlight when the source has word timing; otherwise the whole line lights up.
    private var lineText: Text {
        guard isCurrent, let words = item.words, !words.isEmpty else { return Text(item.text) }
        return words.reduce(Text("")) { text, word in
            text + Text(word.word).foregroundStyle(.white.opacity(word.timeInMs <= nowMs ? 1 : 0.4))
        }
    }
}

/// Three dots that fill in turn and gently breathe through an instrumental gap.
private struct GapDots: View {
    let progress: Double

    var body: some View {
        TimelineView(.animation) { context in
            let breathe = 1 + 0.08 * sin(context.date.timeIntervalSinceReferenceDate * 3)
            HStack(spacing: 10) {
                ForEach(0 ..< 3) { dot in
                    let fill = min(max(progress * 3 - Double(dot), 0), 1)
                    Circle()
                        .fill(.white.opacity(0.3 + 0.7 * fill))
                        .frame(width: 14, height: 14)
                }
            }
            .scaleEffect(breathe, anchor: .leading)
        }
    }
}

private struct PlainLyrics: View {
    let lyrics: Lyrics

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Color.clear.frame(height: 30)
                ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { _, line in
                    if line.trimmingCharacters(in: .whitespaces).isEmpty {
                        Color.clear.frame(height: 4)
                    } else {
                        Text(line).font(.system(size: 30, weight: .bold)).opacity(0.85)
                    }
                }
                if let source = lyrics.source {
                    Text(source).font(.footnote).opacity(0.45).padding(.top, 12)
                }
                Color.clear.frame(height: 120)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}
