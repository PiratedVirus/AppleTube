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
    private let cache = ResponseCache()
    private var apiKey: String? = UserDefaults.standard.string(forKey: "innertubeAPIKey")
    private var prefetching = Set<String>()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// How long a cached response counts as fresh. Mutations invalidate the affected pages explicitly.
    enum TTL {
        static let home: TimeInterval = 15 * 60
        static let explore: TimeInterval = 30 * 60
        static let page: TimeInterval = 30 * 60      // albums, playlists, artists
        static let library: TimeInterval = 5 * 60
        static let search: TimeInterval = 10 * 60
    }

    /// Where a request may be answered from.
    enum Source {
        case fresh          // cache within its TTL, else network
        case staleOnly      // whatever is cached, any age; nil/throws if nothing (for instant first paint)
    }

    // MARK: - Endpoints

    /// First page of Home plus the token for the rest (YouTube sends only a couple of shelves up front).
    func home(_ source: Source = .fresh) async throws -> (response: HomeResponse, continuation: String?) {
        try await load("browse", ["browseId": "FEmusic_home"], ttl: TTL.home, source: source) {
            (HomeResponseParser.parse($0), HomeResponseParser.extractContinuationToken(from: $0))
        }
    }

    func homeContinuation(_ token: String) async throws -> (sections: [HomeSection], continuation: String?) {
        try await load("browse", ["continuation": token]) {
            (HomeResponseParser.parseContinuation($0), HomeResponseParser.extractContinuationTokenFromContinuation($0))
        }
    }

    /// YouTube Music's Explore page (new releases, charts, moods); its shelves parse like Home's.
    func explore(_ source: Source = .fresh) async throws -> [HomeSection] {
        try await load("browse", ["browseId": "FEmusic_explore"], ttl: TTL.explore, source: source) { HomeResponseParser.parse($0).sections }
    }

    func search(_ query: String) async throws -> SearchResponse {
        try await load("search", ["query": query], ttl: TTL.search) { SearchResponseParser.parse($0) }
    }

    func searchSuggestions(_ query: String) async throws -> [SearchSuggestion] {
        guard !query.isEmpty else { return [] }
        return try await load("music/get_search_suggestions", ["input": query], ttl: TTL.search) { SearchSuggestionsParser.parse($0) }
    }

    /// Albums (`MPREb_…`) and playlists both load through browse; plain playlist IDs need the `VL` prefix.
    /// `playbackListId` is what the web player queues: an album's `OLAK5uy_…` list, or the bare playlist ID.
    func playlist(id: String, _ source: Source = .fresh) async throws -> PlaylistPage {
        try await load("browse", ["browseId": Self.browseId(forPlaylist: id)], ttl: TTL.page, source: source) { data in
            let listId = id.hasPrefix("MPRE") ? Self.albumPlaybackListId(in: data) : Self.bareId(id)
            let header = Self.anyHeader(in: data)
            return PlaylistPage(response: PlaylistParser.parsePlaylistWithContinuation(data, playlistId: id), playbackListId: listId,
                                headerTitle: header.title, headerArtworkURL: header.artwork)
        }
    }

    nonisolated static func browseId(forPlaylist id: String) -> String {
        let loadsAsIs = id.hasPrefix("VL") || id.hasPrefix("RD") || id.hasPrefix("MPRE") || id.hasPrefix("UC")
        return loadsAsIs ? id : "VL\(id)"
    }

    /// Playlist ID without the browse-only `VL` prefix (what edit/like endpoints and the player want).
    nonisolated static func bareId(_ id: String) -> String { id.hasPrefix("VL") ? String(id.dropFirst(2)) : id }

    struct PlaylistPage: @unchecked Sendable {
        let response: PlaylistTracksResponse
        let playbackListId: String?
        /// From any `…HeaderRenderer` in the response, for header formats the parser doesn't know.
        let headerTitle: String?
        let headerArtworkURL: URL?
    }

    /// Title and largest artwork of the first `…HeaderRenderer` anywhere in a browse response.
    nonisolated static func anyHeader(in data: [String: Any]) -> (title: String?, artwork: URL?) {
        func find(_ node: Any) -> [String: Any]? {
            if let dict = node as? [String: Any] {
                for (key, value) in dict where key.hasSuffix("HeaderRenderer") {
                    if let renderer = value as? [String: Any], renderer["title"] != nil { return renderer }
                }
                for value in dict.values { if let hit = find(value) { return hit } }
            } else if let array = node as? [Any] {
                for value in array { if let hit = find(value) { return hit } }
            }
            return nil
        }
        func thumbnail(_ node: Any) -> URL? {
            if let dict = node as? [String: Any] {
                if let thumbs = dict["thumbnails"] as? [[String: Any]], let url = thumbs.last?["url"] as? String {
                    return URL(string: url)
                }
                for value in dict.values { if let hit = thumbnail(value) { return hit } }
            } else if let array = node as? [Any] {
                for value in array { if let hit = thumbnail(value) { return hit } }
            }
            return nil
        }
        guard let header = find(data) else { return (nil, nil) }
        let runs = (header["title"] as? [String: Any])?["runs"] as? [[String: Any]]
        let title = runs?.compactMap { $0["text"] as? String }.joined()
        return (title?.isEmpty == false ? title : nil, thumbnail(header))
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

    func artist(id: String, _ source: Source = .fresh) async throws -> ArtistDetail {
        try await load("browse", ["browseId": id], ttl: TTL.page, source: source) { ArtistParser.parseArtistDetail($0, artistId: id) }
    }

    func libraryLanding(_ source: Source = .fresh) async throws -> PlaylistParser.LibraryContent {
        try await load("browse", ["browseId": "FEmusic_library_landing"], requiresAuth: true, ttl: TTL.library, source: source) {
            PlaylistParser.parseLibraryContent($0)
        }
    }

    func libraryPlaylists(_ source: Source = .fresh) async throws -> [Playlist] {
        try await load("browse", ["browseId": "FEmusic_liked_playlists"], requiresAuth: true, ttl: TTL.library, source: source) {
            PlaylistParser.parseLibraryPlaylists($0)
        }
    }

    /// Your own playlists (the ones you can add songs to), for "Add to Playlist".
    func editablePlaylists() async -> [Playlist] {
        let all = (try? await libraryPlaylists()) ?? []
        return all.filter { $0.canDelete && $0.id != LikedMusicPlaylist.id }
    }

    /// Up Next for a song: the radio mix YouTube Music builds from it.
    func radioQueue(videoId: String) async throws -> RadioQueueResult {
        try await load("next", Self.nextBody(videoId: videoId, playlistId: "RDAMVM\(videoId)")) { RadioQueueParser.parse(from: $0) }
    }

    /// YouTube Music's own lyrics for a track: timed if it has them, else plain. See LyricsFinder for fallbacks.
    func youTubeLyrics(videoId: String) async -> LyricResult {
        let next = try? await load("next", Self.nextBody(videoId: videoId, playlistId: nil)) { data in
            (synced: LyricsParser.extractTimedLyrics(from: data), browseId: LyricsParser.extractLyricsBrowseId(from: data))
        }
        if let synced = next?.synced, !synced.isEmpty { return .synced(synced) }
        if let browseId = next?.browseId,
           let plain = try? await load("browse", ["browseId": browseId], ttl: TTL.page, parse: { LyricsParser.parse(from: $0) }),
           plain.isAvailable {
            return .plain(plain)
        }
        return .unavailable
    }

    /// Full song info (artist and album IDs) for the playing track, from its Up Next panel.
    func songDetails(videoId: String) async -> Song? {
        try? await load("next", Self.nextBody(videoId: videoId, playlistId: nil)) { data in
            RadioQueueParser.parse(from: data).songs.first { $0.videoId == videoId }
        }
    }

    struct AccountInfo: Codable, Equatable {
        let name: String
        let photoURL: URL?
    }

    /// Your Google account's name and profile photo (the selected account in YouTube's account switcher).
    func account() async -> AccountInfo? {
        try? await load("account/accounts_list", [:], requiresAuth: true, ttl: TTL.library) { data in
            var accounts: [[String: Any]] = []
            func walk(_ node: Any) {
                if let dict = node as? [String: Any] {
                    if dict["accountName"] != nil, dict["accountPhoto"] != nil { accounts.append(dict) }
                    dict.values.forEach(walk)
                } else if let array = node as? [Any] {
                    array.forEach(walk)
                }
            }
            walk(data)
            guard let account = accounts.first(where: { $0["isSelected"] as? Bool == true }) ?? accounts.first else { return nil }
            let runs = (account["accountName"] as? [String: Any])?["runs"] as? [[String: Any]]
            let name = runs?.compactMap { $0["text"] as? String }.joined() ?? (account["accountName"] as? [String: Any])?["simpleText"] as? String ?? ""
            let thumbs = (account["accountPhoto"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            return AccountInfo(name: name, photoURL: (thumbs?.last?["url"] as? String).flatMap(URL.init(string:)))
        } ?? nil
    }

    // MARK: - Library edits (request shapes from Kaset's YTMusicClient)

    func setLiked(videoId: String, _ liked: Bool) async throws {
        _ = try await send(liked ? "like/like" : "like/removelike", ["target": ["videoId": videoId]])
        invalidate(playlist: LikedMusicPlaylist.id)
    }

    func setDisliked(videoId: String) async throws {
        _ = try await send("like/dislike", ["target": ["videoId": videoId]])
    }

    /// Adds or removes a song from your library using the tokens YouTube attaches to each song.
    func setInLibrary(_ song: Song, _ add: Bool) async throws {
        guard let token = song.feedbackTokens?.token(forAdding: add) else { return }
        _ = try await send("feedback", ["feedbackTokens": [token]])
        invalidateLibrary()
    }

    /// Saves an album or someone else's playlist to your library (YouTube calls this liking the playlist).
    func setSaved(playlistId: String, _ saved: Bool) async throws {
        _ = try await send(saved ? "like/like" : "like/removelike", ["target": ["playlistId": Self.bareId(playlistId)]])
        invalidateLibrary()
    }

    func addToPlaylist(videoIds: [String], playlistId: String) async throws {
        let actions = videoIds.map { ["action": "ACTION_ADD_VIDEO", "addedVideoId": $0] }
        _ = try await send("browse/edit_playlist", ["playlistId": Self.bareId(playlistId), "actions": actions])
        invalidate(playlist: playlistId)
    }

    /// `setVideoId` identifies the entry in the playlist (`Song.playlistSetVideoId`).
    func removeFromPlaylist(videoId: String, setVideoId: String, playlistId: String) async throws {
        let action = ["action": "ACTION_REMOVE_VIDEO", "removedVideoId": videoId, "setVideoId": setVideoId]
        _ = try await send("browse/edit_playlist", ["playlistId": Self.bareId(playlistId), "actions": [action]])
        invalidate(playlist: playlistId)
    }

    /// Creates a private playlist, optionally with songs, and returns its ID.
    func createPlaylist(title: String, videoIds: [String] = []) async throws -> String {
        var body: [String: Any] = ["title": title, "privacyStatus": "PRIVATE"]
        if !videoIds.isEmpty { body["videoIds"] = videoIds }
        let response = try await send("playlist/create", body)
        guard let id = response["playlistId"] as? String else {
            throw YTMusicError.parseError(message: "No playlist ID in create response")
        }
        invalidateLibrary()
        return id
    }

    func deletePlaylist(id: String) async throws {
        _ = try await send("playlist/delete", ["playlistId": Self.bareId(id)])
        invalidateLibrary()
        invalidate(playlist: id)
    }

    private func invalidateLibrary() {
        for browseId in ["FEmusic_library_landing", "FEmusic_liked_playlists"] {
            cache.remove(key: cacheKey("browse", ["browseId": browseId]))
        }
    }

    private func invalidate(playlist id: String) {
        cache.remove(key: cacheKey("browse", ["browseId": Self.browseId(forPlaylist: id)]))
        invalidateLibrary()
    }

    func clearCache() { cache.removeAll() }

    // MARK: - Prefetch

    /// Warms the cache for a page the user is likely to open (cards on screen), a few at a time.
    func prefetch(_ route: Route) {
        let key: String
        switch route {
        case let .playlist(id, _, _): key = cacheKey("browse", ["browseId": Self.browseId(forPlaylist: id)])
        case let .artist(id, _): key = cacheKey("browse", ["browseId": id])
        }
        guard prefetching.count < 3, !prefetching.contains(key), cache.get(key: key, maxAge: TTL.page) == nil else { return }
        prefetching.insert(key)
        Task(priority: .utility) {
            defer { prefetching.remove(key) }
            switch route {
            case let .playlist(id, _, _): _ = try? await playlist(id: id)
            case let .artist(id, _): _ = try? await artist(id: id)
            }
        }
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

    /// Fetches (or reuses a cached copy of) a response and parses it on a background thread, so big responses
    /// don't stall scrolling. `ttl` nil means never cache.
    func load<T>(_ endpoint: String, _ body: [String: Any], requiresAuth: Bool = false, ttl: TimeInterval? = nil,
                 source: Source = .fresh, parse: @escaping @Sendable ([String: Any]) throws -> T) async throws -> T {
        let key = cacheKey(endpoint, body)
        let data: Data
        if source == .staleOnly {
            guard let cached = cache.get(key: key, maxAge: .infinity) else { throw CancellationError() }
            data = cached
        } else if let ttl, let cached = cache.get(key: key, maxAge: ttl) {
            data = cached
        } else {
            data = try await fetch(endpoint, body: body, requiresAuth: requiresAuth)
            if ttl != nil { cache.put(data, key: key) }
        }
        let box = try await Task.detached(priority: .userInitiated) {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw YTMusicError.parseError(message: "\(endpoint) returned non-JSON")
            }
            return UncheckedBox(try parse(json))
        }.value
        return box.value
    }

    /// Mutations: no cache, parsed on the main actor (responses are small).
    private func send(_ endpoint: String, _ body: [String: Any]) async throws -> [String: Any] {
        let data = try await fetch(endpoint, body: body, requiresAuth: true)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Signed-in and signed-out answers differ, so the account state is part of the key.
    private func cacheKey(_ endpoint: String, _ body: [String: Any]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return "\(AppState.shared.signedIn == true ? "user" : "guest")|\(endpoint)|\(json)"
    }

    /// Signed in → cookie + SAPISIDHASH headers. Signed out → a plain guest request, unless the endpoint needs an account.
    private func fetch(_ endpoint: String, body: [String: Any], requiresAuth: Bool, retried: Bool = false) async throws -> Data {
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
            // A saved API key can go stale when YouTube rotates it: fetch a fresh one and retry once.
            if http.statusCode == 400 || http.statusCode == 403, !retried, apiKey != nil {
                apiKey = nil
                UserDefaults.standard.removeObject(forKey: "innertubeAPIKey")
                return try await fetch(endpoint, body: body, requiresAuth: requiresAuth, retried: true)
            }
            if http.statusCode == 401 || http.statusCode == 403 { throw YTMusicError.authExpired }
            throw YTMusicError.apiError(message: "\(endpoint) failed", code: http.statusCode)
        }
        return data
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

    /// The API key is embedded in the music.youtube.com page; fetched once and remembered across launches.
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
        UserDefaults.standard.set(key, forKey: "innertubeAPIKey")
        return key
    }

    nonisolated static func extractAPIKey(from html: String) -> String? {
        guard let match = html.firstMatch(of: /"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"/) else { return nil }
        return String(match.1)
    }
}

/// Carries a parsed (non-Sendable) value out of the background parsing task; it's handed over exactly once.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
