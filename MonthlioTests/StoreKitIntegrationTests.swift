import StoreKit
import StoreKitTest
import XCTest
@testable import Monthlio

/// Exercises the real StoreKit 2 client against StoreKit/Monthlio.storekit.
///
/// On the iOS 26.3 and later simulator runtimes, StoreKit configurations
/// only reach the simulator's storekitd when the run is launched from the
/// Xcode IDE (Cmd+U); `xcodebuild test` from the command line gets
/// SKInternalErrorDomain code 3 from SKTestSession and the products fall
/// back to the App Store sandbox. In that case the test skips rather than
/// fails. Apple Feedback FB22237318 tracks it.
@MainActor
final class StoreKitIntegrationTests: XCTestCase {
    func testLocalConfigurationSellsAndRefundsPro() async throws {
        let session = try SKTestSession(configurationFileNamed: "Monthlio")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()

        let client = StoreKitProClient()
        let product = try? await client.product(id: ProStore.productID)
        try XCTSkipIf(product == nil, "StoreKit testing needs an Xcode IDE run on iOS 26.3+ simulators (command-line runs can't push the configuration); run this from Xcode with Cmd+U")

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
