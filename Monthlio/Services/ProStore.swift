import CryptoKit
import Foundation
import Observation
import StoreKit
import os

private let log = Logger(subsystem: "com.monthlio.app", category: "store")

/// What the app needs to know about the Pro product, free of StoreKit
/// types so the purchase state machine can be tested with a fake client.
struct ProProductInfo: Equatable {
    let id: String
    let displayPrice: String
}

enum ProPurchaseResult: Equatable {
    case purchased
    case pending
    case cancelled
    case unverified
}

/// The slice of StoreKit 2 that `ProStore` uses.
protocol ProStoreClient {
    func product(id: String) async throws -> ProProductInfo?
    func purchase(id: String) async throws -> ProPurchaseResult
    func restore() async throws
    func hasEntitlement(for id: String) async -> Bool
    /// True when a refund or revocation of `id` is on record.
    func hasRevocation(for id: String) async -> Bool
    /// The build the account first downloaded, from the App Store's signed
    /// app transaction. Nil when it can't be verified.
    func originalAppBuild() async throws -> String?
    /// Yields whenever a transaction arrives outside `purchase`: another
    /// device, Family Sharing, or a refund.
    func updates() -> AsyncStream<Void>
}

/// Real StoreKit 2.
final class StoreKitProClient: ProStoreClient {
    private var loaded: Product?

    func product(id: String) async throws -> ProProductInfo? {
        if loaded == nil {
            loaded = try await fetch(id)
        }
        return loaded.map { ProProductInfo(id: $0.id, displayPrice: $0.displayPrice) }
    }

