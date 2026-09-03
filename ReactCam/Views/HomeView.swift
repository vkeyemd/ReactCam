import SwiftUI

struct HomeView: View {
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var recordingSource: RecordingSource?
    @State private var showingImportError = false
    @State private var navigateToStudio = false

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
                            recordingSource = .cameraRollArchitectureWithRearCamera
                            navigateToStudio = true
                        } label: {
                            HomeActionRow(
                                icon: "camera.on.rectangle",
                                title: "Dual Camera",
                                subtitle: "Record with both cameras at once"
                            )
                        }

                        Button {
                            showingPhotoPicker = true
                        } label: {
                            HomeActionRow(
                                icon: "photo.on.rectangle",
                                title: "Import from Camera Roll",
                                subtitle: "Pick a video to react to"
                            )
                        }

                        Button {
                            showingFilePicker = true
                        } label: {
                            HomeActionRow(
                                icon: "folder",
                                title: "Import from Files",
                                subtitle: "Browse for an MP4"
                            )
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingPhotoPicker) {
                PHPickerView(
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
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
