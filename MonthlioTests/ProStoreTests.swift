import StoreKit
import XCTest
@testable import Monthlio

private final class FakeProClient: ProStoreClient {
    var productInfo: ProProductInfo? = ProProductInfo(id: ProStore.productID, displayPrice: "$9.99")
    var productError: Error?
    var purchaseResult: ProPurchaseResult = .purchased
    var purchaseError: Error?
    var restoreError: Error?
    var restoreDelay: Duration = .zero
    var entitled = false
    var revoked = false
    var originalBuild: String?
    var originalBuildError: Error?
    /// How many product requests answer empty before `productInfo` is returned.
    var emptyAnswers = 0
    var purchases = 0
    var restores = 0
    var productRequests = 0
    var originalBuildRequests = 0
    private var continuation: AsyncStream<Void>.Continuation?

    func product(id: String) async throws -> ProProductInfo? {
        productRequests += 1
        if let productError { throw productError }
        if productRequests <= emptyAnswers { return nil }
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
        if restoreDelay > .zero { try? await Task.sleep(for: restoreDelay) }
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
        store.retryDelays = []
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
        store.retryDelays = []
        await store.start()
        XCTAssertEqual(store.lastError, "Monthlio Pro isn't available right now.")
        XCTAssertEqual(client.productRequests, 1, "no delays, no retries")
    }

    func testEmptyAnswerIsAskedAgainBeforeGivingUp() async {
        let client = FakeProClient()
        client.productInfo = nil
        let store = ProStore(client: client, defaults: defaults)
        store.retryDelays = [.milliseconds(1), .milliseconds(1)]

        await store.loadProduct()

        XCTAssertNil(store.product)
        XCTAssertEqual(client.productRequests, 3, "the first request plus one per delay")
        XCTAssertEqual(store.lastError, "Monthlio Pro isn't available right now.")
        XCTAssertFalse(store.isLoadingProduct)
    }

    func testProductArrivingOnARetryLoadsQuietly() async {
        let client = FakeProClient()
        client.emptyAnswers = 2
        let store = ProStore(client: client, defaults: defaults)
        store.retryDelays = [.milliseconds(1), .milliseconds(1)]

        await store.start()

        XCTAssertEqual(store.product?.displayPrice, "$9.99")
        XCTAssertNil(store.lastError, "a slow App Store is not an error")
        XCTAssertEqual(client.productRequests, 3)

        await store.loadProduct()
        XCTAssertEqual(client.productRequests, 3, "a loaded product is not requested again")
    }

