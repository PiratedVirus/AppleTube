import WebKit

/// Shared web session for login and playback. Cookies live in the default persistent store,
/// so signing in once in `LoginView` also signs in the hidden player.
@MainActor
enum WebSession {
    static let origin = URL(string: "https://music.youtube.com")!

    /// Desktop Safari UA so YouTube serves the full web player instead of the "open the app" page (same as Kaset).
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static let dataStore = WKWebsiteDataStore.default()

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        return config
    }

    /// Signed in when Google's SAPISID cookie (used for SAPISIDHASH request signing) is present and unexpired.
    static func isSignedIn() async -> Bool {
        let cookies = await dataStore.httpCookieStore.allCookies()
        return cookies.contains { cookie in
            (cookie.name == "SAPISID" || cookie.name == "__Secure-3PAPISID")
                && cookie.domain.hasSuffix("youtube.com")
                && (cookie.expiresDate ?? .distantFuture) > .now
        }
    }

    static func signOut() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
    }
}
