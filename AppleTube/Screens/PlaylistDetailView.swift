import SwiftUI

/// Album and playlist page in the iOS 26.4 style: the whole page is tinted with the artwork's colour,
/// centred artwork, title/artist, Shuffle · Play · More buttons, then the track list.
struct PlaylistDetailView: View {
    let id: String
    let fallbackTitle: String

    @State private var page: Loadable<(detail: PlaylistDetail, listId: String?)> = .loading
    @State private var tint: Color = Color(.systemBackground)
    @State private var player = WebPlayer.shared
    @State private var artistRoute: Route?

    var body: some View {
        // A List (not a ScrollView) so track rows get Apple Music's swipe actions.
        List {
            switch page {
            case .loading:
                LoadingView().plainRow()
            case let .failed(message):
                ErrorView(message: message) { Task { await load() } }.plainRow()
            case let .loaded((detail, listId)):
                header(detail: detail, listId: listId).plainRow()
                ForEach(Array(detail.tracks.enumerated()), id: \.offset) { index, song in
                    SongRow(song: song, index: index + 1, showsArtwork: !detail.isAlbum, isCurrent: player.videoId == song.videoId) {
                        player.play(song, playbackListId: listId)
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
        // Light or dark text to suit the artwork tint, so .primary/.secondary in rows stay readable.
        .environment(\.colorScheme, isTinted && tint.prefersLightText ? .dark : .light)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .navigationDestination(item: $artistRoute) { route in
            if case let .artist(id, name) = route { ArtistView(id: id, fallbackName: name) }
        }
    }

    private var isTinted: Bool { if case .loaded = page { true } else { false } }
    private var textColor: Color { isTinted ? (tint.prefersLightText ? .white : .black) : .primary }

    private var background: some View {
        LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.25)], startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder
    private func header(detail: PlaylistDetail, listId: String?) -> some View {
        VStack(spacing: 14) {
            ArtworkView(url: detail.thumbnailURL, cornerRadius: 12)
                .frame(width: 260)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text(detail.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if let author = detail.author {
                    // A Button, not a NavigationLink: inside a List a link turns into a full-width chevron row.
                    Button { artistRoute = author.hasNavigableId ? .artist(id: author.id, name: author.name) : nil } label: {
                        Text(author.name).font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                Text(metadata(detail))
                    .font(.footnote.weight(.medium))
                    .opacity(0.7)
            }
            .padding(.horizontal)

            HStack(spacing: 14) {
                circleButton("shuffle") { shuffle(detail, listId: listId) }
                Button {
                    if let first = detail.tracks.first { player.play(first, playbackListId: listId) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.headline)
                        .frame(width: 120, height: 44)
                        .foregroundStyle(tint.prefersLightText ? .black : .white)
                        .background(textColor, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(detail.tracks.isEmpty)
                circleButton("dot.radiowaves.left.and.right") {
                    if let first = detail.tracks.first { player.play(videoId: first.videoId, playlistId: "RDAMVM\(first.videoId)") }
                }
            }
            .padding(.vertical, 4)

            if let description = detail.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .opacity(0.75)
                    .lineLimit(3)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(textColor.opacity(0.15), in: .circle)
        }
        .buttonStyle(.plain)
    }

    private func metadata(_ detail: PlaylistDetail) -> String {
        var parts: [String] = []
        if detail.isAlbum { parts.append("Album") }
        if let count = detail.trackCount ?? (detail.tracks.isEmpty ? nil : detail.tracks.count) { parts.append("\(count) songs") }
        if let duration = detail.duration { parts.append(duration) }
        return parts.joined(separator: " · ")
    }

    /// The web player has no shuffle URL, so start the list from a random track.
    private func shuffle(_ detail: PlaylistDetail, listId: String?) {
        guard let song = detail.tracks.randomElement() else { return }
        player.play(song, playbackListId: listId)
    }

    private func load() async {
        do {
            let result = try await YTMusicAPI.shared.playlist(id: id)
            if let color = await ArtworkColor.color(for: result.response.detail.thumbnailURL) {
                tint = color.mix(with: .black, by: 0.1)
            }
            withAnimation(.easeOut(duration: 0.25)) {
                page = .loaded((result.response.detail, result.playbackListId))
            }
        } catch {
            page = .failed(error.localizedDescription)
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
