import SwiftUI

/// Apple Music shelf: bold title with a chevron, then a horizontally scrolling row of cards.
struct Shelf<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(title).font(.title2.bold())
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) { content }
                    .scrollTargetLayout()
                    .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

/// Square artwork with title and subtitle underneath. Songs play on tap; everything else navigates.
struct ItemCard: View {
    let item: HomeSectionItem
    /// nil fills the available width (grid cells).
    var width: CGFloat? = 160

    var body: some View {
        Group {
            if let route = item.route {
                NavigationLink(value: route) { label }
            } else {
                Button { play() } label: { label }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { ItemMenu(item: item) }
        .task {
            // Warm the page this card opens if it stays on screen for a moment.
            guard let route = item.route else { return }
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { YTMusicAPI.shared.prefetch(route) }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if case let .playlist(playlist) = item {
                    PlaylistArtwork(id: playlist.id, title: playlist.title, url: playlist.thumbnailURL)
                } else {
                    ArtworkView(url: item.thumbnailURL, isCircle: { if case .artist = item { true } else { false } }())
                }
            }
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
            Text(item.title)
                .font(.subheadline)
                .lineLimit(1)
            if let subtitle = item.homeCardSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .contentShape(.rect)
    }

    private func play() {
        if case let .song(song) = item { WebPlayer.shared.play(song) }
    }
}

/// Track row used on album, playlist, artist and search pages.
struct SongRow: View {
    let song: Song
    var index: Int?
    var showsArtwork = true
    var isCurrent = false
    /// Shown when the song carries no artist (e.g. songs inside a search "Top result" artist card).
    var fallbackArtist: String?
    /// Prefix such as "Song" for search results ("Song · Artist").
    var kind: String?
    /// Extra menu actions for where the row is shown (your playlist, the queue…).
    var menuContext: SongMenu.Context = .standard
    var onRemoved: () -> Void = {}
    let action: () -> Void

    /// Not a Button: a context menu on a Button inside a List row doesn't open reliably. A plain view with a
    /// tap gesture gets Apple Music's long-press menu and preview.
    var body: some View {
        HStack(spacing: 12) {
            if let index, !showsArtwork {
                Group {
                    if isCurrent {
                        Image(systemName: "waveform").foregroundStyle(Color.musicAccent).symbolEffect(.variableColor.iterative)
                    } else {
                        Text("\(index)").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .frame(width: 24)
            } else if showsArtwork {
                ArtworkView(url: song.thumbnailURL, cornerRadius: 5, pixelSize: 120)
                    .frame(width: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(song.title).lineLimit(1)
                        .foregroundStyle(isCurrent ? Color.musicAccent : .primary)
                    if song.isExplicit == true {
                        Image(systemName: "e.square.fill").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let artist = song.artistsDisplay.isEmpty ? fallbackArtist : song.artistsDisplay {
                    Text([kind, artist].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Menu {
                SongMenu(song: song, context: menuContext, onRemoved: onRemoved)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: action)
        .accessibilityAddTraits(.isButton)
        .contextMenu { SongMenu(song: song, context: menuContext, onRemoved: onRemoved) } preview: { SongPreview(song: song) }
        // Apple Music: swipe right to Play Next, swipe left to Play Last (only takes effect inside a List).
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { WebPlayer.shared.playNext(videoId: song.videoId) } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(.indigo)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { WebPlayer.shared.playLast(videoId: song.videoId) } label: {
                Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
            .tint(.orange)
        }
    }
}

/// Long-press preview: big artwork with the title underneath, as in Apple Music.
private struct SongPreview: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(url: song.thumbnailURL, cornerRadius: 10, pixelSize: 600).frame(width: 260)
            Text(song.title).font(.headline).lineLimit(1)
            Text(song.artistsDisplay).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(16)
    }
}

/// Loading / error / content switch with Apple-style empty states.
enum Loadable<Value> {
    case loading
    case failed(String)
    case loaded(Value)
}

/// Spinner that only appears if loading takes longer than ~0.3s, so fast (cached) loads never flash it.
struct LoadingView: View {
    @State private var visible = false

    var body: some View {
        ProgressView()
            .opacity(visible ? 1 : 0)
            .frame(maxWidth: .infinity, minHeight: 300)
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeIn(duration: 0.2)) { visible = true }
            }
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Load", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: retry).buttonStyle(.bordered)
        }
    }
}
