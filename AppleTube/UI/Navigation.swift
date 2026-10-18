import SwiftUI

/// Pages any tab can push.
enum Route: Hashable {
    case playlist(id: String, title: String)
    case artist(id: String, name: String)
}

extension View {
    /// Registers the shared destinations; call once per tab's NavigationStack root.
    func musicDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case let .playlist(id, title): PlaylistDetailView(id: id, fallbackTitle: title)
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
        case let .album(album): .playlist(id: album.id, title: album.title)
        case let .playlist(playlist): .playlist(id: playlist.id, title: playlist.title)
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
    // Developer launch argument for screenshots: `-startTab new|radio|library|search`.
    var tab = UserDefaults.standard.string(forKey: "startTab") ?? "home"
    var homePath = NavigationPath()

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

    func refreshSignIn() async {
        signedIn = await WebSession.isSignedIn()
    }
}

/// The round profile button Apple Music puts in each tab's top-right corner.
struct AccountButton: View {
    @State private var app = AppState.shared

    var body: some View {
        Button {
            app.isAccountPresented = true
        } label: {
            Image(systemName: app.signedIn == true ? "person.crop.circle.fill" : "person.crop.circle.badge.exclamationmark")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityLabel("Account")
    }
}
