import SwiftUI

/// Library edits (likes, playlists, saved albums) with optimistic local state and a confirmation toast.
@MainActor
@Observable
final class LibraryState {
    static let shared = LibraryState()

    /// Your own playlists (newest first), for "Add to a Playlist" and for generated covers.
    private(set) var editablePlaylists: [Playlist] = []
    /// Remembered across launches so covers are right on the first frame, before the library reloads.
    private(set) var ownedPlaylistIds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "ownedPlaylistIds") ?? []) {
        didSet { UserDefaults.standard.set(Array(ownedPlaylistIds), forKey: "ownedPlaylistIds") }
    }
    private var liked: [String: Bool] = [:]
    private var inLibrary: [String: Bool] = [:]
    private var saved: [String: Bool] = [:]

    private var api: YTMusicAPI { .shared }
    private var signedIn: Bool { AppState.shared.signedIn == true }

    func refreshPlaylists() async {
        guard signedIn else { return }
        let playlists = await api.editablePlaylists()
        guard !playlists.isEmpty else { return }   // a failed fetch shouldn't wipe the remembered list
        editablePlaylists = playlists
        ownedPlaylistIds = Set(playlists.map { YTMusicAPI.bareId($0.id) })
    }

    func isOwned(_ playlistId: String) -> Bool {
        ownedPlaylistIds.contains(YTMusicAPI.bareId(playlistId))
    }

    // MARK: Songs

    func isLiked(_ song: Song) -> Bool { liked[song.videoId] ?? (song.likeStatus == .like) }
    func isInLibrary(_ song: Song) -> Bool { inLibrary[song.videoId] ?? (song.isInLibrary == true) }

    func toggleLike(_ song: Song) {
        let like = !isLiked(song)
        liked[song.videoId] = like
        run(success: like ? ("Loved", "heart.fill") : ("Removed from Loved", "heart.slash")) {
            try await self.api.setLiked(videoId: song.videoId, like)
        } undo: { self.liked[song.videoId] = !like }
    }

    func suggestLess(_ song: Song) {
        run(success: ("We'll suggest less like this", "hand.thumbsdown")) {
            _ = try await self.api.setDisliked(videoId: song.videoId)
        }
    }

    func toggleInLibrary(_ song: Song) {
        let add = !isInLibrary(song)
        inLibrary[song.videoId] = add
        run(success: add ? ("Added to Library", "checkmark") : ("Removed from Library", "minus.circle")) {
            try await self.api.setInLibrary(song, add)
        } undo: { self.inLibrary[song.videoId] = !add }
    }

    // MARK: Playlists

    func add(_ videoIds: [String], to playlist: Playlist) {
        guard !videoIds.isEmpty else { return }
        run(success: ("Added to \(playlist.title)", "text.badge.checkmark")) {
            try await self.api.addToPlaylist(videoIds: videoIds, playlistId: playlist.id)
        }
    }

    /// Asks for a name (alert in RootView), then creates the playlist with these songs.
    func newPlaylist(with videoIds: [String]) {
        AppState.shared.newPlaylistSongs = NewPlaylistRequest(videoIds: videoIds)
    }

    func createPlaylist(title: String, videoIds: [String]) {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        run(success: ("Created \(name)", "music.note.list")) {
            _ = try await self.api.createPlaylist(title: name, videoIds: videoIds)
            await self.refreshPlaylists()
        }
    }

    func remove(_ song: Song, fromPlaylist playlistId: String, onDone: @escaping () -> Void) {
        guard let setVideoId = song.playlistSetVideoId else { return }
        run(success: ("Removed from Playlist", "minus.circle")) {
            try await self.api.removeFromPlaylist(videoId: song.videoId, setVideoId: setVideoId, playlistId: playlistId)
            onDone()
        }
    }

    func isSaved(_ collectionId: String, default value: Bool = false) -> Bool { saved[collectionId] ?? value }

    /// Albums and other people's playlists: save to / remove from your library.
    func toggleSaved(collectionId: String, libraryId: String, title: String) {
        let save = !isSaved(collectionId)
        saved[collectionId] = save
        run(success: save ? ("Added \(title) to Library", "checkmark") : ("Removed from Library", "minus.circle")) {
            try await self.api.setSaved(playlistId: libraryId, save)
        } undo: { self.saved[collectionId] = !save }
    }

    func delete(playlistId: String, title: String) {
        run(success: ("Deleted \(title)", "trash")) {
            try await self.api.deletePlaylist(id: playlistId)
            await self.refreshPlaylists()
            AppState.shared.popIfShowing(playlistId: playlistId)
        }
    }

    /// Runs an edit; on failure rolls back the optimistic state and says why.
    private func run(success: (String, String), _ work: @escaping () async throws -> Void, undo: (() -> Void)? = nil) {
        guard signedIn else {
            AppState.shared.toast("Sign in to YouTube Music first", symbol: "person.crop.circle.badge.exclamationmark")
            return
        }
        Task {
            do {
                try await work()
                AppState.shared.toast(success.0, symbol: success.1)
            } catch {
                undo?()
                AppState.shared.toast("Couldn't do that: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
            }
        }
    }
}

