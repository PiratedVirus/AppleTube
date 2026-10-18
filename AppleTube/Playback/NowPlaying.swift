import AVFoundation
import MediaPlayer
import UIKit

/// Publishes the web player's state to the Lock Screen / Control Center and routes remote commands back to it.
@MainActor
final class NowPlaying {
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?

    static func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AppleTube] audio session error: \(error)")
        }
    }

    func connect(to player: WebPlayer) {
        let center = MPRemoteCommandCenter.shared()
        func handle(_ command: MPRemoteCommand, _ action: @escaping @MainActor (WebPlayer) -> Void) {
            command.isEnabled = true
            command.addTarget { [weak player] _ in
                guard let player else { return .commandFailed }
                MainActor.assumeIsolated { action(player) }
                return .success
            }
        }
        handle(center.playCommand) { $0.play() }
        handle(center.pauseCommand) { $0.pause() }
        handle(center.togglePlayPauseCommand) { $0.togglePlayPause() }
        handle(center.nextTrackCommand) { $0.next() }
        handle(center.previousTrackCommand) { $0.previous() }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak player] event in
            guard let player, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { player.seek(to: event.positionTime) }
            return .success
        }
    }

    func update(from player: WebPlayer) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: player.title,
            MPMediaItemPropertyArtist: player.artist,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.position,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
        ]
        if player.artworkURL == artworkURL, let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        } else if let url = player.artworkURL {
            loadArtwork(url)
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = player.isPlaying ? .playing : .paused
    }

    private func loadArtwork(_ url: URL) {
        artworkURL = url
        artwork = nil
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data), url == artworkURL else { return }
            artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            update(from: WebPlayer.shared)
        }
    }
}
