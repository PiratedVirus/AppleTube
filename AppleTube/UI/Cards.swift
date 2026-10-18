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
    var width: CGFloat = 160

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
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            ArtworkView(url: item.thumbnailURL, isCircle: { if case .artist = item { true } else { false } }())
                .frame(width: width)
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
        .contentShape(.rect)
    }

    private func play() {
        if case let .song(song) = item { WebPlayer.shared.play(song) }
    }
}

/// Long-press menu shared by cards and rows.
struct ItemMenu: View {
    let item: HomeSectionItem

    var body: some View {
        if let videoId = item.videoId {
            Button("Play", systemImage: "play.fill") { WebPlayer.shared.play(videoId: videoId, playlistId: nil) }
            Button("Start Station", systemImage: "dot.radiowaves.left.and.right") {
                WebPlayer.shared.play(videoId: videoId, playlistId: "RDAMVM\(videoId)")
            }
        }
        if let route = item.route {
            NavigationLink(value: route) { Label("Open", systemImage: "arrow.up.right") }
        }
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Menu {
                    Button("Start Station", systemImage: "dot.radiowaves.left.and.right") {
                        WebPlayer.shared.play(videoId: song.videoId, playlistId: "RDAMVM\(song.videoId)")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Loading / error / content switch with Apple-style empty states.
enum Loadable<Value> {
    case loading
    case failed(String)
    case loaded(Value)
}

struct LoadingView: View {
    var body: some View {
        ProgressView().frame(maxWidth: .infinity, minHeight: 300)
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
