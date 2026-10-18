import SwiftUI

/// Apple Music's mini player, shown as the tab bar's bottom accessory (it collapses next to the tab bar
/// when scrolling, like iOS 26). Tapping it opens Now Playing.
struct MiniPlayer: View {
    @State private var player = WebPlayer.shared
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(url: player.artworkURL, cornerRadius: 6, pixelSize: 120)
                .frame(width: placement == .inline ? 28 : 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.title.isEmpty ? "Not Playing" : player.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if placement != .inline, !player.artist.isEmpty {
                    Text(player.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            if placement != .inline {
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title3).frame(width: 36, height: 36)
                }
                .accessibilityLabel("Next")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .contentShape(.rect)
        .onTapGesture { AppState.shared.isNowPlayingPresented = true }
    }
}
