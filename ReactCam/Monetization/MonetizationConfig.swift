import Foundation

/// Single source of truth for every monetization constant. Do not hardcode
/// these values anywhere else.
enum Monetization {

    /// Master switch for the entire paywall. While this is `false` the app ships with no
    /// monetization surface at all: no purchase or restore UI anywhere, no export or project
    /// limit enforced, no StoreKit calls made, and the free-export counter frozen so nobody
    /// quietly burns their allotment during a stretch when nothing is actually gated.
    ///
    /// Turned off once, for the 1.2 rejection under guideline 2.1(b): the reviewer hit the
    /// paywall's "Retry" dead end because `Product.products(for:)` came back empty. That was
    /// never a code fault -- the account had no Paid Applications Agreement in effect (the app
    /// had only ever been free), and StoreKit returns zero products until it is, in sandbox and
    /// production alike. Banking details are now filed; re-enabled here.
    static let isEnabled = true

    enum Product {
        /// Non-consumable. Must match the App Store Connect product exactly.
        static let proLifetimeID = "com.objectgraph.reactcam.pro.lifetime"
    }

    enum FreeTier {
        /// Lifetime successful exports available without Pro.
        static let exportLimit = 5
        /// Concurrent saved projects available without Pro. Deleting frees a slot.
        static let projectLimit = 5
    }

    enum StorageKey {
        static let freeExportsUsed = "reactcam.freeExportsUsed"
        static let didMigrateLegacyUsage = "reactcam.didMigrateLegacyUsage"

        // Pre-StoreKit mock keys, read only once by the migration below then left alone.
        static let legacyExportCount = "reactcam.exportCount"
        static let legacyIsProUnlocked = "reactcam.isProUnlocked"
    }

    /// Why the paywall was presented. Drives headline/subhead copy only.
    enum PaywallReason: String, Identifiable {
        case freeExportsExhausted
        case projectLimitReached
        case manualUpgrade

        var id: String { rawValue }

        var headline: String {
            switch self {
            case .freeExportsExhausted:
                return "You've used your \(FreeTier.exportLimit) free exports"
            case .projectLimitReached:
                return "You've saved \(FreeTier.projectLimit) projects"
            case .manualUpgrade:
                return "Unlock ReactCam Pro"
            }
        }

        var subhead: String {
            switch self {
            case .freeExportsExhausted:
                return "Unlock unlimited exports and keep capturing every reaction."
            case .projectLimitReached:
                return "Unlock unlimited projects, or delete a project to free a slot."
            case .manualUpgrade:
                return "Unlock unlimited exports and projects with a one-time purchase."
            }
        }
    }

    /// The app's original (pre-StoreKit) mock gave every install unlimited free exports, so
    /// existing users have never hit a limit before. Rather than grandfather that mocked state
    /// as a real entitlement (no money ever changed hands) or lock in unlimited-forever access,
    /// this resets the counter once so existing installs start counting fresh like a new user --
    /// nothing they've already made is affected, and nobody is charged retroactively.
    static func migrateLegacyUsageIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: StorageKey.didMigrateLegacyUsage) else { return }
        defer { defaults.set(true, forKey: StorageKey.didMigrateLegacyUsage) }

        let hadLegacyState = defaults.object(forKey: StorageKey.legacyExportCount) != nil
            || defaults.object(forKey: StorageKey.legacyIsProUnlocked) != nil
        guard hadLegacyState else { return }

        defaults.set(0, forKey: StorageKey.freeExportsUsed)
    }
}
