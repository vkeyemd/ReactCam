import Combine
import Foundation
import StoreKit

/// Source of truth for the Pro entitlement.
///
/// `isPro` is derived only from verified StoreKit transactions -- there is no backend, so
/// on-device `Transaction.currentEntitlements` verification is the only check available, and a
/// local flag is never treated as authoritative.
@MainActor
final class PurchaseManager: ObservableObject {

    enum Notice: Equatable {
        case purchasePending
        case restoreSucceeded
        case restoreNothingFound
        case failed(String)
    }

    // MARK: - Published state

    /// The loaded store product. Nil until `loadProducts()` succeeds.
    @Published private(set) var proProduct: Product?
    @Published private(set) var isPro = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false

    /// Transient user-facing message. The presenting view clears this after showing it.
    @Published var notice: Notice?

    // MARK: - Internals

    private var updatesTask: Task<Void, Never>?
    private var didStart = false

    /// Localized, store-supplied price. Never hardcode a price in the UI.
    var displayPrice: String? { proProduct?.displayPrice }

    // MARK: - Lifecycle

    /// Call once from the app root. Starts the transaction listener, loads products, and
    /// resolves the current entitlement.
    func start() async {
        guard !didStart else { return }
        didStart = true

        // Started before any purchase so renewals/refunds/Ask-to-Buy approvals that arrive
        // later are still observed.
        updatesTask = observeTransactionUpdates()

        await loadProducts()
        await refreshEntitlements()
    }

    // MARK: - Products

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: [Monetization.Product.proLifetimeID])
            proProduct = products.first
            if proProduct == nil {
                notice = .failed("The Pro upgrade isn't available right now. Please try again later.")
            }
        } catch {
            proProduct = nil
            notice = .failed("Couldn't reach the App Store. Check your connection and try again.")
        }
    }

    // MARK: - Entitlement

    /// Recomputes `isPro` from StoreKit's verified current entitlements.
    func refreshEntitlements() async {
        var unlocked = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            guard transaction.productID == Monetization.Product.proLifetimeID else { continue }
            guard transaction.revocationDate == nil else { continue }
            unlocked = true
        }

        isPro = unlocked
    }

    // MARK: - Purchase

    /// Returns true if Pro is unlocked after the attempt.
    @discardableResult
    func purchasePro() async -> Bool {
        guard let product = proProduct else {
            notice = .failed("The Pro upgrade isn't available right now. Please try again.")
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isPro

            case .userCancelled:
                return false

            case .pending:
                notice = .purchasePending
                return false

            @unknown default:
                return false
            }
        } catch {
            notice = .failed("Purchase could not be completed. You were not charged.")
            return false
        }
    }

    // MARK: - Restore

    /// Only call from an explicit user tap (paywall footer or Settings row). `AppStore.sync()`
    /// may prompt for App Store credentials.
    func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            notice = isPro ? .restoreSucceeded : .restoreNothingFound
        } catch {
            notice = .failed("Couldn't restore purchases right now. Please try again.")
        }
    }

    // MARK: - Transaction listener

    /// Long-lived. Kept for the app's lifetime; never cancelled on view disappearance.
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if let transaction = try? self.verified(update) {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    // MARK: - Verification

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }
}

// Allows the StoreKit notice enum to drive `.alert(item:)`.
extension PurchaseManager.Notice: Identifiable {
    var id: String {
        switch self {
        case .purchasePending: return "purchasePending"
        case .restoreSucceeded: return "restoreSucceeded"
        case .restoreNothingFound: return "restoreNothingFound"
        case .failed(let message): return "failed-\(message)"
        }
    }
}