struct NewPlaylistRequest: Identifiable {
    let id = UUID()
    let videoIds: [String]
}

// MARK: - Menus

/// "Add to a Playlist" submenu: New Playlist… then your playlists.
struct AddToPlaylistSubmenu: View {
    /// Songs to add; async so albums/playlists can load their tracks first.
    let videoIds: () async -> [String]
    @State private var library = LibraryState.shared

    var body: some View {
        Menu {
            Button("New Playlist…", systemImage: "plus") {
                Task { library.newPlaylist(with: await videoIds()) }
            }
            if !library.editablePlaylists.isEmpty {
                Divider()
                ForEach(library.editablePlaylists) { playlist in
                    Button(playlist.title) { Task { library.add(await videoIds(), to: playlist) } }
                }
            }
        } label: {
            Label("Add to a Playlist", systemImage: "text.badge.plus")
        }
    }
}

/// Everything you can do with one song, grouped the way Apple Music groups them. `context` adds the actions
/// that only make sense where the song is shown (your own playlist, the queue, Now Playing).
struct SongMenu: View {
    enum Context: Equatable {
        case standard
        case nowPlaying
        case inPlaylist(id: String)
        case queue(index: Int)
    }

    let song: Song
    var context: Context = .standard
    /// Called after the song is removed from the playlist it's shown in.
    var onRemoved: () -> Void = {}

    @State private var library = LibraryState.shared
    @State private var app = AppState.shared

    var body: some View {
        if app.signedIn == true {
            Section {
                if song.feedbackTokens != nil {
                    Button(library.isInLibrary(song) ? "Remove from Library" : "Add to Library",
                           systemImage: library.isInLibrary(song) ? "minus.circle" : "plus") { library.toggleInLibrary(song) }
                }
                AddToPlaylistSubmenu { [song.videoId] }
            }
        }
        if context != .nowPlaying {
            Section {
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { WebPlayer.shared.playNext(videoId: song.videoId) }
                Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") { WebPlayer.shared.playLast(videoId: song.videoId) }
            }
        }
        Section {
            ShareLink(item: URL(string: "https://music.youtube.com/watch?v=\(song.videoId)")!,
                      subject: Text(song.title), message: Text("\(song.title) · \(song.artistsDisplay)")) {
                Label("Share Song…", systemImage: "square.and.arrow.up")
            }
            Button("Create Station", systemImage: "dot.radiowaves.left.and.right") {
                WebPlayer.shared.play(videoId: song.videoId, playlistId: "RDAMVM\(song.videoId)")
            }
        }
        if app.signedIn == true {
            Section {
                Button(library.isLiked(song) ? "Remove from Loved" : "Love",
                       systemImage: library.isLiked(song) ? "heart.slash" : "heart") { library.toggleLike(song) }
                Button("Suggest Less Like This", systemImage: "hand.thumbsdown") { library.suggestLess(song) }
            }
        }
        Section {
            if let album = song.album, album.hasNavigableId {
                Button("Go to Album", systemImage: "square.stack") {
                    app.show(.playlist(id: album.id, title: album.title, artwork: album.thumbnailURL ?? song.thumbnailURL))
                }
            }
            if let artist = song.artists.first(where: \.hasNavigableId) {
                Button("Go to Artist", systemImage: "music.microphone") { app.show(.artist(id: artist.id, name: artist.name)) }
            }
        }
        switch context {
        case let .inPlaylist(id) where library.isOwned(id) && song.playlistSetVideoId != nil:
            Section {
                Button("Remove from This Playlist", systemImage: "minus.circle", role: .destructive) {
                    library.remove(song, fromPlaylist: id, onDone: onRemoved)
                }
            }
        case let .queue(index):
            Section {
                Button("Remove from Queue", systemImage: "minus.circle", role: .destructive) { WebPlayer.shared.removeFromQueue(at: index) }
            }
        default:
            EmptyView()
        }
    }
}

