import XCTest
import SwiftUI
@testable import MediaTracker

final class Phase3UITests: XCTestCase {
    // MARK: - Hex parsing

    func testColorHexAcceptsSixDigitWithHash() {
        XCTAssertNotNil(Color(hex: "#FF00AA"))
        XCTAssertNotNil(Color(hex: "#FF00aa"))
    }

    func testColorHexAcceptsSixDigitWithoutHash() {
        XCTAssertNotNil(Color(hex: "FF00AA"))
    }

    func testColorHexAcceptsThreeDigitShorthand() {
        let short = Color(hex: "#F0A")
        let long = Color(hex: "#FF00AA")
        XCTAssertNotNil(short)
        XCTAssertNotNil(long)
        // Both should yield visually identical red/green/blue (0, 1, 2/3).
        let sRGBShort = NSColor(short!).usingColorSpace(.sRGB)!
        let sRGBLong = NSColor(long!).usingColorSpace(.sRGB)!
        XCTAssertEqual(sRGBShort.redComponent, sRGBLong.redComponent, accuracy: 0.001)
        XCTAssertEqual(sRGBShort.greenComponent, sRGBLong.greenComponent, accuracy: 0.001)
        XCTAssertEqual(sRGBShort.blueComponent, sRGBLong.blueComponent, accuracy: 0.001)
    }

    func testColorHexAcceptsEightDigitWithAlpha() {
        // Alpha digit is accepted but ignored (we render opaque in the theme system).
        XCTAssertNotNil(Color(hex: "#FF00AA80"))
    }

    func testColorHexRejectsMalformedInput() {
        XCTAssertNil(Color(hex: ""))
        XCTAssertNil(Color(hex: "#GG0000"))
        XCTAssertNil(Color(hex: "#12345")) // 5 digits
    }

    func testColorHexTrimsWhitespace() {
        XCTAssertNotNil(Color(hex: "  #FF00AA  "))
    }

    // MARK: - GlassCard renders without crashing

    @MainActor
    func testGlassCardCompiles() {
        // Just confirm the component can be instantiated in a body. Visual checks
        // are out of scope for unit tests; structural smoke is enough.
        let card = GlassCard(color: .blue) { Text("Hi") }
        _ = card.body
    }

    @MainActor
    func testSettingsLabeledRowCompiles() {
        let row = SettingsLabeledRow(title: "X", subtitle: "Y") {
            Picker("", selection: .constant(0)) { Text("A").tag(0) }
        }
        _ = row.body
    }

    @MainActor
    func testAnimatedCarouselCompiles() {
        struct Item: Identifiable { let id: Int }
        let items = [Item(id: 1), Item(id: 2), Item(id: 3)]
        let carousel = AnimatedCarousel(items: items) { i in
            Text("\(i.id)")
        }
        _ = carousel.body
    }
}
