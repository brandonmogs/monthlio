import XCTest
@testable import Monthlio

private final class FakeProClient: ProStoreClient {
    var productInfo: ProProductInfo? = ProProductInfo(id: ProStore.productID, displayPrice: "$9.99")
    var productError: Error?
    var purchaseResult: ProPurchaseResult = .purchased
    var purchaseError: Error?
    var restoreError: Error?
    var entitled = false
    var revoked = false
    var originalBuild: String?
    var originalBuildError: Error?
    var purchases = 0
    var restores = 0
    var originalBuildRequests = 0
    private var continuation: AsyncStream<Void>.Continuation?

    func product(id: String) async throws -> ProProductInfo? {
        if let productError { throw productError }
        return productInfo
    }

    func purchase(id: String) async throws -> ProPurchaseResult {
        purchases += 1
        if let purchaseError { throw purchaseError }
        if purchaseResult == .purchased { entitled = true }
        return purchaseResult
    }

    func restore() async throws {
        restores += 1
        if let restoreError { throw restoreError }
    }

    func hasEntitlement(for id: String) async -> Bool { entitled }

    func hasRevocation(for id: String) async -> Bool { revoked }

    func originalAppBuild() async throws -> String? {
        originalBuildRequests += 1
        if let originalBuildError { throw originalBuildError }
        return originalBuild
    }

    func updates() -> AsyncStream<Void> {
        AsyncStream { self.continuation = $0 }
    }

    func transactionArrived() { continuation?.yield() }
}

private struct StubError: LocalizedError {
    var errorDescription: String? { "Network is down" }
}

