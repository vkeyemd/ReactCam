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
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
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
                    .scaleEffect(1.2)
            }
        }
    }
}
