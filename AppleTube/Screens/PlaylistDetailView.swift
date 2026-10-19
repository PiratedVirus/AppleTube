import SwiftUI

/// Album and playlist page in the iOS 26.4 style: the whole page is tinted with the artwork's colour,
/// centred artwork, title/artist, Shuffle · Play · Station, then the track list. The header paints at once
/// from what the tapped card knew; cached data fills in instantly when available, fresh data follows.
struct PlaylistDetailView: View {
    let id: String
    let fallbackTitle: String
    var fallbackArtwork: URL?

    @State private var page: Loadable<YTMusicAPI.PlaylistPage> = .loading
    @State private var tracks: [Song] = []
    @State private var tint: Color?
    @State private var player = WebPlayer.shared
    @State private var app = AppState.shared
    @State private var covers = CoverStore.shared
    @State private var artistRoute: Route?
    @Environment(\.dismiss) private var dismiss

    private var isAlbum: Bool { id.hasPrefix("MPRE") }

    var body: some View {
        // A List (not a ScrollView) so track rows get Apple Music's swipe actions.
        List {
            switch page {
            case .loading:
                header(page: nil).plainRow()
                LoadingView().plainRow()
            case let .failed(message):
                ErrorView(message: message) { Task { await load() } }.plainRow()
            case let .loaded(loaded):
                header(page: loaded).plainRow()
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, song in
                    SongRow(song: song, index: index + 1, showsArtwork: !isAlbum, isCurrent: player.videoId == song.videoId,
                            menuContext: .inPlaylist(id: id), onRemoved: { removeTrack(song) }) {
                        player.play(song, playbackListId: loaded.playbackListId)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 12))
                    .listRowSeparatorTint(textColor.opacity(0.2))
                }
                Color.clear.frame(height: 90).plainRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(background.ignoresSafeArea())
        .foregroundStyle(textColor)
        .tint(textColor)
        // Light or dark text to suit the tint, so .primary/.secondary in rows stay readable.
        .environment(\.colorScheme, tint.map { $0.prefersLightText ? .dark : .light } ?? .light)
        .animation(.easeOut(duration: 0.3), value: tint)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    collectionMenu
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .task { await load() }
        .navigationDestination(item: $artistRoute) { route in
            if case let .artist(id, name) = route { ArtistView(id: id, fallbackName: name) }
        }
        .onChange(of: app.deletedPlaylistId) { _, deleted in
            if deleted == YTMusicAPI.bareId(id) { dismiss() }
        }
        .onChange(of: covers.style(for: id)) { _, _ in Task { await updateTint() } }
    }

    private var loaded: YTMusicAPI.PlaylistPage? { if case let .loaded(page) = page { page } else { nil } }

    private var collectionMenu: some View {
        let author = loaded?.response.detail.author
        return CollectionMenu(kind: isAlbum ? .album : .playlist, id: id, title: title(loaded),
                              artistRoute: author.flatMap { $0.hasNavigableId ? .artist(id: $0.id, name: $0.name) : nil },
                              playbackListId: loaded?.playbackListId)
    }

    private var textColor: Color { tint.map { $0.prefersLightText ? .white : .black } ?? .primary }

    private var background: some View {
        let base = tint ?? Color(.systemBackground)
        return LinearGradient(colors: [base, base.mix(with: .black, by: tint == nil ? 0 : 0.25)], startPoint: .top, endPoint: .bottom)
    }

