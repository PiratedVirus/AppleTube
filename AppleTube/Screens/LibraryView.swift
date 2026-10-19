import SwiftUI

/// Apple Music "Library": category rows (Playlists, Artists, Albums, Songs) then a "Recently Added" grid.
struct LibraryView: View {
    @State private var app = AppState.shared
    @State private var content: Loadable<PlaylistParser.LibraryContent> = .loading
    @State private var playlists: [Playlist] = []
    @State private var settings = AppSettings.shared
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            Group {
                if app.signedIn == nil {
                    ProgressView()
                } else if app.signedIn == false {
                    ContentUnavailableView {
                        Label("Sign In to See Your Library", systemImage: "music.note.house")
                    } description: {
                        Text("Your YouTube Music playlists, albums and artists appear here.")
                    } actions: {
                        Button("Sign In") { app.isAccountPresented = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    library
                }
            }
            .navigationTitle("Library")
            .toolbar {
                if app.signedIn == true {
                    ToolbarItem(placement: .topBarLeading) { Button("Edit") { isEditing = true } }
                }
                ToolbarItem(placement: .topBarTrailing) { AccountButton() }
            }
            .sheet(isPresented: $isEditing) { LibraryCategoriesEditor() }
            .musicDestinations()
            .navigationDestination(for: LibraryCategory.self) { LibraryCategoryView(category: $0, content: loadedContent, playlists: playlists) }
            .task(id: app.signedIn) { if app.signedIn == true { await load() } }
        }
    }

    private var loadedContent: PlaylistParser.LibraryContent? {
        if case let .loaded(content) = content { content } else { nil }
    }

    /// A ScrollView, not a List: a List row holding several links fires all of them on one tap, which pushed
    /// a stack of playlists (Back then "rotated" through them).
    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(settings.libraryCategories) { category in
                    NavigationLink(value: category) {
                        HStack {
                            Label(category.title, systemImage: category.symbol)
                                .font(.title3)
                                .labelStyle(LibraryRowLabelStyle())
                            Spacer()
                            Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 58)
                }

                Text("Recently Added").font(.title2.bold()).padding(.horizontal)
                    .padding(.top, settings.libraryCategories.isEmpty ? 4 : 24).padding(.bottom, 10)
                switch content {
                case .loading:
                    LoadingView()
                case let .failed(message):
                    ErrorView(message: message) { Task { await load() } }
                case .loaded:
                    RecentlyAddedGrid(playlists: playlists, albums: loadedContent?.albums ?? []).padding(.horizontal)
                }
            }
            .padding(.bottom, 100)
        }
        .refreshable { await load() }
    }

    private func load() async {
        // Last session's library first (instant), then fresh.
        if case .loading = content, let cached = try? await YTMusicAPI.shared.libraryLanding(.staleOnly) {
            playlists = (try? await YTMusicAPI.shared.libraryPlaylists(.staleOnly)) ?? cached.playlists
            content = .loaded(cached)
        }
        do {
            async let landing = YTMusicAPI.shared.libraryLanding()
            async let lists = YTMusicAPI.shared.libraryPlaylists()
            let (content, playlists) = try await (landing, lists)
            self.playlists = playlists.isEmpty ? content.playlists : playlists
            self.content = .loaded(content)
            await LibraryState.shared.refreshPlaylists()
        } catch {
            if case .loading = content { content = .failed(error.localizedDescription) }
        }
    }
}

enum LibraryCategory: String, CaseIterable, Identifiable, Hashable {
    case playlists, artists, albums, songs
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .playlists: "music.note.list"
        case .artists: "music.microphone"
        case .albums: "square.stack"
        case .songs: "music.note"
        }
    }
}

private struct LibraryRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) {
            configuration.icon.foregroundStyle(Color.musicAccent).frame(width: 28)
            configuration.title
        }
        .padding(.vertical, 6)
    }
}

private struct RecentlyAddedGrid: View {
    let playlists: [Playlist]
    let albums: [Album]
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        let items: [HomeSectionItem] = albums.map { .album($0) } + playlists.map { .playlist($0) }
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(items.prefix(20)) { ItemCard(item: $0, width: nil) }
        }
    }
}

