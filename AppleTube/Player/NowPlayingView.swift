import AVKit
import MediaPlayer
import SwiftUI

/// Now Playing, presented as a sheet so it swipes down like Apple Music's: drifting blurred-artwork background;
/// large artwork that shrinks when paused; title and tappable artist; scrubber; transport; volume; and
/// lyrics / AirPlay / Up Next. In lyrics and Up Next the artwork collapses into a compact header.
struct NowPlayingView: View {
    enum Panel {
        case artwork, lyrics, queue

        static var initial: Panel {
            switch UserDefaults.standard.string(forKey: "nowPlayingPanel") {
            case "lyrics": .lyrics
            case "queue": .queue
            default: .artwork
            }
        }
    }

    @State private var player = WebPlayer.shared
    @State private var panel = Panel.initial
    @State private var scrubPosition: Double?
    @State private var song: Song?
    /// The big artwork and the compact header's thumbnail are one shape, so switching panels morphs between them.
    @Namespace private var artworkMorph
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Button { dismiss() } label: {
                Capsule().fill(.white.opacity(0.45)).frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Now Playing")

            if panel != .artwork {
                compactHeader
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }

            Group {
                switch panel {
                case .artwork: artwork
                case .lyrics: LyricsView(player: player)
                case .queue: QueuePanel(player: player)
                }
            }
            .frame(maxHeight: .infinity)

            if panel == .artwork { titleRow.padding(.bottom, 18) }
            scrubber
            transport.padding(.vertical, panel == .lyrics ? 14 : 24)
            if panel != .lyrics {
                VolumeSlider().frame(height: 34).padding(.bottom, 18)
            }
            bottomButtons
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .foregroundStyle(.white)
        .background { NowPlayingBackground(url: player.artworkURL) }
        .animation(.spring(duration: 0.45, bounce: 0.15), value: panel)
        .preferredColorScheme(.dark)
        .libraryPrompts()
        .sensoryFeedback(.impact(weight: .light), trigger: player.isPlaying)
        .task(id: player.videoId) {
            song = nil
            if let videoId = player.videoId { song = await YTMusicAPI.shared.songDetails(videoId: videoId) }
        }
    }

    private var artwork: some View {
        ArtworkView(url: player.artworkURL, cornerRadius: 12, pixelSize: 1080)
            .matchedGeometryEffect(id: "artwork", in: artworkMorph)
            .shadow(color: .black.opacity(player.isPlaying ? 0.4 : 0.2), radius: player.isPlaying ? 28 : 14, y: player.isPlaying ? 16 : 8)
            .scaleEffect(player.isPlaying ? 1 : 0.8)
            .animation(.spring(duration: 0.55, bounce: 0.3), value: player.isPlaying)
            .padding(.vertical, 24)
    }

