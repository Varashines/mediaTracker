import XCTest
import AppKit
import SwiftUI
@testable import MediaTracker

/// Image loads must survive the ordinary navigation that cancels the requesting
/// `.task`, and a failed response must not become permanent.
@MainActor
final class ImageCacheLoadTests: MTTestCase {
    private let target = CGSize(width: 200, height: 300)

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func pngData() -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = ctx.makeImage() else { return Data() }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    private func svgData() -> Data {
        Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 40 20">
          <rect width="40" height="20" fill="#3366ff"/>
        </svg>
        """.utf8)
    }

    private func response(_ url: URL, status: Int = 200, type: String = "image/png") -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
    }

    override func tearDown() {
        ImageCache.shared.clearMemoryCache()
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Failure handling

    func testNonSuccessStatusReturnsNilAndIsNotCachedAsSuccess() async throws {
        let session = makeSession()
        ImageCache.shared.configureForTesting(session: session)
        let url = URL(string: "https://example.test/poster.jpg")!
        MockURLProtocol.requestHandler = { request in
            (self.response(url, status: 429), Data("rate limited".utf8))
        }

        let first = await ImageCache.shared.get(forKey: url.absoluteString, targetSize: target)
        XCTAssertNil(first, "a 429 body must not be treated as an image")

        // A later attempt is allowed to succeed rather than replaying the cached
        // error body forever.
        MockURLProtocol.requestHandler = { request in
            (self.response(url), self.pngData())
        }
        let second = await ImageCache.shared.get(forKey: url.absoluteString, targetSize: target)
        XCTAssertNotNil(second, "a transient failure must not become permanent")
    }

    // MARK: - SVG detection

    /// "image/svg+xml" contains no ".svg" substring, so the previous mime test
    /// never matched and only URLs ending in .svg were rendered.
    func testSVGIsDetectedFromMimeTypeWhenURLHasNoSVGExtension() async throws {
        let session = makeSession()
        ImageCache.shared.configureForTesting(session: session)
        let url = URL(string: "https://example.test/network-logo")!
        MockURLProtocol.requestHandler = { request in
            (self.response(url, type: "image/svg+xml"), self.svgData())
        }

        let container = await ImageCache.shared.get(forKey: url.absoluteString, targetSize: target)
        // The old mime test never matched, so these bytes fell through to
        // CGImageSourceCreateWithData and came back nil.
        XCTAssertNotNil(container, "an SVG served by mime type must decode")
        XCTAssertGreaterThan(container?.image.width ?? 0, 0)
        XCTAssertGreaterThan(container?.image.height ?? 0, 0)
    }

    // MARK: - Cancellation

    /// A cancelled request must still complete and stay available, because the
    /// decode result is what the next caller collects. Note the view-side half of
    /// this bug — `CachedImageView.loadImage` discarding a decoded image when its
    /// `.task` was cancelled by a navigation push — is not reachable from a unit
    /// test, so it is covered by manual verification rather than here.
    func testCancelledRequestStillPopulatesTheCacheForTheNextCaller() async throws {
        let session = makeSession()
        ImageCache.shared.configureForTesting(session: session)
        let url = URL(string: "https://example.test/poster-cancel.jpg")!
        MockURLProtocol.requestHandler = { request in
            // The mock protocol is synchronous, so delay on its own thread. This
            // gives the caller time to be cancelled mid-flight.
            Thread.sleep(forTimeInterval: 0.02)
            return (self.response(url), self.pngData())
        }

        let task = Task { @MainActor in
            await ImageCache.shared.get(forKey: url.absoluteString, targetSize: target)
        }
        task.cancel()
        _ = await task.value

        XCTAssertNotNil(
            ImageCache.shared.checkMemoryCache(forKey: url.absoluteString, targetSize: target),
            "the decode must still be cached for the next caller"
        )
    }

    // MARK: - Eviction

    /// A cell that scrolls back in is served from the cache, which never touches
    /// `activeTasks` — the old guard missed it and evicted anyway, so the next
    /// remount had to hit disk or network.
    func testEvictionIsSkippedWhenTheKeyWasRequestedAgain() async throws {
        let session = makeSession()
        ImageCache.shared.configureForTesting(session: session)
        let url = URL(string: "https://example.test/poster-scrub.jpg")!
        MockURLProtocol.requestHandler = { request in
            (self.response(url), self.pngData())
        }

        let loaded = await ImageCache.shared.get(forKey: url.absoluteString, targetSize: target)
        XCTAssertNotNil(loaded)

        ImageCache.shared.evictOffscreenImage(forKey: url.absoluteString, targetSize: target)
        // The cell scrolls back into view while the 500ms eviction is pending.
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = await ImageCache.shared.get(forKey: url.absoluteString, targetSize: target)
        try await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertNotNil(
            ImageCache.shared.checkMemoryCache(forKey: url.absoluteString, targetSize: target),
            "a cell that came back must keep its decoded image"
        )
    }
}