/// One library category as a list, Apple Music style.
private struct LibraryCategoryView: View {
    let category: LibraryCategory
    let content: PlaylistParser.LibraryContent?
    let playlists: [Playlist]

    var body: some View {
        List {
            switch category {
            case .playlists:
                Button { LibraryState.shared.newPlaylist(with: []) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundStyle(Color.musicAccent)
                            .frame(width: 56, height: 56)
                            .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 6))
                        Text("New Playlist…").foregroundStyle(Color.musicAccent)
                    }
                }
                ForEach(playlists) { playlist in
                    NavigationLink(value: Route.playlist(id: playlist.id, title: playlist.title, artwork: playlist.thumbnailURL)) {
                        HStack(spacing: 12) {
                            PlaylistArtwork(id: playlist.id, title: playlist.title, url: playlist.thumbnailURL, cornerRadius: 6, pixelSize: 160)
                                .frame(width: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.title).lineLimit(1)
                                if let author = playlist.author?.name {
                                    Text(author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                    .contextMenu { ItemMenu(item: .playlist(playlist)) }
                }
            case .artists:
                ForEach(content?.artists ?? []) { artist in
                    NavigationLink(value: Route.artist(id: artist.id, name: artist.name)) {
                        row(url: artist.thumbnailURL, title: artist.name, subtitle: nil, circle: true)
                    }
                    .contextMenu { ArtistMenu(artist: artist) }
                }
            case .albums:
                ForEach(content?.albums ?? []) { album in
                    NavigationLink(value: Route.playlist(id: album.id, title: album.title, artwork: album.thumbnailURL)) {
                        row(url: album.thumbnailURL, title: album.title, subtitle: album.artistsDisplay)
                    }
                    .contextMenu { ItemMenu(item: .album(album)) }
                }
            case .songs:
                // Liked songs are YouTube Music's "LM" playlist.
                NavigationLink(value: Route.playlist(id: LikedMusicPlaylist.id, title: "Liked Songs")) {
                    Label("Liked Songs", systemImage: "heart.fill").foregroundStyle(Color.musicAccent)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.title)
    }

    private func row(url: URL?, title: String, subtitle: String?, circle: Bool = false) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: url, cornerRadius: 6, isCircle: circle, pixelSize: 160).frame(width: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
}

/// Apple Music's Library "Edit": tick the categories to show and drag to reorder. All can be hidden.
struct LibraryCategoriesEditor: View {
    @State private var settings = AppSettings.shared
    /// false when pushed from Settings (no own navigation stack or Done button).
    var inSheet = true
    @State private var order: [LibraryCategory] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if inSheet {
            NavigationStack { editor.toolbar { Button("Done") { dismiss() }.bold() } }
        } else {
            editor
        }
    }

    private var editor: some View {
            List {
                Section {
                    ForEach(order) { category in
                        Button {
                            toggle(category)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: settings.libraryCategories.contains(category) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(settings.libraryCategories.contains(category) ? Color.musicAccent : .secondary)
                                    .contentTransition(.symbolEffect(.replace))
                                Label(category.title, systemImage: category.symbol)
                                    .foregroundStyle(Color(uiColor: .label))
                            }
                        }
                        .accessibilityAddTraits(settings.libraryCategories.contains(category) ? .isSelected : [])
                    }
                    .onMove { from, to in
                        order.move(fromOffsets: from, toOffset: to)
                        settings.libraryCategories = order.filter(settings.libraryCategories.contains)
                    }
                } footer: {
                    Text("Choose what appears at the top of your Library. Drag to reorder.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                order = settings.libraryCategories + LibraryCategory.allCases.filter { !settings.libraryCategories.contains($0) }
            }
    }

    private func toggle(_ category: LibraryCategory) {
        if settings.libraryCategories.contains(category) {
            settings.libraryCategories.removeAll { $0 == category }
        } else {
            settings.libraryCategories = order.filter { settings.libraryCategories.contains($0) || $0 == category }
        }
    }
}