    /// Small artwork + title/artist, shown above lyrics and Up Next (matches Apple's lyrics screen).
    private var compactHeader: some View {
        HStack(spacing: 12) {
            ArtworkView(url: player.artworkURL, cornerRadius: 6, pixelSize: 200)
                .matchedGeometryEffect(id: "artwork", in: artworkMorph)
                .frame(width: 56)
                .onTapGesture { panel = .artwork }
            VStack(alignment: .leading, spacing: 1) {
                Text(player.title).font(.headline).lineLimit(1)
                artistButton.font(.subheadline)
            }
            Spacer()
            moreMenu
        }
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.title.isEmpty ? "Not Playing" : player.title)
                    .font(.title3.bold())
                    .lineLimit(1)
                artistButton.font(.title3)
            }
            Spacer()
            moreMenu
        }
    }

    /// Artist name; tapping it closes the player and opens the artist page, as in Apple Music.
    private var artistButton: some View {
        Button {
            if let artist = song?.artists.first(where: \.hasNavigableId) {
                AppState.shared.show(.artist(id: artist.id, name: artist.name))
            }
        } label: {
            Text(player.artist).opacity(0.7).lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private var moreMenu: some View {
        Menu {
            // Full details once loaded (album/artist links, library state); a minimal song until then.
            if let current = song ?? player.videoId.map({ Song.minimal(videoId: $0, title: player.title, artist: player.artist, artwork: player.artworkURL) }) {
                SongMenu(song: current, context: .nowPlaying)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.15), in: .circle)
        }
    }

    private var scrubber: some View {
        let duration = max(player.duration, 1)
        let position = scrubPosition ?? min(player.position, duration)
        return VStack(spacing: 6) {
            ScrubBar(value: position, total: duration) { target in
                scrubPosition = target
            } onCommit: { target in
                player.seek(to: target)
                // Keep showing the target until the page reports the new time.
                Task {
                    try? await Task.sleep(for: .seconds(0.8))
                    scrubPosition = nil
                }
            }
            HStack {
                Text(Self.time(position))
                Spacer()
                Text("-" + Self.time(max(duration - position, 0)))
            }
            .font(.caption.monospacedDigit())
            .opacity(0.6)
        }
    }

    private var transport: some View {
        HStack {
            Spacer()
            Button { player.previous() } label: { Image(systemName: "backward.fill") }
                .accessibilityLabel("Previous")
            Spacer()
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: 52))
                    .frame(width: 64)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { player.next() } label: { Image(systemName: "forward.fill") }
                .accessibilityLabel("Next")
            Spacer()
        }
        .font(.system(size: 36))
        .buttonStyle(PressableStyle())
    }

    private var bottomButtons: some View {
        HStack {
            panelButton(.lyrics, symbol: "quote.bubble")
            Spacer()
            AirPlayButton().frame(width: 44, height: 44)
            Spacer()
            panelButton(.queue, symbol: "list.bullet")
        }
        .padding(.horizontal, 24)
    }

    private func panelButton(_ target: Panel, symbol: String) -> some View {
        Button {
            panel = panel == target ? .artwork : target
        } label: {
            // Only some symbols have a filled variant (quote.bubble.fill exists, list.bullet.fill doesn't).
            Image(systemName: panel == target && target == .lyrics ? symbol + ".fill" : symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(panel == target ? .white.opacity(0.2) : .clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target == .lyrics ? "Lyrics" : "Up Next")
    }

    static func time(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Transport buttons shrink slightly while pressed, like Apple Music's.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.18 : 0))
                    .frame(width: 76, height: 76)
            }
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Apple Music's knobless progress bar: a thin track that grows while you drag it.
private struct ScrubBar: View {
    let value: Double
    let total: Double
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let fraction = total > 0 ? min(max(value / total, 0), 1) : 0
            Capsule()
                .fill(.white.opacity(0.25))
                .overlay(alignment: .leading) {
                    Capsule().fill(.white.opacity(isDragging ? 1 : 0.75)).frame(width: geometry.size.width * fraction)
                }
                .frame(height: isDragging ? 12 : 7)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            isDragging = true
                            onChange(target(drag.location.x, width: geometry.size.width))
                        }
                        .onEnded { drag in
                            isDragging = false
                            onCommit(target(drag.location.x, width: geometry.size.width))
                        }
                )
                .animation(.spring(duration: 0.25), value: isDragging)
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(NowPlayingView.time(value))
    }

    private func target(_ x: CGFloat, width: CGFloat) -> Double {
        Double(min(max(x / max(width, 1), 0), 1)) * total
    }
}

/// The artwork, hugely blurred and darkened, slowly drifting: Apple Music's living Now Playing background.
private struct NowPlayingBackground: View {
    let url: URL?

    var body: some View {
        ZStack {
            Color.black
            TimelineView(.animation(minimumInterval: 1 / 15)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ArtworkView(url: url, cornerRadius: 0, pixelSize: 120)
                    .scaleEffect(2.2)
                    .rotationEffect(.degrees(sin(t / 9) * 18))
                    .offset(x: cos(t / 7) * 40, y: sin(t / 11) * 60)
                    .blur(radius: 70)
                    .saturation(1.4)
            }
            Color.black.opacity(0.3)
        }
        .ignoresSafeArea()
    }
}

/// System volume slider (MPVolumeView) restyled as a thin white track.
private struct VolumeSlider: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.caption).opacity(0.6)
            SystemVolumeView()
            Image(systemName: "speaker.wave.3.fill").font(.caption).opacity(0.6)
        }
    }

    private struct SystemVolumeView: UIViewRepresentable {
        func makeUIView(context _: Context) -> MPVolumeView {
            let view = MPVolumeView()
            view.tintColor = .white
            return view
        }

        func updateUIView(_: MPVolumeView, context _: Context) {}
    }
}

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context _: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(Color.musicAccent)
        return picker
    }

    func updateUIView(_: AVRoutePickerView, context _: Context) {}
}

