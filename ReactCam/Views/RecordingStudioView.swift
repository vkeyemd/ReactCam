import SwiftUI
import AVFoundation
import Combine

struct RecordingStudioView: View {
    let source: RecordingSource

    @StateObject private var cameraManager = CameraManager()

    @State private var player: AVPlayer?
    @State private var firstFrame: UIImage?
    @State private var orientation: ExportOrientation = .portrait
    @State private var isRecording = false
    @State private var mergeInputs: MergeInputs?
    @State private var playerEndObserver: AnyCancellable?
    @State private var isVideoLoading = false
    @State private var showHeadphoneWarning = false
    @State private var hasAcknowledgedHeadphoneWarning = false
    @State private var recordingStartDate: Date?

    private var sourceLabel: String {
        switch source {
        case .importedVideo: return "Reacting to Video"
        case .cameraRollArchitectureWithRearCamera: return "Dual Camera"
        }
    }

    struct MergeInputs: Identifiable, Hashable {
        let id = UUID()
        let topURL: URL
        let bottomURL: URL
        let orientation: ExportOrientation
        let includeTopAudio: Bool
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            NavigationLink(
                destination: Group {
                    if let inputs = mergeInputs {
                        PreviewExportView(
                            topURL: inputs.topURL,
                            bottomURL: inputs.bottomURL,
                            orientation: inputs.orientation,
                            includeTopAudio: inputs.includeTopAudio
                        )
                    }
                },
                isActive: Binding(
                    get: { mergeInputs != nil },
                    set: { if !$0 { mergeInputs = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()

            VStack(spacing: 0) {
                RecordingStudioTopBar(
                    title: sourceLabel,
                    isRecording: isRecording,
                    recordingStartDate: recordingStartDate,
                    onBack: { }
                )

                Spacer(minLength: 8)

                VideoContainerLayout(
                    sourceVideoPreview: AnyView(primaryPreview),
                    cameraPreview: AnyView(
                        CameraPreviewView(previewLayer: cameraManager.frontPreviewLayer)
                    )
                )

                Spacer(minLength: 8)

                RecordingStudioBottomBar(
                    isRecording: isRecording,
                    onToggleRecord: toggleRecording,
                    onFlipCamera: {
                        if case .importedVideo = source {
                            cameraManager.flipReactionCamera()
                        }
                    },
                    showFlipCamera: source.importedURL != nil
                )
            }

            if isVideoLoading {
                ZStack {
                    Color.black.opacity(0.9).ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)

                        Text("Preparing Video...")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Getting things ready")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(white: 0.1))
                    )
                    .padding(.horizontal, 32)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear { setUp() }
        .onDisappear { tearDown() }
        .alert("Use Headphones for Best Audio", isPresented: $showHeadphoneWarning) {
            Button("Start Recording") {
                hasAcknowledgedHeadphoneWarning = true
                startRecording()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Headphone use is strongly encouraged in this mode to reduce sound artifacts in your final video.")
        }
    }

    @ViewBuilder
    private var primaryPreview: some View {
        switch source {
        case .importedVideo:
            Group {
                if let player {
                    PlayerView(player: player, videoGravity: .resizeAspectFill)
                        .opacity(isRecording ? 1 : 0)

                    if !isRecording, let image = firstFrame {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                } else {
                    Color.black
                }
            }

        case .cameraRollArchitectureWithRearCamera:
            CameraPreviewView(previewLayer: cameraManager.rearPreviewLayer)
        }
    }

    private func setUp() {
        AudioSessionManager.activate()
        orientation = .portrait
        isVideoLoading = false
        player = nil
        firstFrame = nil

        switch source {
        case .importedVideo(let url):
            isVideoLoading = true
            cameraManager.requestPermissionsAndStart(mode: .reactionToImportedVideo)

            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil)
                let image = cgImage != nil ? UIImage(cgImage: cgImage!) : nil

                let item = AVPlayerItem(asset: asset)
                let newPlayer = AVPlayer(playerItem: item)

                DispatchQueue.main.async {
                    self.firstFrame = image
                    self.player = newPlayer
                    self.playerEndObserver = NotificationCenter.default
                        .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
                        .sink { _ in self.stopRecording() }
                    self.isVideoLoading = false
                }
            }

        case .cameraRollArchitectureWithRearCamera:
            isVideoLoading = false
            cameraManager.requestPermissionsAndStart(mode: .rearPrimaryWithFrontOverlay)
        }
    }

    private func tearDown() {
        isVideoLoading = false
        player?.pause()
        player = nil
        firstFrame = nil
        cameraManager.stopSession()
        playerEndObserver?.cancel()
        playerEndObserver = nil
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else if case .importedVideo = source, !hasAcknowledgedHeadphoneWarning {
            // Reacting to a played-back video risks the source audio bleeding into the mic
            // recording (and doubling up if we also keep the source's own audio track), so warn
            // once per session before the very first take in this mode.
            showHeadphoneWarning = true
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        recordingStartDate = Date()
        let currentOrientation = orientation

        switch source {
        case .importedVideo(let sourceURL):
            // Only keep the reacted-to video's own audio track in the final export if headphones
            // were actually in use for this take -- otherwise its audio already bled into the mic
            // recording via the speaker, and re-adding it separately would double it up.
            let includeTopAudio = AudioSessionManager.isUsingHeadphones

            cameraManager.startRecording { reactionURL, primaryURL in
                guard let reactionURL else { return }
                let finalTopURL = primaryURL ?? sourceURL
                finishRecording(
                    topURL: finalTopURL,
                    bottomURL: reactionURL,
                    orientation: currentOrientation,
                    includeTopAudio: includeTopAudio,
                    sourceLabel: "Imported Video"
                )
            }

            player?.seek(to: .zero)
            player?.play()

        case .cameraRollArchitectureWithRearCamera:
            // Both feeds are live camera captures on the same device, not played-back audio, so
            // there's no bleed-through/doubling risk -- always keep the rear camera's own audio.
            cameraManager.startRecording { reactionURL, primaryURL in
                guard let reactionURL, let primaryURL else { return }
                finishRecording(
                    topURL: primaryURL,
                    bottomURL: reactionURL,
                    orientation: currentOrientation,
                    includeTopAudio: true,
                    sourceLabel: "Dual Camera"
                )
            }
        }
    }

    /// Every time a recording finishes, save it as a Project -- durable copies of the raw source
    /// clips the user can come back to and re-export as often as they like (e.g. once in portrait,
    /// again in landscape) -- rather than relying on the OS temp files CameraManager/the pickers
    /// hand back, which aren't guaranteed to survive between launches.
    private func finishRecording(
        topURL: URL,
        bottomURL: URL,
        orientation: ExportOrientation,
        includeTopAudio: Bool,
        sourceLabel: String
    ) {
        let project = ProjectStore.shared.createProject(
            topSourceURL: topURL,
            bottomSourceURL: bottomURL,
            sourceLabel: sourceLabel,
            orientation: orientation,
            includeTopAudio: includeTopAudio
        )

        if let project {
            mergeInputs = MergeInputs(
                topURL: ProjectStore.shared.topURL(for: project),
                bottomURL: ProjectStore.shared.bottomURL(for: project),
                orientation: orientation,
                includeTopAudio: includeTopAudio
            )
        } else {
            // Saving the project failed (e.g. disk space) -- still let the user edit and export
            // this take from the original (temp) URLs rather than losing the recording outright.
            mergeInputs = MergeInputs(
                topURL: topURL,
                bottomURL: bottomURL,
                orientation: orientation,
                includeTopAudio: includeTopAudio
            )
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingStartDate = nil
        player?.pause()
        cameraManager.stopRecording()
    }
}

private struct RecordingStudioTopBar: View {
    let title: String
    let isRecording: Bool
    let recordingStartDate: Date?
    let onBack: () -> Void
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        HStack {
            Button {
                presentationMode.wrappedValue.dismiss()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .padding()
            }

            Spacer()

            if isRecording, let recordingStartDate {
                RecordingTimerLabel(startDate: recordingStartDate)
            } else {
                Text(title)
                    .font(.headline)
                    .bold()
                    .foregroundColor(.white)
            }

            Spacer()

            Image(systemName: "chevron.left")
                .opacity(0)
                .padding()
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
    }
}

/// Live elapsed-time readout ("0:07", "1:23"...) shown in place of the static title while
/// recording, so there's some feedback on clip length before you stop.
private struct RecordingTimerLabel: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1.0)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(startDate)))
            let minutes = elapsed / 60
            let seconds = elapsed % 60

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)

