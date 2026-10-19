import Testing
@testable import AppleTube

/// Turning messy YouTube titles into lyrics-database queries.
struct LyricsQueryTests {
    @Test func stripsVideoNoise() {
        #expect(LyricsQuery.cleanTitle("Never Gonna Give You Up (Official Music Video)") == "Never Gonna Give You Up")
        #expect(LyricsQuery.cleanTitle("Yellow [4K] Lyrics") == "Yellow")
        #expect(LyricsQuery.cleanTitle("Tears ft. Louisa Johnson") == "Tears")
    }

    @Test func splitsArtistDashTitle() {
        let candidates = LyricsQuery.candidates(title: "Rick Astley - Never Gonna Give You Up (Official Video)", artist: "RickAstleyVEVO")
        #expect(candidates.contains(.init(title: "Never Gonna Give You Up", artist: "Rick Astley")))
    }

    @Test func triesPipeSeparatedParts() {
        let candidates = LyricsQuery.candidates(title: "भ्रम और कर्म | Ek Taraf Bhram | RealShanky", artist: "RealShanky")
        #expect(candidates.contains(.init(title: "भ्रम और कर्म", artist: "RealShanky")))
        #expect(candidates.contains(.init(title: "Ek Taraf Bhram", artist: "RealShanky")))
    }

    @Test func cleansArtists() {
        #expect(LyricsQuery.cleanArtist("Coldplay - Topic") == "Coldplay")
        #expect(LyricsQuery.cleanArtist("Zedd & Alessia Cara") == "Zedd")
        #expect(LyricsQuery.cleanArtist("Jax Jones, MNEK") == "Jax Jones")
    }

    @Test func noDuplicates() {
        let candidates = LyricsQuery.candidates(title: "Yellow", artist: "Coldplay")
        #expect(candidates == [.init(title: "Yellow", artist: "Coldplay")])
    }

    @Test func looseMatch() {
        #expect(LyricsQuery.looselyMatches("Never Gonna Give You Up (2022 Remaster)", "never gonna give you up"))
        #expect(!LyricsQuery.looselyMatches("Yellow", "Clocks"))
    }
}
