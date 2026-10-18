import CryptoKit
import Foundation
import WebKit

/// YouTube Music's internal "InnerTube" API, signed with the session cookies from `WebSession`.
/// Request shape follows Kaset's YTMusicClient; responses go to Kaset's parsers in `YTMusic/Kaset`.
@MainActor
final class YTMusicAPI {
    static let shared = YTMusicAPI()

    private static let baseURL = "https://music.youtube.com/youtubei/v1"
    private static let clientVersion = "1.20231204.01.00"

    private let session: URLSession
    private var apiKey: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Endpoints

    /// First page of Home plus the token for the rest (YouTube sends only a couple of shelves up front).
    func home() async throws -> (response: HomeResponse, continuation: String?) {
        let data = try await request("browse", body: ["browseId": "FEmusic_home"])
        return (HomeResponseParser.parse(data), HomeResponseParser.extractContinuationToken(from: data))
    }

    func homeContinuation(_ token: String) async throws -> (sections: [HomeSection], continuation: String?) {
        let data = try await request("browse", body: ["continuation": token])
        return (HomeResponseParser.parseContinuation(data), HomeResponseParser.extractContinuationTokenFromContinuation(data))
    }

    /// YouTube Music's Explore page (new releases, charts, moods); its shelves parse like Home's.
    func explore() async throws -> [HomeSection] {
        HomeResponseParser.parse(try await request("browse", body: ["browseId": "FEmusic_explore"])).sections
    }

    func search(_ query: String) async throws -> SearchResponse {
        SearchResponseParser.parse(try await request("search", body: ["query": query]))
    }

    func searchSuggestions(_ query: String) async throws -> [SearchSuggestion] {
        guard !query.isEmpty else { return [] }
        return SearchSuggestionsParser.parse(try await request("music/get_search_suggestions", body: ["input": query]))
    }

    /// Albums (`MPREb_…`) and playlists both load through browse; plain playlist IDs need the `VL` prefix.
    /// `playbackListId` is what the web player queues: an album's `OLAK5uy_…` list, or the bare playlist ID.
    func playlist(id: String) async throws -> (response: PlaylistTracksResponse, playbackListId: String?) {
        let loadsAsIs = id.hasPrefix("VL") || id.hasPrefix("RD") || id.hasPrefix("MPRE") || id.hasPrefix("UC")
        let data = try await request("browse", body: ["browseId": loadsAsIs ? id : "VL\(id)"])
        let listId = id.hasPrefix("MPRE") ? Self.albumPlaybackListId(in: data) : (id.hasPrefix("VL") ? String(id.dropFirst(2)) : id)
        return (PlaylistParser.parsePlaylistWithContinuation(data, playlistId: id), listId)
    }

