import Foundation

/// Songs played in this app, newest last, for the History section above the queue. Kept on the device.
@MainActor
@Observable
final class PlaybackHistory {
    static let shared = PlaybackHistory()

    struct Entry: Codable, Identifiable, Hashable {
        let videoId: String
        let title: String
        let artist: String
        let artworkURL: URL?
        var id: String { videoId }
    }

    private(set) var entries: [Entry] = []
    private let key = "playbackHistory"
    private let limit = 100

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    /// Records a song once it's actually playing; replaying a song moves it to the end.
    func record(videoId: String, title: String, artist: String, artworkURL: URL?) {
        guard !videoId.isEmpty, !title.isEmpty, entries.last?.videoId != videoId else { return }
        entries.removeAll { $0.videoId == videoId }
        entries.append(Entry(videoId: videoId, title: title, artist: artist, artworkURL: artworkURL))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}
