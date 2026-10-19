import SwiftUI

@main
struct AppleTubeApp: App {
    init() {
        NowPlaying.activateAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
        }
    }
}

/// Applies the accent colour and theme from Settings to the whole app.
private struct ThemedRoot: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        RootView()
            .tint(settings.accent.color)
            .preferredColorScheme(settings.theme.colorScheme)
    }
}
