import SwiftUI

/// Mock paywall shown after the user's first free export. Both paths are
/// stubbed — wire `purchasePro` / `watchAd` up to StoreKit and an ad SDK
/// respectively when those integrations land.
struct PaywallView: View {
    let onUnlocked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            Image(systemName: "star.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("Unlock More Exports")
                .font(.title2.bold())

            Text("Your first export was on us. Unlock Pro for unlimited exports, or watch a short ad to export this one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button {
                    purchasePro()
                } label: {
                    Text("Unlock Pro — $4.99")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.black)
                }

                Button {
                    watchAd()
                } label: {
                    Text("Watch an Ad")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal)
            .disabled(isProcessing)

            if isProcessing {
                ProgressView()
            }

            Spacer()
        }
        .padding()
        .presentationDetents([.fraction(0.55)])
    }

    // MARK: - Mock purchase flows

    private func purchasePro() {
        // TODO: Replace with a real StoreKit 2 purchase(_:) call against the
        // "pro_unlock" product, then set the persisted entitlement flag.
        isProcessing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isProcessing = false
            onUnlocked()
            dismiss()
        }
    }

    private func watchAd() {
        // TODO: Replace with a real rewarded-ad SDK call; call onUnlocked()
        // only from the reward callback, not on ad dismissal.
        isProcessing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isProcessing = false
            onUnlocked()
            dismiss()
        }
    }
}