    func testFailureThenEmptyReportsTheLastAnswer() async {
        let client = FakeProClient()
        client.productError = StubError()
        let store = ProStore(client: client, defaults: defaults)
        store.retryDelays = [.milliseconds(1)]
        await store.loadProduct()
        XCTAssertEqual(store.lastError, "Couldn't load pricing. Check your connection and try again.")
        XCTAssertEqual(client.productRequests, 2)

        client.productError = nil
        client.productInfo = nil
        await store.loadProduct()
        XCTAssertEqual(store.lastError, "Monthlio Pro isn't available right now.")
        XCTAssertEqual(client.productRequests, 4)
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

    func testEnableSyncIfAllowedTurnsSyncOnForProOwnersAndEarlyDownloads() async {
        let client = FakeProClient()
        client.originalBuild = "sandbox"
        let store = ProStore(client: client, defaults: defaults)

        var allowed = await store.enableSyncIfAllowed()
        XCTAssertFalse(allowed, "neither an early download nor a purchase")
        XCTAssertFalse(SyncPreference.isEnabled(defaults))

        client.entitled = true
        allowed = await store.enableSyncIfAllowed()
        XCTAssertTrue(allowed)
        XCTAssertTrue(SyncPreference.isEnabled(defaults))

        let early = FakeProClient()
        early.originalBuild = "2"
        let earlyDefaults = UserDefaults(suiteName: suite + "-early")!
        defer { earlyDefaults.removePersistentDomain(forName: suite + "-early") }
        SyncPreference.migrateIfNeeded(storeExists: false, earlyDefaults)
        let reinstalled = ProStore(client: early, defaults: earlyDefaults)
        let recovered = await reinstalled.enableSyncIfAllowed()
        XCTAssertTrue(recovered, "a pre-Pro download gets its iCloud data back")
        XCTAssertTrue(SyncPreference.isEnabled(earlyDefaults))
    }

    func testDownloadFromBeforeProKeepsSyncOnAnyDevice() async {
        let client = FakeProClient()
        client.originalBuild = "4"
        let store = ProStore(client: client, defaults: defaults)
        XCTAssertFalse(store.canSync, "a fresh install starts local-only")

        await store.start()
        XCTAssertEqual(client.originalBuildRequests, 0, "launch never fetches the app transaction, which can prompt for an Apple Account")

        await store.recordOriginalBuildIfNeeded()

        XCTAssertTrue(store.isGrandfathered)
        XCTAssertTrue(store.canSync)
        XCTAssertTrue(SyncPreference.isEnabled(defaults), "sync was always on before Pro, so it comes back on")
        XCTAssertEqual(client.originalBuildRequests, 1)

        await store.recordOriginalBuildIfNeeded()
        XCTAssertEqual(client.originalBuildRequests, 1, "the App Store is asked once")
    }

    func testDownloadAfterProIsNotGrandfathered() async {
        let client = FakeProClient()
        client.originalBuild = "6"
        let store = ProStore(client: client, defaults: defaults)
        await store.recordOriginalBuildIfNeeded()

        XCTAssertFalse(store.isGrandfathered)
        XCTAssertFalse(store.canSync)
        XCTAssertFalse(SyncPreference.isEnabled(defaults))
    }

    func testSandboxAnswerIsRecordedButNeverGrandfathers() async {
        let client = FakeProClient()
        client.originalBuild = "sandbox"
        let store = ProStore(client: client, defaults: defaults)
        await store.recordOriginalBuildIfNeeded()
        await store.recordOriginalBuildIfNeeded()

        XCTAssertFalse(store.isGrandfathered, "App Review and TestFlight must see the paywall")
        XCTAssertEqual(client.originalBuildRequests, 2, "a sandbox answer is asked again: the App Store build on the same device answers for production")
    }

    func testRestorePurchasesAlsoRecoversAPreProDownload() async {
        let client = FakeProClient()
        client.originalBuild = "2"
        let store = ProStore(client: client, defaults: defaults)
        await store.start()

        await store.restore()

        XCTAssertTrue(store.isGrandfathered)
        XCTAssertTrue(store.canSync)
        // The sync page closes for a free-sync account before this is read;
        // on the Pro page it is the only feedback the tap gets.
        XCTAssertEqual(store.lastError, "No Monthlio Pro purchase was found for this Apple Account.")
    }

    func testACancelledRestoreIsQuietAndRestoresDoNotOverlap() async {
        let client = FakeProClient()
        client.restoreError = StoreKitError.userCancelled
        let store = ProStore(client: client, defaults: defaults)
        await store.start()

        await store.restore()
        XCTAssertNil(store.lastError, "cancelling the sign-in sheet is not an error")
        XCTAssertFalse(store.isRestoring)

        client.restoreError = nil
        client.restoreDelay = .milliseconds(50)
        async let first: Void = store.restore()
        try? await Task.sleep(for: .milliseconds(5))
        XCTAssertTrue(store.isRestoring)
        await store.restore()
        await first
        XCTAssertEqual(client.restores, 2, "the tap during the first restore did nothing")
    }

    func testOriginalBuildIsAskedAgainWhenTheAppStoreCantAnswer() async {
        let client = FakeProClient()
        client.originalBuildError = StubError()
        let store = ProStore(client: client, defaults: defaults)
        await store.recordOriginalBuildIfNeeded()
        XCTAssertFalse(store.isGrandfathered)

        client.originalBuildError = nil
        client.originalBuild = "5"
        await store.recordOriginalBuildIfNeeded()

        XCTAssertEqual(client.originalBuildRequests, 2)
        XCTAssertTrue(store.isGrandfathered, "build 5 never shipped but is still before Pro")
    }

    func testPromoCodeIsTrimmedCaseInsensitiveAndExact() {
        XCTAssertTrue(ProStore.isPromoCode("MOGZ"))
        XCTAssertTrue(ProStore.isPromoCode(" mogz\n"))
        XCTAssertFalse(ProStore.isPromoCode(""))
        XCTAssertFalse(ProStore.isPromoCode("MOGS"))
        XCTAssertFalse(ProStore.isPromoCode("MOGZ1"))
    }

    func testACodeUnlocksProAndOutlastsWhatTheAppStoreSays() async {
        let client = FakeProClient()
        let store = ProStore(client: client, defaults: defaults)
        await store.start()
        XCTAssertFalse(store.isEntitled)

        XCTAssertFalse(store.redeem(code: "MOGS"))
        XCTAssertEqual(store.lastError, "That code didn't work. Check it and try again.")
        XCTAssertFalse(store.isEntitled)

        XCTAssertTrue(store.redeem(code: " mogz "))
        XCTAssertTrue(store.isEntitled)
        XCTAssertNil(store.lastError)
        XCTAssertTrue(store.canSync)
        XCTAssertEqual(client.purchases, 0, "no purchase happened")
        XCTAssertEqual(defaults.string(forKey: ProStore.promoCodeKey), "MOGZ")

        // The App Store knows nothing about the code: no entitlement, and
        // even a refund on record from an earlier purchase changes nothing.
        client.revoked = true
        await store.refreshEntitlement()
        XCTAssertTrue(store.isEntitled, "a redeemed code is Pro whatever the App Store says")

        await store.restore()
        XCTAssertNil(store.lastError, "Restore Purchases doesn't complain to a code holder")

        let fresh = ProStore(client: client, defaults: defaults)
        XCTAssertTrue(fresh.isEntitled, "remembered across launches")
        await fresh.start()
        XCTAssertTrue(fresh.isEntitled)
    }

    func testUnlockTurnsSyncOnExceptForAnEarlySupporterOnTheProPage() {
        let store = ProStore(client: FakeProClient(), defaults: defaults)
        XCTAssertFalse(SyncPreference.isEnabled(defaults))

        XCTAssertTrue(store.enableSyncAfterUnlock(purpose: .pro), "a new buyer wants sync, from whichever screen")
        XCTAssertTrue(SyncPreference.isEnabled(defaults))

        let early = UserDefaults(suiteName: suite + "-early")!
        defer { early.removePersistentDomain(forName: suite + "-early") }
        SyncPreference.migrateIfNeeded(storeExists: true, early)
        SyncPreference.setEnabled(false, early)
        let supporter = ProStore(client: FakeProClient(), defaults: early)
        XCTAssertTrue(supporter.isGrandfathered)
        XCTAssertFalse(supporter.enableSyncAfterUnlock(purpose: .pro), "an early supporter who switched sync off keeps it off")
        XCTAssertFalse(SyncPreference.isEnabled(early))
        XCTAssertTrue(supporter.enableSyncAfterUnlock(purpose: .sync), "opened for sync, sync is what they asked for")
        XCTAssertTrue(SyncPreference.isEnabled(early))
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
