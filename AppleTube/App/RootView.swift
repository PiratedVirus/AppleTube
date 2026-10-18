import SwiftUI

/// Apple Music-style tab layout. Screens are placeholders until Stage 4.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") { PlaybackSpikeView() } // Stage 2 test screen
            Tab("New", systemImage: "square.grid.2x2.fill") { placeholder("New") }
            Tab("Radio", systemImage: "dot.radiowaves.left.and.right") { placeholder("Radio") }
            Tab("Library", systemImage: "music.note.square.stack.fill") { placeholder("Library") }
            Tab(role: .search) { placeholder("Search") }
        }
    }

    private func placeholder(_ title: String) -> some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: "music.note", description: Text("Coming in Stage 4"))
                .navigationTitle(title)
        }
    }
}

#Preview { RootView() }
