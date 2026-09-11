import Combine
import Foundation

/// Tracks local, non-verifiable free-tier usage. This is intentionally simple: there is no
/// backend, no account, and no anti-tamper effort. A determined user can reset these counters;
/// that is an accepted trade-off for an app with no server component.
@MainActor
final class UsageTracker: ObservableObject {

    @Published private(set) var freeExportsUsed: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.freeExportsUsed = defaults.integer(forKey: Monetization.StorageKey.freeExportsUsed)
    }

    var freeExportsRemaining: Int {
        max(0, Monetization.FreeTier.exportLimit - freeExportsUsed)
    }

    /// `true` if the user may export right now. `isPro` always wins.
    func canExport(isPro: Bool) -> Bool {
        isPro || freeExportsUsed < Monetization.FreeTier.exportLimit
    }

    /// `true` if the user may start a new recording that would create another saved project.
    /// `isPro` always wins. Viewing, renaming, deleting, or re-exporting existing projects is
    /// never gated by this -- only pass the count when actually about to create a new one.
    func canCreateProject(currentProjectCount: Int, isPro: Bool) -> Bool {
        isPro || currentProjectCount < Monetization.FreeTier.projectLimit
    }

    /// Call ONLY after an export file has been successfully written.
    func recordSuccessfulExport() {
        freeExportsUsed += 1
        defaults.set(freeExportsUsed, forKey: Monetization.StorageKey.freeExportsUsed)
    }
}