/// Apple Music's queue: Shuffle / Repeat / Autoplay pills, then History (scroll up to reveal) and Playing Next.
/// Swipe a queued song to remove it; tap any song to play it.
private struct QueuePanel: View {
    let player: WebPlayer
    @State private var history = PlaybackHistory.shared

    private var upcoming: [(offset: Int, element: QueueItem)] {
        let start = (player.queueIndex ?? -1) + 1
        return Array(player.queue.enumerated()).filter { $0.offset >= start }
    }

    private var pastSongs: [PlaybackHistory.Entry] {
        history.entries.filter { $0.videoId != player.videoId }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ModePill(symbol: "shuffle", isOn: false, label: "Shuffle") { player.shuffleQueue() }
                ModePill(symbol: player.repeatMode.symbol, isOn: player.repeatMode != .off,
                         label: "Repeat \(player.repeatMode.rawValue)") { player.cycleRepeat() }
                ModePill(symbol: "infinity", isOn: player.autoplay, label: "Autoplay") { player.setAutoplay(!player.autoplay) }
            }
            .padding(.top, 10)

            ScrollViewReader { proxy in
                List {
                    if !pastSongs.isEmpty {
                        Section {
                            ForEach(pastSongs) { entry in
                                QueueRow(title: entry.title, artist: entry.artist, artworkURL: entry.artworkURL)
                                    .opacity(0.6)
                                    .onTapGesture { player.play(videoId: entry.videoId, playlistId: nil) }
                                    .contextMenu {
                                        SongMenu(song: .minimal(videoId: entry.videoId, title: entry.title, artist: entry.artist, artwork: entry.artworkURL))
                                    }
                            }
                        } header: {
                            sectionHeader("History") {
                                Button("Clear") { withAnimation { history.clear() } }
                                    .font(.body)
                                    .opacity(0.7)
                            }
                        }
                    }

                    Section {
                        if upcoming.isEmpty {
                            Text("There's no music in the queue.")
                                .opacity(0.6)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        }
                        ForEach(upcoming, id: \.element.id) { index, item in
                            QueueRow(title: item.title, artist: item.artist, artworkURL: item.artworkURL)
                                .onTapGesture { player.jump(toQueueIndex: index) }
                                .contextMenu {
                                    SongMenu(song: .minimal(videoId: item.videoId, title: item.title, artist: item.artist, artwork: item.artworkURL),
                                             context: .queue(index: index))
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        player.removeFromQueue(at: index)
                                    } label: {
                                        Label("Remove", systemImage: "minus.circle.fill")
                                    }
                                }
                        }
                    } header: {
                        sectionHeader(player.autoplay ? "Continue Playing" : "Playing Next") {
                            if player.autoplay {
                                Text("Autoplay").font(.subheadline).opacity(0.5)
                            }
                        }
                        .id("playingNext")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .environment(\.defaultMinListRowHeight, 60)
                // Start at Playing Next with History tucked above, as Apple Music does.
                .onAppear { proxy.scrollTo("playingNext", anchor: .top) }
            }
        }
    }

    private func sectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            trailing()
        }
        .foregroundStyle(.white)
        .textCase(nil)
        .padding(.vertical, 6)
    }
}

private struct QueueRow: View {
    let title: String
    let artist: String
    let artworkURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: artworkURL, cornerRadius: 6, pixelSize: 160).frame(width: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(artist).font(.subheadline).opacity(0.6).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowSeparator(.hidden)
    }
}

/// The capsule toggles at the top of Apple Music's queue; filled when on.
private struct ModePill: View {
    let symbol: String
    let isOn: Bool
    let label: String
    let action: () -> Void
    @State private var flash = false

    var body: some View {
        Button {
            action()
            flash.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.headline)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isOn ? Color.black.opacity(0.75) : .white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isOn ? .white.opacity(0.75) : .white.opacity(0.14), in: .capsule)
                .symbolEffect(.bounce, value: flash)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: isOn)
        .sensoryFeedback(.selection, trigger: flash)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
