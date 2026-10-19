import Foundation

/// One entry in YouTube Music's play queue, as read from the web player's queue panel.
struct QueueItem: Identifiable, Hashable {
    let id: String          // position-qualified, since a song can appear twice
    let videoId: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let duration: String?
}

enum RepeatMode: String {
    case off, all, one

    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

/// Queue control. YouTube Music's web app ignores queue commands sent straight to it, so (as Kaset found) the
/// reliable path is the page's own UI: open a queue row's menu and click the real "Play next" / "Add to queue" /
/// "Remove from queue" item, retargeting the add items at our song. All verified against music.youtube.com.
extension WebPlayer {
    func jump(toQueueIndex index: Int) { run("window.__atQueue?.jump(\(index))") }
    func removeFromQueue(at index: Int) { run("window.__atQueue?.remove(\(index))") }
    func playNext(videoId: String) { addToQueue(target: ["videoId": videoId], position: "INSERT_AFTER_CURRENT_VIDEO") }
    func playLast(videoId: String) { addToQueue(target: ["videoId": videoId], position: "INSERT_AT_END") }
    /// Whole albums/playlists go into the queue in one step (verified: an 11-track album inserts as 11 rows).
    func playNext(playlistId: String) { addToQueue(target: ["playlistId": playlistId], position: "INSERT_AFTER_CURRENT_VIDEO") }
    func playLast(playlistId: String) { addToQueue(target: ["playlistId": playlistId], position: "INSERT_AT_END") }
    func shuffleQueue() { run("document.querySelector('ytmusic-player-bar .shuffle')?.click()") }
    func cycleRepeat() { run("document.querySelector('ytmusic-player-bar .repeat')?.click()") }

    func setAutoplay(_ on: Bool) {
        autoplay = on
        run("(function(){ const t = document.querySelector('#automix'); if (t && t.checked !== \(on)) t.click(); })()")
    }

    /// With nothing playing there is no queue row to borrow a menu from, so just start it.
    private func addToQueue(target: [String: String], position: String) {
        guard !queue.isEmpty else {
            if let videoId = target["videoId"] { play(videoId: videoId, playlistId: nil) }
            if let playlistId = target["playlistId"] { play(playlistId: playlistId) }
            return
        }
        guard let json = try? JSONSerialization.data(withJSONObject: target), let target = String(data: json, encoding: .utf8) else { return }
        run("window.__atQueue?.add(\(target), '\(position)')")
    }

    func applyQueue(_ body: [String: Any]) {
        let rows = body["queue"] as? [[String: Any]] ?? []
        queue = rows.enumerated().map { index, row in
            let videoId = row["vid"] as? String ?? ""
            return QueueItem(
                id: "\(index)-\(videoId)",
                videoId: videoId,
                title: row["title"] as? String ?? "",
                artist: row["artist"] as? String ?? "",
                artworkURL: (row["art"] as? String).flatMap(URL.init(string:)),
                duration: row["len"] as? String
            )
        }
        queueIndex = rows.firstIndex { $0["sel"] as? Bool == true }
        let repeatTitle = (body["repeat"] as? String ?? "").lowercased()
        repeatMode = repeatTitle.contains("one") ? .one : repeatTitle.contains("all") ? .all : .off
        if let on = body["autoplay"] as? Bool { autoplay = on }
    }

    /// Posts the queue whenever it changes and exposes the row actions used above.
    static let queueScript = """
    (function() {
        if (window.__atQueue) return;
        const sleep = ms => new Promise(r => setTimeout(r, ms));
        const rows = () => Array.from(document.querySelectorAll('ytmusic-player-queue-item'));
        const text = t => t && t.runs ? t.runs.map(r => r.text).join('') : '';

        async function clickMenuEntry(row, key, position, newTarget) {
            const button = row && row.querySelector('ytmusic-menu-renderer #button, ytmusic-menu-renderer button, ytmusic-menu-renderer tp-yt-paper-icon-button');
            if (!button) return false;
            button.click();
            let entry = null;
            for (let i = 0; i < 30 && !entry; i++) {
                await sleep(100);
                entry = Array.from(document.querySelectorAll('ytmusic-menu-popup-renderer ytmusic-menu-service-item-renderer'))
                    .find(e => {
                        const ep = e.data && e.data.serviceEndpoint && e.data.serviceEndpoint[key];
                        return ep && e.offsetParent !== null && (!position || ep.queueInsertPosition === position);
                    });
            }
            if (!entry) { document.body.click(); return false; }
            let restore = null;
            if (newTarget) {
                // Swap the menu item's target for ours ({videoId} or {playlistId}) just for this click.
                const endpoint = entry.data.serviceEndpoint.queueAddEndpoint;
                const original = endpoint.queueTarget;
                endpoint.queueTarget = newTarget;
                restore = () => { endpoint.queueTarget = original; };
            }
            entry.click();
            if (restore) setTimeout(restore, 0);
            return true;
        }

        window.__atQueue = {
            jump: i => rows()[i]?.querySelector('ytmusic-play-button-renderer')?.click(),
            remove: i => clickMenuEntry(rows()[i], 'removeFromQueueEndpoint'),
            add: (target, position) => {
                const list = rows();
                const row = list.find(r => r.data && r.data.selected) || list[0];
                return clickMenuEntry(row, 'queueAddEndpoint', position, target);
            }
        };

        let last = '';
        setInterval(function() {
            const list = rows().map(r => {
                const d = r.data || {};
                const thumbs = d.thumbnail && d.thumbnail.thumbnails || [];
                return { vid: d.videoId || '', title: text(d.title), artist: text(d.shortBylineText),
                         art: thumbs.length ? thumbs[0].url : '', len: text(d.lengthText), sel: !!d.selected };
            });
            const repeat = document.querySelector('ytmusic-player-bar .repeat')?.getAttribute('title') || '';
            const toggle = document.querySelector('#automix');
            const state = { queue: list, repeat: repeat, autoplay: toggle ? !!toggle.checked : null };
            const key = JSON.stringify(state);
            if (key !== last) { last = key; window.webkit.messageHandlers.player.postMessage(state); }
        }, 1000);
    })();
    """
}
