import SwiftUI

@main
struct ReactCam1App: App {
    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var usageTracker: UsageTracker
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must run before UsageTracker() reads its counter below -- existing installs had
        // unlimited free exports under the old mocked paywall, so this resets them to a fresh
        // count rather than either honoring a fake "Pro" flag or granting a permanent free unlock.
        Monetization.migrateLegacyUsageIfNeeded()
        _usageTracker = StateObject(wrappedValue: UsageTracker())
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchView()
                .environmentObject(purchaseManager)
                .environmentObject(usageTracker)
                .preferredColorScheme(.dark)
                // Single app-wide accent so every system-styled control (nav links, buttons,
                // pickers, toggles, alerts) matches one brand color throughout, instead of
                // falling back to the system default blue in some places and a hardcoded color
                // in others. Sourced from the AccentColor asset, which is set to the same light
                // blue as the app logo's background.
                .tint(.accentColor)
                .task { await purchaseManager.start() }
        }
        .onChange(of: scenePhase) { newPhase in
            // Picks up a refund/revocation that landed while the app was backgrounded.
            guard newPhase == .active else { return }
            Task { await purchaseManager.refreshEntitlements() }
        }
    }
}

/// How long the launch screen stays up before handing off to HomeView.
private let launchLoadDuration: Double = 1.0

struct AppLaunchView: View {
    @State private var isLaunching = true

    var body: some View {
        ZStack {
            HomeView()
                .opacity(isLaunching ? 0 : 1)

            if isLaunching {
                LaunchScreenView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + launchLoadDuration) {
                withAnimation(.easeOut(duration: 0.35)) {
                    isLaunching = false
                }
            }
        }
    }
}

private struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image("ReactCamLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: .blue.opacity(0.35), radius: 20)

                Text("ReactCam")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
        }
    }
}
