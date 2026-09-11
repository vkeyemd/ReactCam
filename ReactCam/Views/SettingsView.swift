import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var paywallReason: Monetization.PaywallReason?

    var body: some View {
        List {
            Section("Purchases") {
                if purchaseManager.isPro {
                    LabeledContent("ReactCam Pro", value: "Unlocked")
                } else {
                    Button("Unlock ReactCam Pro") {
                        paywallReason = .manualUpgrade
                    }
                }

                Button {
                    Task { await purchaseManager.restorePurchases() }
                } label: {
                    if purchaseManager.isRestoring {
                        ProgressView()
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .disabled(purchaseManager.isRestoring)
            }

            Section {
                Link("Privacy Policy", destination: URL(string: "https://vkeyemd.github.io/ReactCam/privacy.html")!)
            } footer: {
                Text("ReactCam collects no data. Your videos never leave your device.")
            }
        }
        .navigationTitle("Settings")
        .sheet(item: $paywallReason) { reason in
            PaywallView(reason: reason) {}
                .environmentObject(purchaseManager)
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
                    dismissButton: .default(Text("OK"))
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
}
