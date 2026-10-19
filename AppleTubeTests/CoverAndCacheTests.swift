import Foundation
import Testing
@testable import AppleTube

@MainActor
struct CoverAndCacheTests {
    @Test func defaultCoverIsStablePerPlaylist() {
        let a = CoverStyle.default(for: "PLabc123")
        #expect(a == CoverStyle.default(for: "PLabc123"))
        #expect((0 ..< CoverStyle.palettes.count).contains(a.palette))
        // Different playlists spread across the palette rather than all looking the same.
        let palettes = Set((0 ..< 40).map { CoverStyle.default(for: "PL\($0)").palette })
        #expect(palettes.count >= 6)
    }

    @Test func coverStyleIgnoresBrowsePrefix() {
        #expect(CoverStore.shared.style(for: "VLPLxyz") == CoverStore.shared.style(for: "PLxyz"))
    }

    @Test func responseCacheRoundTripAndExpiry() {
        let cache = ResponseCache()
        let key = "test|\(UUID())"
        cache.put(Data("hello".utf8), key: key)
        #expect(cache.get(key: key, maxAge: 60) == Data("hello".utf8))
        #expect(cache.get(key: key, maxAge: -1) == nil)
        cache.remove(key: key)
        #expect(cache.get(key: key, maxAge: .infinity) == nil)
    }

    @Test func bareIdDropsBrowsePrefix() {
        #expect(YTMusicAPI.bareId("VLPL123") == "PL123")
        #expect(YTMusicAPI.bareId("PL123") == "PL123")
        #expect(YTMusicAPI.browseId(forPlaylist: "PL123") == "VLPL123")
        #expect(YTMusicAPI.browseId(forPlaylist: "MPREb_x") == "MPREb_x")
    }
}
