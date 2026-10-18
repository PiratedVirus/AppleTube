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
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Group {
                switch panel {
                case .artwork: artwork
                case .lyrics: LyricsView(player: player)
                case .queue: QueuePanel(videoId: player.videoId, playlistId: player.playlistId)
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
        .sensoryFeedback(.impact(weight: .light), trigger: player.isPlaying)
        .task(id: player.videoId) {
            song = nil
            if let videoId = player.videoId { song = await YTMusicAPI.shared.songDetails(videoId: videoId) }
        }
    }

    private var artwork: some View {
        ArtworkView(url: player.artworkURL, cornerRadius: 12, pixelSize: 1080)
            .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
            .scaleEffect(player.isPlaying ? 1 : 0.82)
            .animation(.spring(duration: 0.5, bounce: 0.25), value: player.isPlaying)
            .padding(.vertical, 24)
            .transition(.scale(scale: 0.4, anchor: .topLeading).combined(with: .opacity))
    }

    /// Small artwork + title/artist, shown above lyrics and Up Next (matches Apple's lyrics screen).
    private var compactHeader: some View {
        HStack(spacing: 12) {
            ArtworkView(url: player.artworkURL, cornerRadius: 6, pixelSize: 200)
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
            if let album = song?.album, album.hasNavigableId {
                Button("Go to Album", systemImage: "square.stack") {
                    AppState.shared.show(.playlist(id: album.id, title: album.title))
                }
            }
            if let artist = song?.artists.first(where: \.hasNavigableId) {
                Button("Go to Artist", systemImage: "music.microphone") {
                    AppState.shared.show(.artist(id: artist.id, name: artist.name))
                }
            }
            if let videoId = player.videoId {
                Button("Start Station", systemImage: "dot.radiowaves.left.and.right") {
                    player.play(videoId: videoId, playlistId: "RDAMVM\(videoId)")
                }
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
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
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

/// Up Next: the radio queue YouTube Music builds from the current song.
private struct QueuePanel: View {
    let videoId: String?
    let playlistId: String?
    @State private var songs: [Song] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Up Next").font(.headline).padding(.top, 12)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(songs.filter { $0.videoId != videoId }) { song in
                        SongRow(song: song) {
                            WebPlayer.shared.play(videoId: song.videoId, playlistId: playlistId)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .task(id: videoId) {
            guard let videoId else { return }
            songs = (try? await YTMusicAPI.shared.radioQueue(videoId: videoId).songs) ?? []
        }
    }
}
