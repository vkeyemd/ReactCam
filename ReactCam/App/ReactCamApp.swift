import SwiftUI

@main
struct ReactCam1App: App {
    var body: some Scene {
        WindowGroup {
            AppLaunchView()
                .preferredColorScheme(.dark)
        }
    }
}

/// How long the loading bar takes to fill before handing off to HomeView. Kept in one place so
/// the bar's animation and the actual transition it gates never drift out of sync -- the bar is
/// only a truthful "how much longer" indicator if it finishes exactly when the wait does.
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
    // Starts just above zero (rather than 0) so the bar visibly renders with a sliver of fill
    // immediately on appear, instead of a beat of looking empty/frozen before the animation
    // below has a chance to kick in.
    @State private var progress: Double = 0.05

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

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 160)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: launchLoadDuration)) {
                progress = 1.0
            }
        }
    }
}