    /// Every track row on an album page plays with the album's `OLAK5uy_…` list; pick the most common one in
    /// the track list (other shelves on the page carry radio and related-album lists).
    nonisolated static func albumPlaybackListId(in data: [String: Any]) -> String? {
        var node: Any? = data
        for key in ["contents", "twoColumnBrowseResultsRenderer", "secondaryContents", "sectionListRenderer", "contents"] {
            node = (node as? [String: Any])?[key]
        }
        let sections = node as? [[String: Any]]
        guard let trackList = sections?.first(where: { $0["musicShelfRenderer"] != nil }) else { return nil }
        var counts: [String: Int] = [:]
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let id = (dict["watchEndpoint"] as? [String: Any])?["playlistId"] as? String, id.hasPrefix("OLAK") {
                    counts[id, default: 0] += 1
                }
                dict.values.forEach(walk)
            } else if let array = node as? [Any] {
                array.forEach(walk)
            }
        }
        walk(trackList)
        return counts.max { $0.value < $1.value }?.key
    }

    func artist(id: String) async throws -> ArtistDetail {
        ArtistParser.parseArtistDetail(try await request("browse", body: ["browseId": id]), artistId: id)
    }

    func libraryLanding() async throws -> PlaylistParser.LibraryContent {
        PlaylistParser.parseLibraryContent(try await request("browse", body: ["browseId": "FEmusic_library_landing"], requiresAuth: true))
    }

    func libraryPlaylists() async throws -> [Playlist] {
        PlaylistParser.parseLibraryPlaylists(try await request("browse", body: ["browseId": "FEmusic_liked_playlists"], requiresAuth: true))
    }

    /// Up Next for a song: the radio mix YouTube Music builds from it.
    func radioQueue(videoId: String) async throws -> RadioQueueResult {
        RadioQueueParser.parse(from: try await request("next", body: Self.nextBody(videoId: videoId, playlistId: "RDAMVM\(videoId)")))
    }

    func lyrics(videoId: String) async throws -> Lyrics {
        let next = try await request("next", body: Self.nextBody(videoId: videoId, playlistId: nil))
        guard let browseId = LyricsParser.extractLyricsBrowseId(from: next) else { return .unavailable }
        return LyricsParser.parse(from: try await request("browse", body: ["browseId": browseId]))
    }

    /// Lyrics for the Apple Music-style view, best first: YouTube Music's own timed lyrics, then LRCLIB
    /// (a free community database, as Kaset uses) for timed lines, then plain text from either.
    func bestLyrics(videoId: String, title: String, artist: String, duration: Double) async -> LyricResult {
        let next = try? await request("next", body: Self.nextBody(videoId: videoId, playlistId: nil))
        if let next, let synced = LyricsParser.extractTimedLyrics(from: next), !synced.isEmpty {
            return .synced(synced)
        }
        let lrclib = await Self.lrclib(title: title, artist: artist, duration: duration)
        if case .synced = lrclib { return lrclib }
        if let next, let browseId = LyricsParser.extractLyricsBrowseId(from: next),
           let data = try? await request("browse", body: ["browseId": browseId]) {
            let plain = LyricsParser.parse(from: data)
            if plain.isAvailable { return .plain(plain) }
        }
        return lrclib
    }

    private struct LRCLibTrack: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static func lrclib(title: String, artist: String, duration: Double) async -> LyricResult {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        guard let url = components.url else { return .unavailable }
        var request = URLRequest(url: url)
        request.setValue("AppleTube/1.0 (personal)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let tracks = try? JSONDecoder().decode([LRCLibTrack].self, from: data)
        else { return .unavailable }
        // Closest duration wins; versions of a song often differ by intros and outros.
        let candidates = tracks.filter { $0.instrumental != true && ($0.syncedLyrics != nil || $0.plainLyrics != nil) }
        let best = candidates.min { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
        if let synced = best?.syncedLyrics, let parsed = LRCParser.parse(synced) {
            return .synced(SyncedLyrics(lines: parsed.lines, source: "LRCLIB"))
        }
        if let plain = best?.plainLyrics { return .plain(Lyrics(text: plain, source: "LRCLIB")) }
        return .unavailable
    }

    /// Full song info (artist and album IDs) for the playing track, from its Up Next panel.
    func songDetails(videoId: String) async -> Song? {
        guard let data = try? await request("next", body: Self.nextBody(videoId: videoId, playlistId: nil)) else { return nil }
        return RadioQueueParser.parse(from: data).songs.first { $0.videoId == videoId }
    }

    private static func nextBody(videoId: String, playlistId: String?) -> [String: Any] {
        var body: [String: Any] = [
            "videoId": videoId,
            "enablePersistentPlaylistPanel": true,
            "isAudioOnly": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
        ]
        body["playlistId"] = playlistId
        return body
    }

    // MARK: - Transport

    /// Signed in → cookie + SAPISIDHASH headers. Signed out → a plain guest request, unless the endpoint needs an account.
    func request(_ endpoint: String, body: [String: Any], requiresAuth: Bool = false) async throws -> [String: Any] {
        let auth = await Self.authHeaders()
        if requiresAuth, auth == nil { throw YTMusicError.notAuthenticated }

        let key = try await resolveAPIKey()
        var components = URLComponents(string: "\(Self.baseURL)/\(endpoint)")!
        components.queryItems = [URLQueryItem(name: "key", value: key), URLQueryItem(name: "prettyPrint", value: "false")]

        var fullBody = body
        fullBody["context"] = Self.context()

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: fullBody)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(WebSession.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(WebSession.origin.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(WebSession.origin.absoluteString, forHTTPHeaderField: "Referer")
        for (field, value) in auth ?? ["Cookie": "SOCS=CAI"] {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw YTMusicError.networkError(underlying: error)
        }
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            if http.statusCode == 401 || http.statusCode == 403 { throw YTMusicError.authExpired }
            throw YTMusicError.apiError(message: "\(endpoint) failed", code: http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.parseError(message: "\(endpoint) returned non-JSON")
        }
        return json
    }

    private static func context() -> [String: Any] {
        [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": clientVersion,
                "hl": Locale.current.language.languageCode?.identifier ?? "en",
                "gl": Locale.current.region?.identifier ?? "US",
                "platform": "DESKTOP",
                "userAgent": WebSession.userAgent,
                "utcOffsetMinutes": TimeZone.current.secondsFromGMT() / 60,
            ],
            "user": ["lockedSafetyMode": false],
        ]
    }

    /// `Authorization: SAPISIDHASH <ts>_<sha1("<ts> <SAPISID> <origin>")>` plus every youtube.com cookie.
    private static func authHeaders() async -> [String: String]? {
        let cookies = await WebSession.dataStore.httpCookieStore.allCookies()
            .filter { $0.domain.hasSuffix("youtube.com") && ($0.expiresDate ?? .distantFuture) > .now }
        guard let sapisid = cookies.first(where: { $0.name == "SAPISID" })?.value
            ?? cookies.first(where: { $0.name == "__Secure-3PAPISID" })?.value
        else { return nil }

        let origin = WebSession.origin.absoluteString
        let timestamp = Int(Date().timeIntervalSince1970)
        let hash = Insecure.SHA1.hash(data: Data("\(timestamp) \(sapisid) \(origin)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return [
            "Cookie": cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
            "Authorization": "SAPISIDHASH \(timestamp)_\(hash)",
            "X-Goog-AuthUser": "0",
            "X-Origin": origin,
        ]
    }

    /// The API key is embedded in the music.youtube.com page; fetch it once per launch.
    private func resolveAPIKey() async throws -> String {
        if let apiKey { return apiKey }
        var request = URLRequest(url: WebSession.origin)
        request.setValue(WebSession.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8), let key = Self.extractAPIKey(from: html) else {
            throw YTMusicError.parseError(message: "Could not find the YouTube Music API key")
        }
        apiKey = key
        return key
    }

    nonisolated static func extractAPIKey(from html: String) -> String? {
        guard let match = html.firstMatch(of: /"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"/) else { return nil }
        return String(match.1)
    }
}
