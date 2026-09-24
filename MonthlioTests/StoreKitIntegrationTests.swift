import StoreKit
import StoreKitTest
import XCTest
@testable import Monthlio

/// Exercises the real StoreKit 2 client against StoreKit/Monthlio.storekit.
/// StoreKit testing needs the simulator's StoreKit test daemon, which only
/// answers when the active developer directory is a full Xcode; elsewhere
/// the test skips rather than fails.
@MainActor
final class StoreKitIntegrationTests: XCTestCase {
    func testLocalConfigurationSellsAndRefundsPro() async throws {
        let session = try SKTestSession(configurationFileNamed: "Monthlio")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()

        let client = StoreKitProClient()
        let product = try? await client.product(id: ProStore.productID)
        try XCTSkipIf(product == nil, "StoreKit testing is unavailable here (select a full Xcode with xcode-select to enable it)")

        XCTAssertEqual(product?.displayPrice, "$9.99")
        let outcome = try await client.purchase(id: ProStore.productID)
        XCTAssertEqual(outcome, .purchased)
        let entitled = await client.hasEntitlement(for: ProStore.productID)
        XCTAssertTrue(entitled)

        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: UInt(transaction.identifier))
        let stillEntitled = await client.hasEntitlement(for: ProStore.productID)
        XCTAssertFalse(stillEntitled)
        session.clearTransactions()
    }
}
