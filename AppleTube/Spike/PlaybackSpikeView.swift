import SwiftUI

/// Playback diagnostics (Account → Playback Test): play a track by video ID and watch the player state.
struct PlaybackSpikeView: View {
    @State private var signedIn: Bool?
    @State private var showLogin = false
    @State private var videoId = "dQw4w9WgXcQ"
    private let player = WebPlayer.shared

    var body: some View {
        Form {
                Section("Account") {
                    LabeledContent("YouTube Music", value: signedIn == nil ? "Checking…" : (signedIn! ? "Signed in" : "Signed out"))
                    if signedIn == true {
                        Button("Sign out", role: .destructive) {
                            Task { await WebSession.signOut(); signedIn = await WebSession.isSignedIn() }
                        }
                    } else {
                        Button("Sign in to YouTube Music") { showLogin = true }
                    }
                }

                Section("Test track") {
                    TextField("Video ID", text: $videoId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Load and play") { player.load(videoId: videoId) }
                }

                Section("Now playing") {
                    HStack(spacing: 12) {
                        AsyncImage(url: player.artworkURL) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
                            .frame(width: 56, height: 56)
                            .clipShape(.rect(cornerRadius: 6))
                        VStack(alignment: .leading) {
                            Text(player.title.isEmpty ? "Nothing playing" : player.title).font(.headline)
                            Text(player.artist).foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: min(player.position, max(player.duration, 1)), total: max(player.duration, 1))
                    HStack {
                        Spacer()
                        Button { player.previous() } label: { Image(systemName: "backward.fill") }
                        Spacer()
                        Button { player.togglePlayPause() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
                        Spacer()
                        Button { player.next() } label: { Image(systemName: "forward.fill") }
                        Spacer()
                    }
                    .buttonStyle(.borderless)
                    .font(.title2)
                    LabeledContent("Status", value: player.status)
                    LabeledContent("Position", value: "\(Int(player.position))s / \(Int(player.duration))s")
                }
            }
        .navigationTitle("Playback Test")
        .sheet(isPresented: $showLogin) {
            NavigationStack {
                LoginView {
                    showLogin = false
                    signedIn = true
                }
                .navigationTitle("Sign in")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Cancel") { showLogin = false } }
            }
        }
        .task {
            signedIn = await WebSession.isSignedIn()
        }
        .onChange(of: player.title) { _, title in
            if !title.isEmpty { print("[AppleTube] now playing: \(title) — \(player.artist) [\(player.status)]") }
        }
    }
}
