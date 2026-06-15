import XCTest
@testable import MediaTracker

final class EpisodeRangeTests: XCTestCase {

    // MARK: - Range Computation Tests

    func testRangeComputation_8Episodes_NoPills() {
        let episodes = makeEpisodes(count: 8, startAt: 1)
        let ranges = computeEpisodeRanges(episodes: episodes, episodesPerRange: 10, rangeThreshold: 15)
        let showPills = episodes.count > 15
        XCTAssertFalse(showPills, "8 episodes should not show range pills")
        // When no pills, all episodes should be shown
        XCTAssertEqual(episodes.count, 8)
    }

    func testRangeComputation_15Episodes_NoPills() {
        let episodes = makeEpisodes(count: 15, startAt: 1)
        let showPills = episodes.count > 15
        XCTAssertFalse(showPills, "15 episodes should not show range pills")
    }

    func testRangeComputation_16Episodes_TwoRanges() {
        let episodes = makeEpisodes(count: 16, startAt: 1)
        let ranges = computeEpisodeRanges(episodes: episodes, episodesPerRange: 10, rangeThreshold: 15)
        XCTAssertEqual(ranges.count, 2, "16 episodes should have 2 ranges")
        XCTAssertEqual(ranges[0], 1...10, "First range should be 1-10")
        XCTAssertEqual(ranges[1], 11...16, "Second range should be 11-16")
    }

    func testRangeComputation_20Episodes_TwoRanges() {
        let episodes = makeEpisodes(count: 20, startAt: 1)
        let ranges = computeEpisodeRanges(episodes: episodes, episodesPerRange: 10, rangeThreshold: 15)
        XCTAssertEqual(ranges.count, 2, "20 episodes should have 2 ranges")
        XCTAssertEqual(ranges[0], 1...10, "First range should be 1-10")
        XCTAssertEqual(ranges[1], 11...20, "Second range should be 11-20")
    }

    func testRangeComputation_21Episodes_Merged() {
        let episodes = makeEpisodes(count: 21, startAt: 1)
        let ranges = computeEpisodeRanges(episodes: episodes, episodesPerRange: 10, rangeThreshold: 15)
        XCTAssertEqual(ranges.count, 2, "21 episodes should have 2 ranges (merged)")
        XCTAssertEqual(ranges[0], 1...10, "First range should be 1-10")
        XCTAssertEqual(ranges[1], 11...21, "Second range should be 11-21 (merged)")
    }

    func testRangeComputation_31Episodes_ThreeRanges() {
        let episodes = makeEpisodes(count: 31, startAt: 1)
        let ranges = computeEpisodeRanges(episodes: episodes, episodesPerRange: 10, rangeThreshold: 15)
        XCTAssertEqual(ranges.count, 3, "31 episodes should have 3 ranges")
        XCTAssertEqual(ranges[0], 1...10, "First range should be 1-10")
        XCTAssertEqual(ranges[1], 11...20, "Second range should be 11-20")
        XCTAssertEqual(ranges[2], 21...31, "Third range should be 21-31 (merged)")
    }

    func testRangeComputation_50Episodes_FiveRanges() {
        let episodes = makeEpisodes(count: 50, startAt: 1)
        let ranges = computeEpisodeRanges(episodes: episodes, episodesPerRange: 10, rangeThreshold: 15)
        XCTAssertEqual(ranges.count, 5, "50 episodes should have 5 ranges")
        XCTAssertEqual(ranges[0], 1...10)
        XCTAssertEqual(ranges[1], 11...20)
        XCTAssertEqual(ranges[2], 21...30)
        XCTAssertEqual(ranges[3], 31...40)
        XCTAssertEqual(ranges[4], 41...50)
    }

    // MARK: - Episode Count Match Tests

    func testEpisodeCountMatch_16Episodes() {
        let episodes = makeEpisodes(count: 16, startAt: 1)
        let ranges = computeEpisodeRanges(episodes: episodes, episodesPerRange: 10, rangeThreshold: 15)
        // Verify each range's episodes match
        XCTAssertEqual(episodes.filter { ranges[0].contains($0.episodeNumber) }.count, 10, "Range 1-10 should have 10 episodes")
        XCTAssertEqual(episodes.filter { ranges[1].contains($0.episodeNumber) }.count, 6, "Range 11-16 should have 6 episodes")
    }