    /// One App Store request, with the answer logged: an empty answer is
    /// silent in StoreKit and has cost an App Review round already (the
    /// Paid Apps Agreement wasn't in effect, so the sandbox had nothing to
    /// sell), so the log names what to check.
    private func fetch(_ id: String) async throws -> Product? {
        let products: [Product]
        do {
            products = try await Product.products(for: [id])
        } catch {
            log.error("Loading \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        guard let product = products.first else {
            let storefront = await Storefront.current?.countryCode ?? "unknown"
            log.error("The App Store has no product \(id, privacy: .public) for storefront \(storefront, privacy: .public). Check the Paid Apps Agreement (Business > Agreements must be Active) and the product's state in App Store Connect.")
            return nil
        }
        log.info("Loaded \(product.id, privacy: .public) at \(product.displayPrice, privacy: .public)")
        return product
    }

    func purchase(id: String) async throws -> ProPurchaseResult {
        if loaded == nil {
            loaded = try await fetch(id)
        }
        guard let product = loaded else { return .unverified }
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return .unverified }
            await transaction.finish()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restore() async throws {
        try await AppStore.sync()
    }

    func hasEntitlement(for id: String) async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == id, transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    func hasRevocation(for id: String) async -> Bool {
        for await result in Transaction.all {
            if case .verified(let transaction) = result, transaction.productID == id, transaction.revocationDate != nil {
                return true
            }
        }
        return false
    }

    /// Only a production transaction can prove a pre-Pro download. The
    /// sandbox (App Review, TestFlight) and Xcode report "1.0" for every
    /// account, so those environments answer with a sentinel that is
    /// recorded but never grandfathers.
    func originalAppBuild() async throws -> String? {
        guard case .verified(let transaction) = try await AppTransaction.shared else { return nil }
        guard transaction.environment == .production else { return "sandbox" }
        return transaction.originalAppVersion
    }

    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result {
                        await transaction.finish()
                    }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Monthlio Pro is a one-time purchase that unlocks iCloud sync, custom
/// colors and CSV export; a code from the developer unlocks it too. The
/// entitlement is cached locally so launch can pick the store configuration
/// before StoreKit has answered.
@MainActor
@Observable
final class ProStore {
    nonisolated static let productID = "com.monthlio.app.pro"
    nonisolated static let entitlementKey = "pro.entitled"
    /// The code this device redeemed, if any.
    nonisolated static let promoCodeKey = "pro.promoCode"
    /// SHA-256 digests of the accepted codes (trimmed, upper-cased), so the
    /// codes themselves can't be read out of the binary. To add one:
    /// `printf 'CODE' | shasum -a 256`.
    nonisolated static let promoCodeDigests: Set<String> = [
        "5e196d55be6b6efe368b469ac4c0f6d342854a0077e8d35e836c48a39b8e8b25",
    ]

    private(set) var product: ProProductInfo?
    private(set) var isEntitled: Bool
    /// Downloaded before Pro existed, so sync is free on this account.
    private(set) var isGrandfathered: Bool
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var isLoadingProduct = false
    private(set) var lastError: String?
    /// Pauses between product requests before the paywall offers "Try
    /// Again". The App Store can answer empty for a moment right after an
    /// install, and the sandbox App Review uses is slower still. Tests
    /// shorten or drop them.
    var retryDelays: [Duration] = [.milliseconds(500), .seconds(2)]

    private let client: ProStoreClient
    private let defaults: UserDefaults
    private var updatesTask: Task<Void, Never>?

    init(client: ProStoreClient = StoreKitProClient(), defaults: UserDefaults = SyncPreference.standard) {
        self.client = client
        self.defaults = defaults
        isEntitled = defaults.bool(forKey: Self.entitlementKey) || Self.hasRedeemedCode(defaults)
        isGrandfathered = SyncPreference.isGrandfathered(defaults)
    }

    /// Sync is allowed with Pro or for accounts that predate it.
    var canSync: Bool { isEntitled || isGrandfathered }

    /// Runs after a purchase, a found purchase or a redeemed code, from
    /// whichever screen offered Pro. Buying Pro means wanting sync, unless
    /// an early supporter who already had it free turned it off on
    /// purpose; opened for sync, the answer is always yes. Returns whether
    /// sync was turned on.
    @discardableResult
    func enableSyncAfterUnlock(purpose: PaywallPurpose) -> Bool {
        guard purpose == .sync || !isGrandfathered else { return false }
        SyncPreference.setEnabled(true, defaults)
        return true
    }

    /// Verifies the entitlement, loads the product and starts listening for
    /// transactions made elsewhere.
    func start() async {
        if updatesTask == nil {
            let stream = client.updates()
            updatesTask = Task { [weak self] in
                for await _ in stream {
                    await self?.refreshEntitlement()
                }
            }
        }
        await refreshEntitlement()
        await loadProduct()
    }

    /// Asks the App Store once which build this account first downloaded.
    /// Not called at launch: fetching the app transaction can show an
    /// Apple Account sign-in prompt, so it runs when the user reaches the
    /// sync row or the paywall. If the App Store can't answer (offline, or
    /// a simulator without StoreKit testing) it is asked again next time.
    func recordOriginalBuildIfNeeded() async {
        guard !SyncPreference.ignoresAppTransaction, !SyncPreference.hasRecordedOriginalBuild(defaults) else { return }
        guard let version = try? await client.originalAppBuild() else { return }
        SyncPreference.recordOriginalBuild(version, defaults)
        isGrandfathered = SyncPreference.isGrandfathered(defaults)
    }

    /// Loads the product, asking again after each `retryDelays` pause when
    /// the answer is empty or fails. The error is reported once, after the
    /// last attempt, so the paywall shows a spinner rather than a message
    /// that flickers between tries.
    /// For a reinstalled device with an empty store: asks the App Store
    /// whether this account may sync (an early download or a Pro purchase)
    /// and turns sync on if so. Returns whether sync is now on; the store
    /// itself switches to iCloud on the next launch.
    func enableSyncIfAllowed() async -> Bool {
        await recordOriginalBuildIfNeeded()
        await refreshEntitlement()
        guard canSync else { return false }
        SyncPreference.setEnabled(true, defaults)
        return true
    }

    func loadProduct() async {
        guard product == nil, !isLoadingProduct else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        lastError = nil
        var failure: String?
        for attempt in 0...retryDelays.count {
            if attempt > 0 {
                try? await Task.sleep(for: retryDelays[attempt - 1])
                if Task.isCancelled { break }
            }
            do {
                product = try await client.product(id: Self.productID)
                if product != nil { return }
                failure = String(localized: "Monthlio Pro isn't available right now.")
            } catch {
                failure = String(localized: "Couldn't load pricing. Check your connection and try again.")
            }
        }
        lastError = failure
    }

    /// Returns true once the purchase is verified.
    @discardableResult
    func purchase() async -> Bool {
        guard product != nil, !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        lastError = nil
        do {
            switch try await client.purchase(id: Self.productID) {
            case .purchased:
                setEntitled(true)
                return true
            case .pending:
                lastError = String(localized: "The purchase is waiting for approval.")
            case .cancelled:
                break
            case .unverified:
                lastError = String(localized: "Apple couldn't verify the purchase. Try Restore Purchases.")
            }
        } catch {
            lastError = error.localizedDescription
        }
        return false
    }

    /// Trimmed and upper-cased, so "mogz " and "MOGZ" are the same code.
    nonisolated static func normalizedCode(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    nonisolated static func isPromoCode(_ text: String) -> Bool {
        let normalized = normalizedCode(text)
        guard !normalized.isEmpty else { return false }
        let digest = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        return promoCodeDigests.contains(digest)
    }

    nonisolated static func hasRedeemedCode(_ defaults: UserDefaults) -> Bool {
        defaults.string(forKey: promoCodeKey) != nil
    }

    /// A code from the developer (a gift, a review copy) unlocks Pro on this
    /// device without a purchase. The code is remembered so a refund or an
    /// empty App Store answer never takes Pro away again. Returns false,
    /// with `lastError` set, for a code that isn't accepted.
    @discardableResult
    func redeem(code: String) -> Bool {
        lastError = nil
        guard Self.isPromoCode(code) else {
            lastError = String(localized: "That code didn't work. Check it and try again.")
            return false
        }
        defaults.set(Self.normalizedCode(code), forKey: Self.promoCodeKey)
        setEntitled(true)
        return true
    }

    /// Asks the App Store for this account's purchases. One at a time: a
    /// second tap while the first is still signing in would open a second
    /// sign-in sheet. Cancelling that sheet is not an error. When nothing
    /// is found the page says so, for early supporters too: their free
    /// sync is explained by the note above the benefits, not by silence.
    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        lastError = nil
        do {
            try await client.restore()
        } catch StoreKitError.userCancelled {
            return
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlement()
        await recordOriginalBuildIfNeeded()
        if !isEntitled, lastError == nil {
            lastError = String(localized: "No Monthlio Pro purchase was found for this Apple Account.")
        }
    }

    /// A cached entitlement survives an empty answer (signed-out App Store
    /// account, StoreKit cache not yet restored); only a refund or
    /// revocation on record takes it away. A redeemed code is Pro on this
    /// device whatever the App Store says.
    func refreshEntitlement() async {
        if await client.hasEntitlement(for: Self.productID) {
            setEntitled(true)
            return
        }
        if Self.hasRedeemedCode(defaults) {
            setEntitled(true)
            return
        }
        if isEntitled, !(await client.hasRevocation(for: Self.productID)) {
            return
        }
        setEntitled(false)
    }

    private func setEntitled(_ entitled: Bool) {
        isEntitled = entitled
        defaults.set(entitled, forKey: Self.entitlementKey)
        SyncPreference.reconcile(isPro: entitled, defaults)
    }
}
