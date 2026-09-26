import SwiftUI
import XCTest
@testable import Monthlio

private final class PricedProClient: ProStoreClient {
    func product(id: String) async throws -> ProProductInfo? { ProProductInfo(id: id, displayPrice: "$9.99") }
    func purchase(id: String) async throws -> ProPurchaseResult { .cancelled }
    func restore() async throws {}
    func hasEntitlement(for id: String) async -> Bool { false }
    func hasRevocation(for id: String) async -> Bool { false }
    func originalAppBuild() async throws -> String? { "6" }
    func updates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// Renders the paywall with the price loaded, at iPhone 15 size, for the
/// in-app purchase review screenshot. The simulator can't show the price
/// from the command line, so this is the honest picture of the screen.
@MainActor
final class PaywallRenderTests: XCTestCase {
    func testPaywallRendersWithThePriceLoaded() async throws {
        let store = ProStore(client: PricedProClient(), defaults: UserDefaults(suiteName: "PaywallRenderTests")!)
        await store.loadProduct()
        XCTAssertEqual(store.product?.displayPrice, "$9.99")

        // ImageRenderer doesn't pick up the asset catalog's accent colour, so
        // apply the same green the app uses.
        let view = PaywallBody()
            .environment(store)
            .padding()
            .frame(width: 393, height: 852)
            .background(Color(.systemGroupedBackground))
            .tint(MonthlioBrand.green)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width * image.scale, 1179)

        // A blank background or SwiftUI's unsupported-view placeholder must
        // fail: the real paywall has the green Unlock button somewhere.
        let cg = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cg.dataProvider?.data) as Data
        let bytesPerPixel = cg.bitsPerPixel / 8
        var sawGreen = false
        for y in stride(from: 0, to: cg.height, by: 12) {
            for x in stride(from: 0, to: cg.width, by: 12) {
                let i = y * cg.bytesPerRow + x * bytesPerPixel
                let (p0, p1, p2) = (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
                // Brand green is roughly (45, 179, 111); byte order may be RGB or BGR.
                if p1 > 150 && p1 > p0 + 60 && p1 > p2 + 40 { sawGreen = true }
            }
        }
        XCTAssertTrue(sawGreen, "no green button pixels: the paywall did not render")

        let directory = FileManager.default.temporaryDirectory.appending(path: "monthlio-paywall")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: directory.appending(path: "paywall-9.99.png"))
        print("PAYWALL_RENDER_DIR=\(directory.path)")
    }
}
