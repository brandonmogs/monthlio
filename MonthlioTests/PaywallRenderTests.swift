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

        let view = PaywallView()
            .environment(store)
            .frame(width: 393, height: 852)
            .background(Color(.systemGroupedBackground))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width * image.scale, 1179)

        let directory = FileManager.default.temporaryDirectory.appending(path: "monthlio-paywall")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: directory.appending(path: "paywall-9.99.png"))
        print("PAYWALL_RENDER_DIR=\(directory.path)")
    }
}
