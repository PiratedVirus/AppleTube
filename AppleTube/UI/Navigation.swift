import SwiftUI

/// Pages any tab can push.
enum Route: Hashable {
    /// `artwork` (from the card that was tapped) lets the page paint its header before the data arrives.
    case playlist(id: String, title: String, artwork: URL? = nil)
    case artist(id: String, name: String)
}

extension View {
    /// Registers the shared destinations; call once per tab's NavigationStack root. Pages slide in like
    /// Apple Music's, which keeps the edge swipe-back gesture.
    func musicDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case let .playlist(id, title, artwork): PlaylistDetailView(id: id, fallbackTitle: title, fallbackArtwork: artwork)
            case let .artist(id, name): ArtistView(id: id, fallbackName: name)
            }
        }
    }
}

extension HomeSectionItem {
    /// Where tapping this card goes; nil means "play it".
    var route: Route? {
        switch self {
        case .song: nil
        case let .album(album): .playlist(id: album.id, title: album.title, artwork: album.thumbnailURL)
        case let .playlist(playlist): .playlist(id: playlist.id, title: playlist.title, artwork: playlist.thumbnailURL)
        case let .artist(artist): .artist(id: artist.id, name: artist.name)
        }
    }
}

/// App-wide UI state: signed-in status and the full-screen player.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()
    var isNowPlayingPresented = false
    var isAccountPresented = false
    var signedIn: Bool?
    // Developer launch argument for screenshots: `-startTab radio|library|search`.
    var tab = UserDefaults.standard.string(forKey: "startTab") ?? "home"
    var homePath = NavigationPath()
    /// Bumped when the already-selected Search tab is tapped again; SearchView focuses its field.
    var searchFocusRequest = 0
    var newPlaylistSongs: NewPlaylistRequest?
    var confirmDelete: DeleteRequest?
    private(set) var currentToast: Toast?
    /// Playlist pages close themselves when their playlist is deleted.
    var deletedPlaylistId: String?

    struct Toast: Equatable {
        let id = UUID()
        let message: String
        let symbol: String
    }

    /// Apple Music-style HUD confirming an action ("Added to Library").
    func toast(_ message: String, symbol: String) {
        let toast = Toast(message: message, symbol: symbol)
        withAnimation(.spring(duration: 0.35)) { currentToast = toast }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if currentToast == toast { withAnimation(.easeOut(duration: 0.25)) { currentToast = nil } }
        }
    }

    func popIfShowing(playlistId: String) {
        deletedPlaylistId = YTMusicAPI.bareId(playlistId)
    }

    /// Closes Now Playing and opens a page on the Home tab (Apple Music does the same from the player).
    func show(_ route: Route) {
        isNowPlayingPresented = false
        tab = "home"
        homePath.append(route)
    }

    /// Starts a song from a list and brings up Now Playing.
    func playAndShow(_ song: Song, playbackListId: String? = nil) {
        WebPlayer.shared.play(song, playbackListId: playbackListId)
        isNowPlayingPresented = true
    }

    /// Remembered so the profile photo shows instantly on launch.
    var account: YTMusicAPI.AccountInfo? = UserDefaults.standard.data(forKey: "account")
        .flatMap { try? JSONDecoder().decode(YTMusicAPI.AccountInfo.self, from: $0) } {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(account), forKey: "account") }
    }

    func refreshSignIn() async {
        signedIn = await WebSession.isSignedIn()
        guard signedIn == true else {
            account = nil
            return
        }
        if let info = await YTMusicAPI.shared.account() { account = info }
        await LibraryState.shared.refreshPlaylists()
    }
}

/// The round profile button Apple Music puts in each tab's top-right corner: your photo (chosen in Settings,
/// else your Google photo), else your initial, else a person symbol.
struct AccountButton: View {
    @State private var app = AppState.shared

    var body: some View {
        Button {
            app.isAccountPresented = true
        } label: {
            ProfileAvatar(size: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account and Settings")
    }
}

struct ProfileAvatar: View {
    let size: CGFloat
    @State private var app = AppState.shared
    @State private var settings = AppSettings.shared

    var body: some View {
        Group {
            if let data = settings.customProfilePhoto, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url = app.account?.photoURL {
                CachedImage(url: url) { initials }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
    }

    @ViewBuilder
    private var initials: some View {
        if let letter = app.account?.name.first {
            Text(String(letter).uppercased())
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LinearGradient(colors: [Color.musicAccent.mix(with: .white, by: 0.2), .musicAccent], startPoint: .top, endPoint: .bottom))
        } else {
            Image(systemName: app.signedIn == true ? "person.crop.circle.fill" : "person.crop.circle.badge.exclamationmark")
                .resizable()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.musicAccent)
        }
    }
}

extension View {
    /// Toasts and the prompts library actions raise. Applied to the root and to Now Playing (which covers it).
    func libraryPrompts() -> some View { modifier(LibraryPrompts()) }
}

private struct LibraryPrompts: ViewModifier {
    @State private var app = AppState.shared
    @State private var covers = CoverStore.shared
    @State private var newName = ""

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = app.currentToast {
                    Label(toast.message, systemImage: toast.symbol)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .id(toast.id)
                        .sensoryFeedback(.success, trigger: toast.id)
                }
            }
            .alert("New Playlist", isPresented: Binding(get: { app.newPlaylistSongs != nil }, set: { if !$0 { app.newPlaylistSongs = nil } })) {
                TextField("Playlist Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Create") {
                    LibraryState.shared.createPlaylist(title: newName, videoIds: app.newPlaylistSongs?.videoIds ?? [])
                    newName = ""
                }
            } message: {
                if let count = app.newPlaylistSongs?.videoIds.count, count > 0 {
                    Text(count == 1 ? "The song will be added to it." : "\(count) songs will be added to it.")
                }
            }
            .confirmationDialog("Delete \(app.confirmDelete?.title ?? "playlist")?",
                                isPresented: Binding(get: { app.confirmDelete != nil }, set: { if !$0 { app.confirmDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete Playlist", role: .destructive) {
                    if let request = app.confirmDelete { LibraryState.shared.delete(playlistId: request.playlistId, title: request.title) }
                }
            } message: {
                Text("This deletes it from your YouTube Music account.")
            }
            .sheet(item: $covers.editing) { request in
                EditCoverView(request: request, originalArtwork: covers.originalArtwork[YTMusicAPI.bareId(request.playlistId)])
            }
    }
}
