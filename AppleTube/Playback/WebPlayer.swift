import UIKit
import WebKit

/// Plays YouTube Music through a hidden music.youtube.com web view, Kaset-style.
/// The web player handles Premium, streams and YouTube's protections; we only drive it with JavaScript.
@MainActor
@Observable
final class WebPlayer: NSObject {
    static let shared = WebPlayer()

    private(set) var title = ""
    private(set) var artist = ""
    private(set) var artworkURL: URL?
    /// YouTube video ID of the current track, read from the page URL (`watch?v=`).
    private(set) var videoId: String?
    /// Playlist/album the web player is working through (`list=`), if any.
    private(set) var playlistId: String?
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    @ObservationIgnored private(set) var positionUpdatedAt = Date.now
    private(set) var duration: Double = 0
    private(set) var isAdShowing = false
    private(set) var status = "Idle"
    /// YouTube Music's own queue (read from the page), the current song's place in it, and its modes.
    var queue: [QueueItem] = []
    var queueIndex: Int?
    var repeatMode: RepeatMode = .off
    var autoplay = true

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var lastLoggedSecond = -5
    @ObservationIgnored private let nowPlaying = NowPlaying()
    @ObservationIgnored private var wasPlayingWhenResigned = false

    override init() {
        let config = WebSession.makeConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(source: Self.alwaysVisibleScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        config.userContentController.addUserScript(
            WKUserScript(source: Self.lockScreenControlsScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        config.userContentController.addUserScript(
            WKUserScript(source: Self.observerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        config.userContentController.addUserScript(
            WKUserScript(source: Self.queueScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 2, height: 2), configuration: config)
        super.init()
        config.userContentController.add(self, name: "player")
        webView.customUserAgent = WebSession.userAgent
        webView.navigationDelegate = self
        webView.isUserInteractionEnabled = false
        webView.alpha = 0.01
        // The hidden page must not show up to VoiceOver (or UI tests) as hundreds of web elements.
        webView.accessibilityElementsHidden = true
        webView.isAccessibilityElement = false
        nowPlaying.connect(to: self)
        observeAppLifecycle()
    }

    /// Locking the phone pauses the web player, but a play command while locked works. So remember whether we
    /// were playing as the app resigns active and push play a few times once it's in the background.
    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wasPlayingWhenResigned = self?.isPlaying ?? false }
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeAfterBackgrounding() }
        }
    }

    private func resumeAfterBackgrounding() {
        guard wasPlayingWhenResigned else { return }
        print("[AppleTube] backgrounded while playing; keeping playback alive")
        Task {
            for delay in [0.3, 1.0, 2.5, 5.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard wasPlayingWhenResigned else { return }
                play()
            }
            wasPlayingWhenResigned = false
        }
    }

    /// WebKit only plays media for web views that are in a window, so park it there invisibly.
    /// Also boots music.youtube.com once so later tracks can start without a page load.
    func attach(to window: UIWindow) {
        guard webView.superview !== window else { return }
        window.addSubview(webView)
        window.sendSubviewToBack(webView)
        if webView.url == nil { webView.load(URLRequest(url: WebSession.origin)) }
    }

    func load(videoId: String) {
        play(videoId: videoId, playlistId: nil)
    }

    /// Plays a track. With a playlist/album ID the web player queues the rest of it, so next/previous follow
    /// that list; without one, YouTube Music builds a radio queue from the track.
    func play(videoId: String, playlistId: String?) {
        var endpoint: [String: Any] = ["videoId": videoId]
        endpoint["playlistId"] = playlistId
        start(endpoint)
    }

    /// Plays a mix/station by its playlist ID; the web player picks the first track.
    func play(playlistId: String) {
        start(["playlistId": playlistId])
    }

    /// `playbackListId` comes from `YTMusicAPI.playlist(id:)`; nil starts a radio from the song.
    func play(_ song: Song, playbackListId: String? = nil) {
        play(videoId: song.videoId, playlistId: playbackListId)
    }

    /// Starts a watch endpoint. If the YouTube Music web app is already running, hand it the endpoint
    /// (`ytmusic-app.resolveCommand`, as Kaset does) so it switches track in place, which takes about a second.
    /// Otherwise fall back to loading the watch page.
    private func start(_ endpoint: [String: Any]) {
        setStatus("Loading…")
        isPlaying = false
        Task {
            let routed = try? await webView.callAsyncJavaScript("""
                const app = document.querySelector('ytmusic-app');
                if (!app || typeof app.resolveCommand !== 'function') return false;
                app.resolveCommand({ watchEndpoint: endpoint });
                return true;
                """, arguments: ["endpoint": endpoint], contentWorld: .page)
            if (routed as? Bool) == true { return }
            var components = URLComponents(string: "https://music.youtube.com/watch")!
            components.queryItems = endpoint.compactMap { key, value in
                (value as? String).map { URLQueryItem(name: key == "videoId" ? "v" : "list", value: $0) }
            }
            if let url = components.url { webView.load(URLRequest(url: url)) }
        }
    }

    /// Playback position now, extrapolated between the page's twice-a-second updates (for smooth lyrics).
    func currentPosition(at date: Date = .now) -> Double {
        guard isPlaying else { return position }
        return min(position + date.timeIntervalSince(positionUpdatedAt), max(duration, position))
    }

    func play() { run("document.querySelector('video')?.play()") }
    func pause() {
        wasPlayingWhenResigned = false
        run("document.querySelector('video')?.pause()")
    }
    func togglePlayPause() { isPlaying ? pause() : play() }

    func next() {
        run("(document.querySelector('ytmusic-player-bar .next-button') || {click(){ document.getElementById('movie_player')?.nextVideo?.() }}).click()")
    }

    func previous() {
        run("(document.querySelector('ytmusic-player-bar .previous-button') || {click(){ document.getElementById('movie_player')?.previousVideo?.() }}).click()")
    }

    func seek(to seconds: Double) {
        position = seconds
        positionUpdatedAt = .now
        run("(function(){ const v = document.querySelector('video'); if (v) v.currentTime = \(seconds); })()")
    }

    func setStatus(_ new: String) {
        guard new != status else { return }
        status = new
        print("[AppleTube] status: \(new)")
    }

    /// Fire-and-forget (also used by the queue extension); `void` keeps WebKit from trying to bridge a returned Promise.
    func run(_ script: String) {
        webView.evaluateJavaScript("void (\(script));") { [weak self] _, error in
            if let error { self?.setStatus("JS error: \(error.localizedDescription)") }
        }
    }

    private func apply(_ state: [String: Any]) {
        isPlaying = state["playing"] as? Bool ?? false
        position = state["t"] as? Double ?? 0
        positionUpdatedAt = .now
        duration = state["d"] as? Double ?? 0
        isAdShowing = state["ad"] as? Bool ?? false
        title = state["title"] as? String ?? ""
        artist = state["artist"] as? String ?? ""
        artworkURL = (state["art"] as? String).flatMap(URL.init(string:))
        videoId = (state["vid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        playlistId = (state["list"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if isPlaying, !isAdShowing, let videoId {
            PlaybackHistory.shared.record(videoId: videoId, title: title, artist: artist, artworkURL: artworkURL)
        }
        setStatus(isAdShowing ? "Ad playing" : (isPlaying ? "Playing" : "Paused"))
        let second = Int(position)
        if second / 5 != lastLoggedSecond / 5 {
            lastLoggedSecond = second
            print("[AppleTube] position \(second)s playing=\(isPlaying) title=\(title)")
        }
        nowPlaying.update(from: self)
    }

    /// Polls the page twice a second and posts player state to Swift. Title/artist/artwork come from
    /// `navigator.mediaSession.metadata`, which the YouTube Music web app sets for every track.
    private static let observerScript = """
    (function() {
        if (window.__appleTubeObserver) return;
        window.__appleTubeObserver = true;
        let last = '';
        setInterval(function() {
            const v = document.querySelector('video');
            const md = navigator.mediaSession && navigator.mediaSession.metadata;
            const art = md && md.artwork && md.artwork.length ? md.artwork[md.artwork.length - 1].src : '';
            const s = {
                playing: !!v && !v.paused && !v.ended,
                t: v ? (v.currentTime || 0) : 0,
                d: v && isFinite(v.duration) ? v.duration : 0,
                title: md ? (md.title || '') : '',
                artist: md ? (md.artist || '') : '',
                art: art,
                vid: new URLSearchParams(location.search).get('v') || '',
                list: new URLSearchParams(location.search).get('list') || '',
                ad: !!document.querySelector('#movie_player.ad-showing')
            };
            const key = JSON.stringify(s);
            if (key !== last) { last = key; window.webkit.messageHandlers.player.postMessage(s); }
        }, 500);
    })();
    """

    /// Keeps the page believing it's on screen so it doesn't pause itself when the phone locks.
    private static let alwaysVisibleScript = """
    (function() {
        try {
            Object.defineProperty(document, 'hidden', { get: () => false, configurable: true });
            Object.defineProperty(document, 'webkitHidden', { get: () => false, configurable: true });
            Object.defineProperty(document, 'visibilityState', { get: () => 'visible', configurable: true });
            Object.defineProperty(document, 'webkitVisibilityState', { get: () => 'visible', configurable: true });
        } catch (e) {}
        const swallow = e => e.stopImmediatePropagation();
        document.addEventListener('visibilitychange', swallow, true);
        document.addEventListener('webkitvisibilitychange', swallow, true);
        window.addEventListener('pagehide', swallow, true);
        window.addEventListener('blur', swallow, true);
    })();
    """

    /// WebKit builds the Lock Screen controls from the page's Media Session handlers; with no next/previous
    /// handlers it shows ±10s skip buttons. Runs at document start so ours are in place before the first track,
    /// and wraps `setActionHandler` so the YouTube Music web app can't swap them back to seeking later.
    private static let lockScreenControlsScript = """
    (function() {
        const ms = navigator.mediaSession;
        if (!ms || ms.__appleTubeControls) return;
        ms.__appleTubeControls = true;
        const video = () => document.querySelector('video');
        const click = sel => document.querySelector(sel)?.click();
        const post = cmd => window.webkit.messageHandlers.player.postMessage({ cmd: cmd });
        const ours = {
            play: () => { video()?.play(); post('play'); },
            pause: () => { video()?.pause(); post('pause'); },
            nexttrack: () => click('ytmusic-player-bar .next-button'),
            previoustrack: () => click('ytmusic-player-bar .previous-button'),
            seekto: d => { const v = video(); if (v && d.seekTime != null) v.currentTime = d.seekTime; },
            seekforward: null,
            seekbackward: null
        };
        const original = ms.setActionHandler.bind(ms);
        ms.setActionHandler = function(action, handler) {
            try { return original(action, action in ours ? ours[action] : handler); } catch (e) {}
        };
        for (const action in ours) ms.setActionHandler(action, ours[action]);
    })();
    """
}

extension WebPlayer: WKScriptMessageHandler {
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if body["queue"] != nil {
            applyQueue(body)
            return
        }
        if let command = body["cmd"] as? String {
            // A pause from the Lock Screen is deliberate, so stop the auto-resume after locking.
            if command == "pause" { wasPlayingWhenResigned = false }
            print("[AppleTube] lock screen command: \(command)")
            return
        }
        apply(body)
    }
}

extension WebPlayer: WKNavigationDelegate {
    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        setStatus("Page loaded, waiting for audio…")
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        setStatus("Load failed: \(error.localizedDescription)")
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        setStatus("Load failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        setStatus("Web process crashed, reloading")
        webView.reload()
    }
}
