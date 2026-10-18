import Testing
@testable import AppleTube

/// How timed lyric lines become display items (lines plus "• • •" gaps).
@MainActor
struct LyricItemTests {
    private func lyrics(_ lines: [(Int, String)]) -> SyncedLyrics {
        let parsed = LRCParser.parse(lines.map { ms, text in
            String(format: "[%02d:%02d.%02d]%@", ms / 60000, ms / 1000 % 60, ms % 1000 / 10, text)
        }.joined(separator: "\n"))
        return parsed ?? SyncedLyrics(lines: [], source: "test")
    }

    @Test func introGapBeforeLateFirstLine() {
        let items = LyricItem.items(from: lyrics([(12000, "First"), (15000, "Second")]))
        #expect(items.first?.isGap == true)
        #expect(items.first?.endMs == 12000)
        #expect(items.filter { !$0.isGap }.map(\.text) == ["First", "Second"])
    }

    @Test func noIntroGapWhenSingingStartsImmediately() {
        let items = LyricItem.items(from: lyrics([(1000, "Go"), (3000, "On")]))
        #expect(items.first?.text == "Go")
    }

    @Test func instrumentalBreakBetweenDistantLines() {
        let items = LyricItem.items(from: lyrics([(1000, "Before"), (40000, "After")]))
        #expect(items.map(\.isGap) == [false, true, false])
    }

    @Test func emptyLineMarksABreak() {
        // Verse is sung ~3s, then silence until 20s: the break shows as a gap.
        let items = LyricItem.items(from: lyrics([(1000, "Verse"), (4000, ""), (20000, "Chorus")]))
        #expect(items.map(\.text) == ["Verse", "", "Chorus"])
    }

    @Test func shortPausesAreNotGaps() {
        let items = LyricItem.items(from: lyrics([(500, "One"), (3000, "Two"), (6000, "Three")]))
        #expect(items.allSatisfy { !$0.isGap })
    }

    @Test func idsAreSequential() {
        let items = LyricItem.items(from: lyrics([(8000, "A"), (60000, "B"), (61000, "C")]))
        #expect(items.map(\.id) == Array(0 ..< items.count))
    }
}