                Text(String(format: "%d:%02d", minutes, seconds))
                    .font(.headline.monospacedDigit())
                    .bold()
                    .foregroundColor(.white)
            }
        }
    }
}

private struct RecordingStudioBottomBar: View {
    let isRecording: Bool
    let onToggleRecord: () -> Void
    let onFlipCamera: () -> Void
    let showFlipCamera: Bool

    var body: some View {
        ZStack {
            HStack {
                Spacer()

                Button(action: onToggleRecord) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 72, height: 72)

                        if isRecording {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red)
                                .frame(width: 28, height: 28)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 60, height: 60)
                        }
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)

                Spacer()
            }

            if !isRecording && showFlipCamera {
                HStack {
                    Spacer()

                    Button(action: onFlipCamera) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title2)
                            .padding()
                            .background(Color(white: 0.2))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 24)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(height: 100)
        .padding(.bottom, 16)
    }
}

private struct VideoContainerLayout: View {
    let sourceVideoPreview: AnyView
    let cameraPreview: AnyView

    var body: some View {
        GeometryReader { geo in
            let containerSize = fittedSize(in: geo.size)

            ZStack(alignment: .topLeading) {
                sourceVideoPreview
                    .frame(width: containerSize.width, height: containerSize.height)
                    .clipped()

                let pipWidth = containerSize.width * 0.25
                let pipHeight = pipWidth * (16.0 / 9.0)
                let paddingX = containerSize.width * 0.05
                let paddingY = containerSize.height * 0.05

                cameraPreview
                    .frame(width: pipWidth, height: pipHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                    )
                    .shadow(radius: 12)
                    .offset(
                        x: containerSize.width - pipWidth - paddingX,
                        y: containerSize.height - pipHeight - paddingY
                    )
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .background(Color.black)
            .cornerRadius(12)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        let targetRatio = ExportOrientation.portrait.previewAspectRatio
        let availableRatio = available.width / available.height

        if availableRatio > targetRatio {
            let height = available.height
            return CGSize(width: height * targetRatio, height: height)
        } else {
            let width = available.width
            return CGSize(width: width, height: width / targetRatio)
        }
    }
}