@MainActor
final class ProStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "ProStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        SyncPreference.migrateIfNeeded(storeExists: false, defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testStartLoadsTheProductAndEntitlement() async {
        let client = FakeProClient()
        let store = ProStore(client: client, defaults: defaults)

        await store.start()

        XCTAssertEqual(store.product?.displayPrice, "$9.99")
        XCTAssertFalse(store.isEntitled)
        XCTAssertNil(store.lastError)
    }

    func testPurchaseUnlocksCachesAndAllowsSync() async {
        let client = FakeProClient()
        let store = ProStore(client: client, defaults: defaults)
        await store.start()

        let purchased = await store.purchase()

        XCTAssertTrue(purchased)
        XCTAssertTrue(store.isEntitled)
        XCTAssertEqual(client.purchases, 1)
        XCTAssertTrue(defaults.bool(forKey: ProStore.entitlementKey), "the next launch can trust the cache")
        XCTAssertTrue(SyncPreference.canSync(isPro: store.isEntitled, defaults))

        let fresh = ProStore(client: FakeProClient(), defaults: defaults)
        XCTAssertTrue(fresh.isEntitled, "cached before StoreKit answers")
    }

    func testCancelledPurchaseIsQuietAndOtherOutcomesExplain() async {
        let client = FakeProClient()
        let store = ProStore(client: client, defaults: defaults)
        await store.start()

        client.purchaseResult = .cancelled
        var outcome = await store.purchase()
        XCTAssertFalse(outcome)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.isEntitled)

        client.purchaseResult = .pending
        outcome = await store.purchase()
        XCTAssertFalse(outcome)
        XCTAssertEqual(store.lastError, "The purchase is waiting for approval.")

        client.purchaseResult = .unverified
        outcome = await store.purchase()
        XCTAssertFalse(outcome)
        XCTAssertEqual(store.lastError, "Apple couldn't verify the purchase. Try Restore Purchases.")

        client.purchaseError = StubError()
        outcome = await store.purchase()
        XCTAssertFalse(outcome)
        XCTAssertEqual(store.lastError, "Network is down")
    }

    func testPurchaseIsIgnoredUntilTheProductLoaded() async {
        let client = FakeProClient()
        client.productError = StubError()
        let store = ProStore(client: client, defaults: defaults)
        await store.start()

        XCTAssertNil(store.product)
        XCTAssertEqual(store.lastError, "Couldn't load pricing. Check your connection and try again.")
        let outcome = await store.purchase()
        XCTAssertFalse(outcome)
        XCTAssertEqual(client.purchases, 0)

        client.productError = nil
        await store.loadProduct()
        XCTAssertNotNil(store.product)
        XCTAssertNil(store.lastError)
    }

    func testMissingProductExplains() async {
        let client = FakeProClient()
        client.productInfo = nil
        let store = ProStore(client: client, defaults: defaults)
        await store.start()
        XCTAssertEqual(store.lastError, "Monthlio Pro isn't available right now.")
    }

    func testRestoreFindsOrExplains() async {
        let client = FakeProClient()
        let store = ProStore(client: client, defaults: defaults)
        await store.start()

        await store.restore()
        XCTAssertEqual(client.restores, 1)
        XCTAssertFalse(store.isEntitled)
        XCTAssertEqual(store.lastError, "No Monthlio Pro purchase was found for this Apple Account.")

        client.entitled = true
        await store.restore()
        XCTAssertTrue(store.isEntitled)
        XCTAssertNil(store.lastError)

        client.restoreError = StubError()
        await store.restore()
        XCTAssertEqual(store.lastError, "Network is down")
    }

    func testRefundArrivingLaterRevokesAndTurnsSyncOff() async {
        let client = FakeProClient()
        let store = ProStore(client: client, defaults: defaults)
        await store.start()
        let purchased = await store.purchase()
        XCTAssertTrue(purchased)
        SyncPreference.setEnabled(true, defaults)

        client.entitled = false
        client.revoked = true
        client.transactionArrived()
        for _ in 0..<50 where store.isEntitled {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertFalse(store.isEntitled)
        XCTAssertFalse(defaults.bool(forKey: ProStore.entitlementKey))
        XCTAssertFalse(SyncPreference.isEnabled(defaults), "sync can't stay on without the entitlement")
    }

    func testTransientlyMissingEntitlementKeepsProAndSync() async {
        let client = FakeProClient()
        let store = ProStore(client: client, defaults: defaults)
        await store.start()
        let purchased = await store.purchase()
        XCTAssertTrue(purchased)
        SyncPreference.setEnabled(true, defaults)

        client.entitled = false
        await store.refreshEntitlement()

        XCTAssertTrue(store.isEntitled, "no refund on record, so the cached purchase stands")
        XCTAssertTrue(SyncPreference.isEnabled(defaults))

        let fresh = ProStore(client: client, defaults: UserDefaults(suiteName: suite + "-never")!)
        defer { UserDefaults(suiteName: suite + "-never")!.removePersistentDomain(forName: suite + "-never") }
        await fresh.refreshEntitlement()
        XCTAssertFalse(fresh.isEntitled, "nothing cached and nothing entitled stays unentitled")
    }

    func testDownloadFromBeforeProKeepsSyncOnAnyDevice() async {
        let client = FakeProClient()
        client.originalBuild = "3"
        let store = ProStore(client: client, defaults: defaults)
        XCTAssertFalse(store.canSync, "a fresh install starts local-only")

        await store.start()

        XCTAssertTrue(store.isGrandfathered)
        XCTAssertTrue(store.canSync)
        XCTAssertTrue(SyncPreference.isEnabled(defaults), "sync was always on before Pro, so it comes back on")
        XCTAssertEqual(client.originalBuildRequests, 1)

        await store.start()
        XCTAssertEqual(client.originalBuildRequests, 1, "the App Store is asked once")
    }

    func testDownloadAfterProIsNotGrandfathered() async {
        let client = FakeProClient()
        client.originalBuild = "4"
        let store = ProStore(client: client, defaults: defaults)
        await store.start()

        XCTAssertFalse(store.isGrandfathered)
        XCTAssertFalse(store.canSync)
        XCTAssertFalse(SyncPreference.isEnabled(defaults))
    }

    func testOriginalBuildIsAskedAgainWhenTheAppStoreCantAnswer() async {
        let client = FakeProClient()
        client.originalBuildError = StubError()
        let store = ProStore(client: client, defaults: defaults)
        await store.start()
        XCTAssertFalse(store.isGrandfathered)

        client.originalBuildError = nil
        client.originalBuild = "1.0"
        await store.start()

        XCTAssertEqual(client.originalBuildRequests, 2)
        XCTAssertTrue(store.isGrandfathered, "a sandbox-style version string still counts as build 1")
    }

    func testGrandfatheredDeviceKeepsSyncAfterRefund() async {
        SyncPreference.migrateIfNeeded(storeExists: true, UserDefaults(suiteName: suite + "-legacy")!)
        let legacy = UserDefaults(suiteName: suite + "-legacy")!
        defer { legacy.removePersistentDomain(forName: suite + "-legacy") }
        let client = FakeProClient()
        client.entitled = true
        let store = ProStore(client: client, defaults: legacy)
        await store.start()
        XCTAssertTrue(SyncPreference.isEnabled(legacy))

        client.entitled = false
        client.revoked = true
        await store.refreshEntitlement()

        XCTAssertFalse(store.isEntitled)
        XCTAssertTrue(SyncPreference.isEnabled(legacy), "early installs keep sync for free")
    }
}
