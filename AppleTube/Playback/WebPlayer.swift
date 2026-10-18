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
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var isAdShowing = false
    private(set) var status = "Idle"

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var lastLoggedSecond = -5
    @ObservationIgnored private let nowPlaying = NowPlaying()

    override init() {
        let config = WebSession.makeConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(source: Self.observerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 2, height: 2), configuration: config)
        super.init()
        config.userContentController.add(self, name: "player")
        webView.customUserAgent = WebSession.userAgent
        webView.navigationDelegate = self
        webView.isUserInteractionEnabled = false
        webView.alpha = 0.01
        nowPlaying.connect(to: self)
    }

    /// WebKit only plays media for web views that are in a window, so park it there invisibly.
    func attach(to window: UIWindow) {
        guard webView.superview !== window else { return }
        window.addSubview(webView)
        window.sendSubviewToBack(webView)
    }

    func load(videoId: String) {
        guard let url = URL(string: "https://music.youtube.com/watch?v=\(videoId)") else { return }
        setStatus("Loading \(videoId)…")
        webView.load(URLRequest(url: url))
    }

    func play() { run("document.querySelector('video')?.play()") }
    func pause() { run("document.querySelector('video')?.pause()") }
    func togglePlayPause() { isPlaying ? pause() : play() }

    func next() {
        run("(document.querySelector('ytmusic-player-bar .next-button') || {click(){ document.getElementById('movie_player')?.nextVideo?.() }}).click()")
    }

    func previous() {
        run("(document.querySelector('ytmusic-player-bar .previous-button') || {click(){ document.getElementById('movie_player')?.previousVideo?.() }}).click()")
    }

    func seek(to seconds: Double) {
        run("(function(){ const v = document.querySelector('video'); if (v) v.currentTime = \(seconds); })()")
    }

    private func setStatus(_ new: String) {
        guard new != status else { return }
        status = new
        print("[AppleTube] status: \(new)")
    }

    /// Fire-and-forget; `void` keeps WebKit from trying to bridge a returned Promise.
    private func run(_ script: String) {
        webView.evaluateJavaScript("void (\(script));") { [weak self] _, error in
            if let error { self?.setStatus("JS error: \(error.localizedDescription)") }
        }
    }

    private func apply(_ state: [String: Any]) {
        isPlaying = state["playing"] as? Bool ?? false
        position = state["t"] as? Double ?? 0
        duration = state["d"] as? Double ?? 0
        isAdShowing = state["ad"] as? Bool ?? false
        title = state["title"] as? String ?? ""
        artist = state["artist"] as? String ?? ""
        artworkURL = (state["art"] as? String).flatMap(URL.init(string:))
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
                ad: !!document.querySelector('#movie_player.ad-showing')
            };
            const key = JSON.stringify(s);
            if (key !== last) { last = key; window.webkit.messageHandlers.player.postMessage(s); }
        }, 500);
    })();
    """
}

extension WebPlayer: WKScriptMessageHandler {
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let state = message.body as? [String: Any] else { return }
        apply(state)
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
