import SwiftUI
import WebKit

/// Google sign-in for music.youtube.com. The user types their own credentials; we only watch for the SAPISID cookie.
struct LoginView: UIViewRepresentable {
    var onSignedIn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSignedIn: onSignedIn) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WebSession.makeConfiguration())
        webView.customUserAgent = WebSession.userAgent
        webView.navigationDelegate = context.coordinator
        let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F")!
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_: WKWebView, context _: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onSignedIn: () -> Void
        init(onSignedIn: @escaping () -> Void) { self.onSignedIn = onSignedIn }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            guard webView.url?.host == "music.youtube.com" else { return }
            Task { if await WebSession.isSignedIn() { onSignedIn() } }
        }
    }
}
