import Foundation

/// Finds lyrics for the playing track, best first. YouTube Music has timed lyrics for many official songs, but
/// music videos and uploads ("भ्रम और कर्म | Ek Taraf Bhram | …", "Artist - Song (Official Video)") usually have
/// none, so we also try LRCLIB (a free community lyrics database) with cleaned-up titles, then the official
/// audio version of the song on YouTube Music.
@MainActor
enum LyricsFinder {
    private static var cache: [String: LyricResult] = [:]

    static func find(videoId: String, title: String, artist: String, duration: Double) async -> LyricResult {
        if let cached = cache[videoId] { return cached }
        let result = await search(videoId: videoId, title: title, artist: artist, duration: duration)
        // Only remember hits: a miss may just be LRCLIB being briefly overloaded.
        if result.isAvailable { cache[videoId] = result }
        return result
    }

    private static func search(videoId: String, title: String, artist: String, duration: Double) async -> LyricResult {
        let api = YTMusicAPI.shared
        var plain: LyricResult?
        func keepPlain(_ result: LyricResult) { if plain == nil, case .plain = result { plain = result } }

        // 1. YouTube Music's own lyrics for this exact track.
        let own = await api.youTubeLyrics(videoId: videoId)
        if case .synced = own { return own }
        keepPlain(own)

        // 2–3. LRCLIB: exact match, then searches with each cleaned-up reading of the title.
        let queries = LyricsQuery.candidates(title: title, artist: artist)
        if let first = queries.first {
            let exact = await LRCLib.get(title: first.title, artist: first.artist, duration: duration)
            if case .synced = exact { return exact }
            keepPlain(exact)
        }
        for query in queries.prefix(4) {
            let found = await LRCLib.search(title: query.title, artist: query.artist, duration: duration)
            if case .synced = found { return found }
            keepPlain(found)
        }
        if let first = queries.first {
            let loose = await LRCLib.search(freeText: "\(first.title) \(first.artist)", duration: duration)
            if case .synced = loose { return loose }
            keepPlain(loose)
        }

        // 4. The official audio version on YouTube Music often has lyrics when the video doesn't.
        if let first = queries.first,
           let song = try? await api.search("\(first.title) \(first.artist)").songs
               .first(where: { $0.videoId != videoId && LyricsQuery.looselyMatches($0.title, first.title) }) {
            let audio = await api.youTubeLyrics(videoId: song.videoId)
            if case .synced = audio { return audio }
            keepPlain(audio)
        }

        return plain ?? .unavailable
    }
}

/// Readings of a messy YouTube title/artist to try against lyrics databases.
enum LyricsQuery {
    struct Candidate: Equatable {
        let title: String
        let artist: String
    }

    static func candidates(title rawTitle: String, artist rawArtist: String) -> [Candidate] {
        let artist = cleanArtist(rawArtist)
        let title = cleanTitle(rawTitle)
        var out: [Candidate] = [Candidate(title: title, artist: artist)]

        // "Artist - Song" (common for videos): try both halves the right way round.
        for separator in [" - ", " – ", " — "] where title.contains(separator) {
            let parts = title.components(separatedBy: separator).map(trim).filter { !$0.isEmpty }
            if parts.count >= 2 {
                out.append(Candidate(title: parts[1], artist: cleanArtist(parts[0])))
                out.append(Candidate(title: parts[0], artist: artist))
            }
        }
        // "Song | Film | Singer": each part may be the song name.
        if title.contains("|") {
            for part in title.components(separatedBy: "|").map(trim).filter({ !$0.isEmpty }).prefix(3) {
                out.append(Candidate(title: part, artist: artist))
            }
        }
        var seen = Set<String>()
        return out.filter { !$0.title.isEmpty && seen.insert("\($0.title.lowercased())|\($0.artist.lowercased())").inserted }
    }

    static func cleanTitle(_ raw: String) -> String {
        var title = raw
        // Bracketed extras: (Official Video), [Lyrics], (feat. X), (From "Film")…
        title = title.replacingOccurrences(of: #"\s*[\(\[\{][^\)\]\}]*[\)\]\}]"#, with: "", options: .regularExpression)
        let noise = [#"official\s+(music\s+)?(video|audio|lyric(al)?\s+video|visuali[sz]er)"#, #"lyric(al)?\s+video"#,
                     #"\blyrics?\b"#, #"\bfull\s+(song|video)\b"#, #"\b(hd|4k|hq)\b"#, #"\s(ft|feat)\.?\s.*$"#]
        for pattern in noise {
            title = title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return trim(title.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-–—|:,"))
            .trimmingCharacters(in: .whitespaces)
    }

    static func cleanArtist(_ raw: String) -> String {
        var artist = raw.replacingOccurrences(of: #"\s*-\s*Topic$|VEVO$|\s+Official$"#, with: "", options: [.regularExpression, .caseInsensitive])
        for separator in [",", " & ", " x ", " X ", " feat", " ft.", " and "] {
            if let range = artist.range(of: separator) { artist = String(artist[..<range.lowerBound]) }
        }
        return trim(artist)
    }

    /// Same song name ignoring case, punctuation and extras: one contains the other.
    static func looselyMatches(_ lhs: String, _ rhs: String) -> Bool {
        let normalize = { (text: String) in
            cleanTitle(text).lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let a = normalize(lhs), b = normalize(rhs)
        return !a.isEmpty && !b.isEmpty && (a.contains(b) || b.contains(a))
    }

    private static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// lrclib.net: free, keyless, community timed lyrics.
private enum LRCLib {
    struct Track: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    static func get(title: String, artist: String, duration: Double) async -> LyricResult {
        var items = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        guard let track: Track = await fetch("get", items) else { return .unavailable }
        return result(from: [track], duration: duration)
    }

    static func search(title: String, artist: String, duration: Double) async -> LyricResult {
        let tracks: [Track]? = await fetch("search", [URLQueryItem(name: "track_name", value: title),
                                                      URLQueryItem(name: "artist_name", value: artist)])
        return result(from: tracks ?? [], duration: duration)
    }

    static func search(freeText: String, duration: Double) async -> LyricResult {
        let tracks: [Track]? = await fetch("search", [URLQueryItem(name: "q", value: freeText)])
        return result(from: tracks ?? [], duration: duration)
    }

    /// Prefers timed lyrics whose length is close to the track's (versions differ by intros and outros; videos run
    /// long), else plain lyrics.
    private static func result(from tracks: [Track], duration: Double) -> LyricResult {
        let usable = tracks.filter { $0.instrumental != true }
        let distance = { (track: Track) in duration > 0 ? abs((track.duration ?? duration) - duration) : 0 }
        if let synced = usable.filter({ $0.syncedLyrics != nil && distance($0) <= 45 }).min(by: { distance($0) < distance($1) }),
           let parsed = LRCParser.parse(synced.syncedLyrics ?? "") {
            return .synced(SyncedLyrics(lines: parsed.lines, source: "LRCLIB"))
        }
        if let text = usable.first(where: { $0.plainLyrics?.isEmpty == false })?.plainLyrics {
            return .plain(Lyrics(text: text, source: "LRCLIB"))
        }
        return .unavailable
    }

    private static func fetch<T: Decodable>(_ endpoint: String, _ items: [URLQueryItem]) async -> T? {
        var components = URLComponents(string: "https://lrclib.net/api/\(endpoint)")!
        components.queryItems = items
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("AppleTube/1.0 (personal)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