/// Actions for an album or playlist (card long-press and the page's ⋯ button).
struct CollectionMenu: View {
    enum Kind { case album, playlist }

    let kind: Kind
    let id: String
    let title: String
    var artistRoute: Route?
    /// The list the web player queues (album OLAK… / bare playlist id); resolved by loading the page if nil.
    var playbackListId: String?
    var isSavedByDefault = false

    @State private var library = LibraryState.shared
    @State private var app = AppState.shared
    @State private var covers = CoverStore.shared

    private var isOwned: Bool { kind == .playlist && library.isOwned(id) }
    private var isSaved: Bool { library.isSaved(id, default: isSavedByDefault) }

    var body: some View {
        Section {
            Button("Play", systemImage: "play") { Task { if let list = await listId() { WebPlayer.shared.play(playlistId: list) } } }
            Button("Shuffle", systemImage: "shuffle") {
                Task {
                    guard let list = await listId() else { return }
                    WebPlayer.shared.play(playlistId: list)
                    try? await Task.sleep(for: .seconds(2.5))   // let the web player build the queue first
                    WebPlayer.shared.shuffleQueue()
                }
            }
        }
        Section {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                Task { if let list = await listId() { WebPlayer.shared.playNext(playlistId: list) } }
            }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                Task { if let list = await listId() { WebPlayer.shared.playLast(playlistId: list) } }
            }
        }
        if app.signedIn == true {
            Section {
                if !isOwned {
                    Button(isSaved ? "Remove from Library" : "Add to Library", systemImage: isSaved ? "minus.circle" : "plus") {
                        Task {
                            guard let list = await listId() else { return }
                            library.toggleSaved(collectionId: id, libraryId: list, title: title)
                        }
                    }
                }
                AddToPlaylistSubmenu {
                    (try? await YTMusicAPI.shared.playlist(id: id).response.detail.tracks.map(\.videoId)) ?? []
                }
            }
        }
        Section {
            ShareLink(item: shareURL, subject: Text(title)) {
                Label(kind == .album ? "Share Album…" : "Share Playlist…", systemImage: "square.and.arrow.up")
            }
            if kind == .playlist {
                Button("Edit Cover…", systemImage: "paintpalette") { covers.editing = CoverEditRequest(playlistId: id, title: title) }
            }
            if let artistRoute {
                Button("Go to Artist", systemImage: "music.microphone") { app.show(artistRoute) }
            }
        }
        if isOwned {
            Section {
                Button("Delete Playlist", systemImage: "trash", role: .destructive) {
                    app.confirmDelete = DeleteRequest(playlistId: id, title: title)
                }
            }
        }
    }

    private var shareURL: URL {
        kind == .album
            ? URL(string: "https://music.youtube.com/browse/\(id)")!
            : URL(string: "https://music.youtube.com/playlist?list=\(YTMusicAPI.bareId(id))")!
    }

    private func listId() async -> String? {
        if let playbackListId { return playbackListId }
        return try? await YTMusicAPI.shared.playlist(id: id).playbackListId
    }
}

struct ArtistMenu: View {
    let artist: Artist

    var body: some View {
        Button("Go to Artist", systemImage: "music.microphone") { AppState.shared.show(.artist(id: artist.id, name: artist.name)) }
        ShareLink(item: URL(string: "https://music.youtube.com/channel/\(artist.id)")!, subject: Text(artist.name)) {
            Label("Share Artist…", systemImage: "square.and.arrow.up")
        }
    }
}

/// Long-press menu for any card.
struct ItemMenu: View {
    let item: HomeSectionItem

    var body: some View {
        switch item {
        case let .song(song):
            SongMenu(song: song)
        case let .album(album):
            CollectionMenu(kind: .album, id: album.id, title: album.title,
                           artistRoute: album.artists?.first(where: \.hasNavigableId).map { .artist(id: $0.id, name: $0.name) },
                           playbackListId: album.libraryTargetId)
        case let .playlist(playlist):
            CollectionMenu(kind: .playlist, id: playlist.id, title: playlist.title)
        case let .artist(artist):
            ArtistMenu(artist: artist)
        }
    }
}

struct DeleteRequest: Identifiable {
    var id: String { playlistId }
    let playlistId: String
    let title: String
}

extension Song {
    /// A song known only by what the player or queue shows (no album/artist IDs or library tokens).
    static func minimal(videoId: String, title: String, artist: String, artwork: URL?) -> Song {
        Song(id: videoId, title: title, artists: artist.isEmpty ? [] : [Artist(id: "", name: artist)], thumbnailURL: artwork, videoId: videoId)
    }
}
