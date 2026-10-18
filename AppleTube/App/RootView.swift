import SwiftUI

/// Apple Music's shell: Home · Radio · Library · Search, the mini player floating above the tab bar, and
/// Now Playing zooming out of the mini player (drag it back down to close).
struct RootView: View {
    @State private var app = AppState.shared
    @Namespace private var playerZoom

    var body: some View {
        TabView(selection: $app.tab) {
            Tab("Home", systemImage: "house.fill", value: "home") { HomeView() }
            Tab("Radio", systemImage: "dot.radiowaves.left.and.right", value: "radio") { RadioView() }
            Tab("Library", systemImage: "music.note.square.stack.fill", value: "library") { LibraryView() }
            Tab(value: "search", role: .search) { SearchView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            MiniPlayer().matchedTransitionSource(id: "nowPlaying", in: playerZoom)
        }
        .fullScreenCover(isPresented: $app.isNowPlayingPresented) {
            NowPlayingView().navigationTransition(.zoom(sourceID: "nowPlaying", in: playerZoom))
        }
        .sheet(isPresented: $app.isAccountPresented) { AccountView() }
        .background(PlayerHost())
        .task {
            await app.refreshSignIn()
            // `-autoplayVideoId <id>` / `-showNowPlaying YES` for automated runs.
            if let id = UserDefaults.standard.string(forKey: "autoplayVideoId") { WebPlayer.shared.load(videoId: id) }
            if UserDefaults.standard.bool(forKey: "showNowPlaying") { app.isNowPlayingPresented = true }
            // `-thenPlayVideoId <id>` switches track after 30s, to exercise in-page (no reload) track changes.
            if let next = UserDefaults.standard.string(forKey: "thenPlayVideoId") {
                try? await Task.sleep(for: .seconds(30))
                WebPlayer.shared.play(videoId: next, playlistId: nil)
            }
        }
    }
}

/// Parks the hidden player web view in the window; WebKit only plays media for views in a window.
struct PlayerHost: UIViewRepresentable {
    func makeUIView(context _: Context) -> UIView { HostView() }
    func updateUIView(_: UIView, context _: Context) {}

    private final class HostView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { WebPlayer.shared.attach(to: window) }
        }
    }
}
