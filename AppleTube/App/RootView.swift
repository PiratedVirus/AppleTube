import SwiftUI

/// Apple Music's iOS 26 shell: Home · New · Radio · Library tabs with Search split off on the right,
/// the mini player floating above the tab bar, and Now Playing as a full-screen sheet.
struct RootView: View {
    @State private var app = AppState.shared
    // Developer launch arguments for screenshots: `-startTab new|radio|library|search`.
    @State private var tab = UserDefaults.standard.string(forKey: "startTab") ?? "home"

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: "home") { HomeView() }
            Tab("New", systemImage: "square.grid.2x2.fill", value: "new") { NewView() }
            Tab("Radio", systemImage: "dot.radiowaves.left.and.right", value: "radio") { RadioView() }
            Tab("Library", systemImage: "music.note.square.stack.fill", value: "library") { LibraryView() }
            Tab(value: "search", role: .search) { SearchView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { MiniPlayer() }
        .fullScreenCover(isPresented: $app.isNowPlayingPresented) { NowPlayingView() }
        .sheet(isPresented: $app.isAccountPresented) { AccountView() }
        .background(PlayerHost())
        .task {
            await app.refreshSignIn()
            // `-autoplayVideoId <id>` / `-showNowPlaying YES` for automated runs.
            if let id = UserDefaults.standard.string(forKey: "autoplayVideoId") { WebPlayer.shared.load(videoId: id) }
            if UserDefaults.standard.bool(forKey: "showNowPlaying") { app.isNowPlayingPresented = true }
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