    private func header(page: YTMusicAPI.PlaylistPage?) -> some View {
        let detail = page?.response.detail
        return VStack(spacing: 14) {
            Group {
                if isAlbum {
                    ArtworkView(url: page.flatMap(Self.artworkURL) ?? fallbackArtwork, cornerRadius: 12)
                } else {
                    PlaylistArtwork(id: id, title: title(page), url: page.flatMap(Self.artworkURL) ?? fallbackArtwork, cornerRadius: 12)
                }
            }
            .frame(width: 260)
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .padding(.top, 8)

            VStack(spacing: 4) {
                Text(title(page))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if let author = detail?.author {
                    // A Button, not a NavigationLink: inside a List a link turns into a full-width chevron row.
                    Button { artistRoute = author.hasNavigableId ? .artist(id: author.id, name: author.name) : nil } label: {
                        Text(author.name).font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                if let detail {
                    Text(metadata(detail))
                        .font(.footnote.weight(.medium))
                        .opacity(0.7)
                }
            }
            .padding(.horizontal)

            HStack(spacing: 14) {
                circleButton("shuffle", label: "Shuffle") { shuffle(listId: page?.playbackListId) }
                Button {
                    if let first = tracks.first { player.play(first, playbackListId: page?.playbackListId) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.headline)
                        .frame(width: 120, height: 44)
                        .foregroundStyle(tint.map { $0.prefersLightText ? Color.black : .white } ?? Color(.systemBackground))
                        .background(textColor, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(tracks.isEmpty)
                circleButton("dot.radiowaves.left.and.right", label: "Station") {
                    if let first = tracks.first { player.play(videoId: first.videoId, playlistId: "RDAMVM\(first.videoId)") }
                }
            }
            .padding(.vertical, 4)
            .opacity(page == nil ? 0.4 : 1)

            if let description = detail?.description, !description.isEmpty, description != title(page) {
                Text(description)
                    .font(.footnote)
                    .opacity(0.75)
                    .lineLimit(3)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    /// The parser names playlists it doesn't understand "Unknown Playlist"; prefer anything better.
    private func title(_ page: YTMusicAPI.PlaylistPage?) -> String {
        let parsed = page?.response.detail.title ?? ""
        guard parsed == "Unknown Playlist" || parsed.isEmpty else { return parsed }
        return [fallbackTitle, page?.headerTitle ?? ""].first { !$0.isEmpty } ?? "Playlist"
    }

    private static func artworkURL(_ page: YTMusicAPI.PlaylistPage) -> URL? {
        page.response.detail.thumbnailURL ?? page.headerArtworkURL
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(textColor.opacity(0.15), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func metadata(_ detail: PlaylistDetail) -> String {
        var parts: [String] = []
        if detail.isAlbum { parts.append("Album") }
        if let count = detail.trackCount ?? (tracks.isEmpty ? nil : tracks.count) { parts.append(count == 1 ? "1 song" : "\(count) songs") }
        if let duration = detail.duration { parts.append(duration) }
        return parts.joined(separator: " · ")
    }

    /// Start the list, then shuffle the web player's queue (it has no shuffle-on-start option).
    private func shuffle(listId: String?) {
        guard let song = tracks.randomElement() else { return }
        player.play(song, playbackListId: listId)
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            player.shuffleQueue()
        }
    }

    private func removeTrack(_ song: Song) {
        withAnimation { tracks.removeAll { $0.playlistSetVideoId == song.playlistSetVideoId && $0.videoId == song.videoId } }
    }

    private func load() async {
        // Last copy first (instant), then fresh.
        if case .loading = page, let cached = try? await YTMusicAPI.shared.playlist(id: id, .staleOnly) {
            await show(cached)
        }
        do {
            await show(try await YTMusicAPI.shared.playlist(id: id))
        } catch {
            if case .loading = page { page = .failed(error.localizedDescription) }
        }
    }

    private func show(_ result: YTMusicAPI.PlaylistPage) async {
        if let artwork = Self.artworkURL(result) { covers.originalArtwork[YTMusicAPI.bareId(id)] = artwork }
        page = .loaded(result)
        tracks = result.response.detail.tracks
        await updateTint()
    }

    /// Generated covers tint the page with their palette; artwork tints it with its average colour.
    private func updateTint() async {
        let artwork = loaded.flatMap(Self.artworkURL) ?? fallbackArtwork
        if !isAlbum, covers.usesGeneratedCover(id: id, hasArtwork: artwork != nil) {
            tint = covers.style(for: id).colors.first?.mix(with: .black, by: 0.1)
        } else if let color = await ArtworkColor.color(for: artwork ?? tracks.first?.thumbnailURL) {
            tint = color.mix(with: .black, by: 0.1)
        }
    }
}

private extension View {
    /// A full-width list row with no background, separator or insets (page header, spinners, padding).
    func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }
}
