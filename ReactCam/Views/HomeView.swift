import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var usageTracker: UsageTracker
    @ObservedObject private var projectStore = ProjectStore.shared

    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingImportSourceChooser = false
    @State private var recordingSource: RecordingSource?
    @State private var showingImportError = false
    @State private var navigateToStudio = false
    @State private var navigateToProjects = false
    @State private var navigateToSettings = false
    @State private var paywallReason: Monetization.PaywallReason?
    @State private var pendingUnlockedAction: (() -> Void)?

    /// Gate for anything that would create a new saved Project -- Dual Camera and Import Video
    /// both end in RecordingStudioView.finishRecording(), which saves a Project automatically the
    /// instant a recording finishes (there's no separate "save" step to gate instead). Checking
    /// here, before the camera/picker even opens, means hitting the cap never wastes a recording
    /// or import the user already sat through.
    private func beginNewRecording(_ action: @escaping () -> Void) {
        let canProceed = usageTracker.canCreateProject(
            currentProjectCount: projectStore.projects.count,
            isPro: purchaseManager.isPro
        )
        if canProceed {
            action()
        } else {
            pendingUnlockedAction = action
            paywallReason = .projectLimitReached
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                NavigationLink(
                    destination: Group {
                        if let source = recordingSource {
                            RecordingStudioView(source: source)
                        }
                    },
                    isActive: $navigateToStudio
                ) {
                    EmptyView()
                }
                .hidden()

                NavigationLink(destination: ProjectsView(), isActive: $navigateToProjects) {
                    EmptyView()
                }
                .hidden()

                NavigationLink(destination: SettingsView(), isActive: $navigateToSettings) {
                    EmptyView()
                }
                .hidden()

                VStack(spacing: 32) {
                    Spacer()

                    VStack(spacing: 8) {
                        Image("ReactCamLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .blue.opacity(0.3), radius: 15)
                            .padding(.bottom, 8)

                        Text("ReactCam")
                            .font(.largeTitle.bold())

                        Text("Capture your kid's reaction to anything.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(spacing: 16) {
                        Button {
                            beginNewRecording {
                                recordingSource = .cameraRollArchitectureWithRearCamera
                                navigateToStudio = true
                            }
                        } label: {
                            HomeActionRow(
                                icon: "camera.on.rectangle",
                                title: "Dual Camera",
                                subtitle: "Record with both cameras at once"
                            )
                        }

                        Button {
                            beginNewRecording {
                                showingImportSourceChooser = true
                            }
                        } label: {
                            HomeActionRow(
                                icon: "square.and.arrow.down",
                                title: "Import Video",
                                subtitle: "From Camera Roll or Files"
                            )
                        }
                        .confirmationDialog("Import Video", isPresented: $showingImportSourceChooser, titleVisibility: .visible) {
                            Button("Camera Roll") {
                                showingPhotoPicker = true
                            }
                            Button("Files") {
                                showingFilePicker = true
                            }
                            Button("Cancel", role: .cancel) {}
                        }

                        Button {
                            navigateToProjects = true
                        } label: {
                            HomeActionRow(
                                icon: "folder",
                                title: "Projects",
                                subtitle: "Re-export past recordings"
                            )
                        }
                    }
                    .padding(.horizontal)

                    PrivacyFooter()
                        .padding(.horizontal)

                    Spacer()
                }
                .padding()

                // Settings lives here rather than as a fourth row in the main action list, so it
                // doesn't compete for attention with Dual Camera / Import / Projects.
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            navigateToSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Settings")
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoImportSheet(
                    onPicked: { url in
                        showingPhotoPicker = false
                        recordingSource = .importedVideo(url: url)
                        navigateToStudio = true
                    },
                    onCancel: {
                        showingPhotoPicker = false
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPickerView(
                    onPicked: { url in
                        showingFilePicker = false
                        recordingSource = .importedVideo(url: url)
                        navigateToStudio = true
                    },
                    onCancel: {
                        showingFilePicker = false
                    }
                )
                .ignoresSafeArea()
            }
            .alert("Couldn't import that video", isPresented: $showingImportError) {
                Button("OK", role: .cancel) {}
            }
            .sheet(item: $paywallReason) { reason in
                PaywallView(reason: reason) {
                    pendingUnlockedAction?()
                    pendingUnlockedAction = nil
                }
                .environmentObject(purchaseManager)
            }
            .onReceive(NotificationCenter.default.publisher(for: .returnToHome)) { _ in
                // Resetting these tears down whatever's pushed on top, however deep -- Recording
                // Studio -> Editor, or Projects -> Editor.
                navigateToStudio = false
                navigateToProjects = false
                navigateToSettings = false
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

/// Hosts PHPickerView plus its own loading overlay, both inside the same sheet. Showing the
/// overlay as a sibling *inside* the sheet -- rather than on HomeView underneath -- means it's
/// guaranteed visible for the load's entire real duration: the sheet only dismisses (via
/// onPicked/onCancel) once the load is done, so there's no race with a dismiss animation that
/// could finish before a fast local load does.
private struct PhotoImportSheet: View {
    let onPicked: (URL) -> Void
    let onCancel: () -> Void
    @State private var isLoading = false

    var body: some View {
        ZStack {
            PHPickerView(
                onPicked: onPicked,
                onCancel: onCancel,
                onImportStart: { isLoading = true }
            )

            if isLoading {
                ImportProgressOverlay()
            }
        }
    }
}

/// Shown while a picked video is being loaded out of the Photos library (potentially slow for
/// iCloud-backed originals) and copied into our own sandbox, so the screen doesn't just sit
/// blank between the picker sheet dismissing and the editor appearing.
private struct ImportProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 16) {
                // Circular, not linear -- SwiftUI's linear ProgressView style doesn't actually
                // animate on iOS when there's no value (it just renders a static bar). Circular
                // is what RecordingStudioView's own "Preparing Video..." spinner already uses,
                // and it visibly spins.
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text("Importing Video…")
                    .font(.headline)

                Text("This can take a moment for larger videos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 32)
        }
    }
}

/// Reassures the user up front that this app has no server component -- everything happens
/// on-device -- and gives them somewhere to verify that claim in writing.
private struct PrivacyFooter: View {
    var body: some View {
        VStack(spacing: 6) {
            Label("Private by design — your videos never leave your device", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link("Privacy Policy", destination: URL(string: "https://vkeyemd.github.io/ReactCam/privacy.html")!)
                .font(.caption2)
        }
    }
}

private struct HomeActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var disabled: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(disabled ? 0.5 : 1.0)
        .foregroundStyle(.primary)
    }
}
