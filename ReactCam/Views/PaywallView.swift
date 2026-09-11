import SwiftUI

/// Real StoreKit 2 paywall for the one-time "ReactCam Pro" unlock. Presented for one of three
/// reasons (free exports used up, free project slots used up, or a manual upgrade from
/// Settings) -- the reason only changes the headline/subhead copy, not the purchase mechanics.
struct PaywallView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    let reason: Monetization.PaywallReason
    /// Called only after Pro is confirmed unlocked (purchase or restore).
    let onUnlocked: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefits
                    Spacer(minLength: 8)
                    callToAction
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(purchaseManager.isPurchasing)
        .task {
            if purchaseManager.proProduct == nil {
                await purchaseManager.loadProducts()
            }
        }
        .alert(item: $purchaseManager.notice) { notice in
            switch notice {
            case .purchasePending:
                return Alert(
                    title: Text("Purchase Pending"),
                    message: Text("Your purchase needs approval before it can be completed. It will unlock automatically once approved."),
                    dismissButton: .default(Text("OK"))
                )
            case .restoreSucceeded:
                return Alert(
                    title: Text("Welcome back"),
                    message: Text("ReactCam Pro has been restored on this device."),
                    dismissButton: .default(Text("OK")) {
                        onUnlocked()
                        dismiss()
                    }
                )
            case .restoreNothingFound:
                return Alert(
                    title: Text("Nothing to Restore"),
                    message: Text("No previous ReactCam Pro purchase was found for this Apple Account."),
                    dismissButton: .default(Text("OK"))
                )
            case .failed(let message):
                return Alert(
                    title: Text("Something went wrong"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .padding(.top, 16)

            Text(reason.headline)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(reason.subhead)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 16) {
            BenefitRow(
                icon: "infinity",
                title: "Unlimited exports",
                subtitle: "Full quality, no watermark, no limits."
            )
            BenefitRow(
                icon: "folder",
                title: "Unlimited projects",
                subtitle: "Keep and re-edit your whole library."
            )
            BenefitRow(
                icon: "lock.shield",
                title: "Private by design",
                subtitle: "Your videos never leave your device. We collect no data."
            )
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var callToAction: some View {
        VStack(spacing: 10) {
            if purchaseManager.isLoadingProducts {
                ProgressView()
                    .padding(.vertical, 14)
            } else if let price = purchaseManager.displayPrice {
                // Price always comes from StoreKit -- never hardcoded.
                Button {
                    Task {
                        if await purchaseManager.purchasePro() {
                            onUnlocked()
                            dismiss()
                        }
                    }
                } label: {
                    Group {
                        if purchaseManager.isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Text("Unlock Pro — \(price)")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(purchaseManager.isPurchasing)
            } else {
                Button("Retry") {
                    Task { await purchaseManager.loadProducts() }
                }
                .buttonStyle(.bordered)
                Text("The upgrade couldn't be loaded. Check your connection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await purchaseManager.restorePurchases()
                    if purchaseManager.isPro {
                        onUnlocked()
                        dismiss()
                    }
                }
            } label: {
                if purchaseManager.isRestoring {
                    ProgressView()
                } else {
                    Text("Restore Purchases")
                }
            }
            .font(.footnote)
            .disabled(purchaseManager.isRestoring)

            Text("One-time purchase. Yours forever.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("ReactCam collects no data. No account, no uploads, no tracking.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct BenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
