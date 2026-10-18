import Foundation
import Testing
@testable import AppleTube

/// Runs the Kaset parsers against real (signed-out) YouTube Music responses captured by
/// `Scripts/capture_fixtures.py`. When YouTube changes its response format, these fail first.
@MainActor
struct ParserFixtureTests {
    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// Signed-out Home only returns two shelves on the first page; the rest arrive via continuation.
    @Test func home() throws {
        let data = try fixture("home")
        let home = HomeResponseParser.parse(data)
        #expect(home.sections.count >= 2)
        #expect(HomeResponseParser.extractContinuationToken(from: data) != nil)
        #expect(home.sections.allSatisfy { !$0.title.isEmpty })
        #expect(home.sections.contains { !$0.items.isEmpty })
    }

    @Test func search() throws {
        let response = SearchResponseParser.parse(try fixture("search"))
        #expect(!response.songs.isEmpty)
        #expect(!response.albums.isEmpty)
        #expect(response.artists.contains { $0.name.localizedCaseInsensitiveContains("coldplay") })
    }

    @Test func suggestions() throws {
        let suggestions = SearchSuggestionsParser.parse(try fixture("suggestions"))
        #expect(!suggestions.isEmpty)
    }

    @Test func album() throws {
        let album = PlaylistParser.parsePlaylistWithContinuation(try fixture("album"), playlistId: "MPREb_fixture")
        #expect(!album.detail.title.isEmpty)
        #expect(album.detail.tracks.count >= 3)
        #expect(album.detail.tracks.allSatisfy { !$0.videoId.isEmpty })
    }

    @Test func playlist() throws {
        let playlist = PlaylistParser.parsePlaylistWithContinuation(try fixture("playlist"), playlistId: "VLfixture")
        #expect(!playlist.detail.title.isEmpty)
        #expect(playlist.detail.tracks.count >= 5)
    }

    @Test func artist() throws {
        let artist = ArtistParser.parseArtistDetail(try fixture("artist"), artistId: "UCfixture")
        #expect(!artist.name.isEmpty)
        #expect(!artist.songs.isEmpty)
    }

    @Test func radioQueue() throws {
        let queue = RadioQueueParser.parse(from: try fixture("radio"))
        #expect(queue.songs.count >= 10)
    }

    @Test func lyrics() throws {
        let lyrics = LyricsParser.parse(from: try fixture("lyrics"))
        #expect(lyrics.isAvailable)
    }

    @Test func apiKeyExtraction() {
        #expect(YTMusicAPI.extractAPIKey(from: #"ytcfg.set({"INNERTUBE_API_KEY": "AIzaTest123"})"#) == "AIzaTest123")
    }
}

private final class FixtureAnchor {}
