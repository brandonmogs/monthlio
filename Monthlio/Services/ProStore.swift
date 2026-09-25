import Foundation
import Observation
import StoreKit

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
            loaded = try await Product.products(for: [id]).first
        }
        return loaded.map { ProProductInfo(id: $0.id, displayPrice: $0.displayPrice) }
    }

    func purchase(id: String) async throws -> ProPurchaseResult {
        if loaded == nil {
            loaded = try await Product.products(for: [id]).first
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

    func originalAppBuild() async throws -> String? {
        guard case .verified(let transaction) = try await AppTransaction.shared else { return nil }
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

/// Monthlio Pro is a one-time purchase that unlocks iCloud sync. The
/// entitlement is cached locally so launch can pick the store configuration
/// before StoreKit has answered.
@MainActor
@Observable
final class ProStore {
    static let productID = "com.monthlio.app.pro"
    static let entitlementKey = "pro.entitled"

    private(set) var product: ProProductInfo?
    private(set) var isEntitled: Bool
    /// Downloaded before Pro existed, so sync is free on this account.
    private(set) var isGrandfathered: Bool
    private(set) var isPurchasing = false
    private(set) var isLoadingProduct = false
    private(set) var lastError: String?

    private let client: ProStoreClient
    private let defaults: UserDefaults
    private var updatesTask: Task<Void, Never>?

    init(client: ProStoreClient = StoreKitProClient(), defaults: UserDefaults = SyncPreference.standard) {
        self.client = client
        self.defaults = defaults
        isEntitled = defaults.bool(forKey: Self.entitlementKey)
        isGrandfathered = SyncPreference.isGrandfathered(defaults)
    }

    /// Sync is allowed with Pro or for accounts that predate it.
    var canSync: Bool { isEntitled || isGrandfathered }

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
        await recordOriginalBuildIfNeeded()
        await loadProduct()
    }

    /// Asks the App Store once which build this account first downloaded.
    /// If it can't answer (offline, or a simulator without StoreKit testing)
    /// the question is asked again on the next launch.
    func recordOriginalBuildIfNeeded() async {
        guard !SyncPreference.ignoresAppTransaction, !SyncPreference.hasRecordedOriginalBuild(defaults) else { return }
        guard let version = try? await client.originalAppBuild() else { return }
        SyncPreference.recordOriginalBuild(version, defaults)
        isGrandfathered = SyncPreference.isGrandfathered(defaults)
    }

    func loadProduct() async {
        guard product == nil, !isLoadingProduct else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            product = try await client.product(id: Self.productID)
            lastError = product == nil ? String(localized: "Monthlio Pro isn't available right now.") : nil
        } catch {
            lastError = String(localized: "Couldn't load pricing. Check your connection and try again.")
        }
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

    func restore() async {
        lastError = nil
        do {
            try await client.restore()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlement()
        if !isEntitled, lastError == nil {
            lastError = String(localized: "No Monthlio Pro purchase was found for this Apple Account.")
        }
    }

    func refreshEntitlement() async {
        setEntitled(await client.hasEntitlement(for: Self.productID))
    }

    private func setEntitled(_ entitled: Bool) {
        isEntitled = entitled
        defaults.set(entitled, forKey: Self.entitlementKey)
        SyncPreference.reconcile(isPro: entitled, defaults)
    }
}