    func testEpisodeCountMatch_20Episodes() {
        let episodes = makeEpisodes(count: 20, startAt: 1)
        let ranges = computeEpisodeRanges(episodes: episodes, episodesPerRange: 10, rangeThreshold: 15)
        XCTAssertEqual(episodes.filter { ranges[0].contains($0.episodeNumber) }.count, 10, "Range 1-10 should have 10 episodes")
        XCTAssertEqual(episodes.filter { ranges[1].contains($0.episodeNumber) }.count, 10, "Range 11-20 should have 10 episodes")
    }

    func testEpisodeCountMatch_21Episodes() {
        let episodes = makeEpisodes(count: 21, startAt: 1)
        let ranges = computeEpisodeRanges(episodes: episodes, episodesPerRange: 10, rangeThreshold: 15)
        XCTAssertEqual(episodes.filter { ranges[0].contains($0.episodeNumber) }.count, 10, "Range 1-10 should have 10 episodes")
        XCTAssertEqual(episodes.filter { ranges[1].contains($0.episodeNumber) }.count, 11, "Range 11-21 should have 11 episodes")
    }

    func testEpisodeCountMatch_31Episodes() {
        let episodes = makeEpisodes(count: 31, startAt: 1)
        let ranges = computeEpisodeRanges(episodes: episodes, episodesPerRange: 10, rangeThreshold: 15)
        XCTAssertEqual(episodes.filter { ranges[0].contains($0.episodeNumber) }.count, 10)
        XCTAssertEqual(episodes.filter { ranges[1].contains($0.episodeNumber) }.count, 10)
        XCTAssertEqual(episodes.filter { ranges[2].contains($0.episodeNumber) }.count, 11)
    }

    func testEpisodeCountMatch_50Episodes() {
        let episodes = makeEpisodes(count: 50, startAt: 1)
        let ranges = computeEpisodeRanges(episodes: episodes, episodesPerRange: 10, rangeThreshold: 15)
        for range in ranges {
            let count = episodes.filter { range.contains($0.episodeNumber) }.count
            XCTAssertGreaterThan(count, 0, "Range \(range) should have episodes")
        }
        // Total should be 50
        let totalInRange = ranges.reduce(0) { sum, range in
            sum + episodes.filter { range.contains($0.episodeNumber) }.count
        }
        XCTAssertEqual(totalInRange, 50, "All episodes should be in a range")
    }

    func testEpisodeCountMatch_EpisodesWithSpecials() {
        // Episodes: 0, 1, 2, ..., 20 (21 total, but episode 0 is a special)
        let episodes = makeEpisodes(count: 21, startAt: 0)
        let ranges = computeEpisodeRanges(episodes: episodes, episodesPerRange: 10, rangeThreshold: 15)
        XCTAssertEqual(ranges[0], 0...9, "First range should be 0-9")
        XCTAssertEqual(ranges[1], 10...20, "Second range should be 10-20")
        let totalInRange = ranges.reduce(0) { sum, range in
            sum + episodes.filter { range.contains($0.episodeNumber) }.count
        }
        XCTAssertEqual(totalInRange, 21, "All episodes should be in a range")
    }

    // MARK: - Helpers

    private func makeEpisodes(count: Int, startAt: Int) -> [(episodeNumber: Int, isWatched: Bool)] {
        return (0..<count).map { i in
            (episodeNumber: startAt + i, isWatched: i < count - 1) // last one unwatched
        }
    }

    private func computeEpisodeRanges(
        episodes: [(episodeNumber: Int, isWatched: Bool)],
        episodesPerRange: Int,
        rangeThreshold: Int
    ) -> [ClosedRange<Int>] {
        guard !episodes.isEmpty else { return [] }

        let firstEp = episodes.first!.episodeNumber
        let lastEp = episodes.last!.episodeNumber
        var ranges: [ClosedRange<Int>] = []
        var start = firstEp
        while start <= lastEp {
            let end = min(start + episodesPerRange - 1, lastEp)
            ranges.append(start...end)
            start = end + 1
        }

        // Merge last range into previous if ≤ 1 episode
        if ranges.count >= 2 {
            let last = ranges[ranges.count - 1]
            let prev = ranges[ranges.count - 2]
            if last.count <= 1 {
                ranges[ranges.count - 2] = prev.lowerBound...last.upperBound
                ranges.removeLast()
            }
        }

        return ranges
    }
}
