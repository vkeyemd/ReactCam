import SwiftUI
import AVFoundation
import Photos
import Combine

/// A helper view that encapsulates a transformed interactive player layer.
/// This prevents the Swift compiler from choking on complex chained expressions inside the main view.
struct InteractivePlayerLayer<G: Gesture>: View {
    let player: AVPlayer
    let size: CGSize
    let transform: CGAffineTransform
    let gesture: G

    var body: some View {
        PlayerView(player: player, videoGravity: .resizeAspectFill)
            .frame(width: size.width, height: size.height)
            .projectionEffect(ProjectionTransform(transform))
            .gesture(gesture)
    }
}

/// One slider row in the Sound Mixer: an icon that flips to a mute glyph at zero volume, a
/// label, the slider itself, and a live percentage readout.
private struct AudioMixerRow: View {
    let icon: String
    let label: String
    @Binding var volume: Float

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: volume <= 0.001 ? "speaker.slash.fill" : icon)
                .frame(width: 20)
                .foregroundStyle(volume <= 0.001 ? .red : .white)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 90, alignment: .leading)

            Slider(value: $volume, in: 0...1)
                .tint(.accentColor)

            Text("\(Int(volume * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

struct PreviewExportView: View {
    let topURL: URL
    let bottomURL: URL
    let includeTopAudio: Bool
    @State private var orientation: ExportOrientation = .portrait

    @AppStorage("reactcam.exportCount") private var exportCount = 0
    @AppStorage("reactcam.isProUnlocked") private var isProUnlocked = false

    // Layout configuration states
    @State private var topLayer = VideoLayoutState(scale: 1.0, offset: .zero, isTopMost: false)
    @State private var bottomLayer = VideoLayoutState(scale: 1.0, offset: .zero, isTopMost: true)

    // Layout role state: when true, the videos switch roles (top track becomes overlay, bottom track becomes background)
    @State private var isRolesSwapped = false

    // Gesture temp active states
    @State private var activeTopDragOffset: CGSize = .zero
    @State private var activeTopScale: CGFloat = 1.0
    @State private var activeBottomDragOffset: CGSize = .zero
    @State private var activeBottomScale: CGFloat = 1.0

    // Asset track info states
    @State private var topTrackInfo: TrackInfo?
    @State private var bottomTrackInfo: TrackInfo?
    @State private var isMetadataLoaded = false

    // Playback sync manager
    @StateObject private var syncController: PlayerSyncController

    // UI & Merge State
    @State private var mergeState: MergeState = .editing
    @State private var showingPaywall = false
    @State private var showingShareSheet = false
    @State private var saveErrorMessage: String?
    @State private var didSaveSuccessfully = false
    @State private var isSaving = false
    @State private var exportedVideoURL: URL?

    // Warning indicators
    @State private var showOffCanvasWarning = false

    // Sound mixer state
    @State private var topAudioVolume: Float = 1.0
    @State private var bottomAudioVolume: Float = 1.0
    @State private var topAudioAvailable = false
    @State private var bottomAudioAvailable = false

    enum MergeState {
        case editing
        case merging(progress: Float)
        case ready(URL)
        case failed(String)
    }

    struct TrackInfo {
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        
        var isPortrait: Bool {
            preferredTransform.a == 0 && abs(preferredTransform.b) == 1
        }
        var actualSize: CGSize {
            isPortrait ? CGSize(width: naturalSize.height, height: naturalSize.width) : naturalSize
        }
    }

    init(topURL: URL, bottomURL: URL, orientation: ExportOrientation, includeTopAudio: Bool = true) {
        self.topURL = topURL
        self.bottomURL = bottomURL
        self.includeTopAudio = includeTopAudio
        self._orientation = State(initialValue: orientation)
        self._syncController = StateObject(wrappedValue: PlayerSyncController(topURL: topURL, bottomURL: bottomURL))
    }

    private var isFirstExportFree: Bool { exportCount == 0 }

    /// Fixed reference frame the drag gesture measures against — the render-size canvas
    /// container, captured BEFORE the display .scaleEffect and outside any per-layer
    /// projectionEffect. See usage at the canvas container and in makeGesture(for:).
    static let canvasCoordinateSpace = "reactcam.previewCanvas"

    var body: some View {
        VStack(spacing: 12) {
            if isMetadataLoaded {
                GeometryReader { geo in
                    let renderSize = orientation.renderSize
                    let viewSize = fittedSize(in: geo.size, for: renderSize)

                    ZStack {
                        // 1. Black Canvas Frame Container
                        ZStack(alignment: .topLeading) {
                            Color.black // Base black layer

                            // Render layers in respect of z-index
                            let layers = orderedLayers()
                            ForEach(layers, id: \.id) { item in
                                if item.id == .top {
                                    if let player = syncController.topPlayer, let info = topTrackInfo {
                                        let transform = calculateFullTransform(for: .top, info: info, renderSize: renderSize)
                                        let gesture = makeGesture(for: .top)
                                        InteractivePlayerLayer(
                                            player: player,
                                            size: info.actualSize,
                                            transform: transform,
                                            gesture: gesture
                                        )
                                    }
                                } else {
                                    if let player = syncController.bottomPlayer, let info = bottomTrackInfo {
                                        let transform = calculateFullTransform(for: .bottom, info: info, renderSize: renderSize)
                                        let gesture = makeGesture(for: .bottom)
                                        InteractivePlayerLayer(
                                            player: player,
                                            size: info.actualSize,
                                            transform: transform,
                                            gesture: gesture
                                        )
                                    }
                                }
                            }
                        }
                        .frame(width: renderSize.width, height: renderSize.height)
                        // Named BEFORE .scaleEffect so drag translations are always measured in
                        // fixed canvas/render-size pixel units, independent of the on-screen
                        // display scale and of each layer's own projectionEffect (which bakes in
                        // baseScale/mirror/zoom and would otherwise distort gesture units).
                        .coordinateSpace(name: PreviewExportView.canvasCoordinateSpace)
                        .clipped() // Hard border clipping to chosen canvas dims
                        .scaleEffect(viewSize.width / renderSize.width, anchor: .center)
                        .frame(width: viewSize.width, height: viewSize.height)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(radius: 12)
                        
                        // 2. Play/Pause overlay toggle
                        Button {
                            syncController.toggle()
                        } label: {
                            Image(systemName: syncController.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(radius: 4)
                        }
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .onChange(of: geo.size) { _ in
                        checkOffCanvasLimits(renderSize: renderSize)
                    }
                }
                .aspectRatio(orientation.previewAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.05))
                .cornerRadius(16)
                .padding(.horizontal)
            } else {
                // Loading spinner while track metadata is parsed
                VStack {
                    Spacer()
                    ProgressView("Analyzing videos...")
                        .tint(.white)
                        .foregroundStyle(.white)
                    Spacer()
                }
                .frame(height: 320)
            }

            // Warning Banner for Off-Canvas elements
            if showOffCanvasWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Warning: One of your videos is fully outside the canvas bounds!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Restore") {
                        resetToDefault()
                    }
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.orange)
                }
                .padding(.horizontal)
                .transition(.opacity)
            }

            // Live Control Panel
            if case .editing = mergeState {
                VStack(spacing: 12) {
                    // Orientation Picker & Layer Z-Index controls
                    HStack(spacing: 16) {
                        // Orientation Selection
                        Picker("Canvas", selection: $orientation) {
                            ForEach(ExportOrientation.allCases) { orient in
                                Text(orient.displayName).tag(orient)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: orientation) { _ in
                            // Reset transforms on orientation change to guarantee instant visual correctness
                            resetToDefault()
                        }

                        // Toggle role order button (makes overlay and background switch places)
                        Button(action: toggleRoles) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.2.squarepath")
                                Text("Toggle")
                            }
                            .font(.subheadline)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color(white: 0.15))
                            .cornerRadius(8)
                            .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal)

                    // Reset buttons
                    HStack {
                        Button(action: resetToDefault) {
                            Label("Reset Layout", systemImage: "arrow.counterclockwise")
                                .font(.subheadline)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(Color.red.opacity(0.15))
                                .cornerRadius(8)
                                .foregroundStyle(.red)
                        }

                        Spacer()

                        Text("Drag & Pinch Layers Freeform")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    .padding(.horizontal)

                    if topAudioAvailable || bottomAudioAvailable {
                        Divider()
                            .background(Color(white: 0.2))

                        soundMixer
                    }

                    Divider()
                        .background(Color(white: 0.2))
                }
            }

            // Export States & Final Triggers
            switch mergeState {
            case .editing:
                exportControls

            case .merging(let progress):
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)

                    Text("Processing & Merging Layout (\(Int(progress * 100))%)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()

            case .ready:
                exportControls

            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Button("Try Again") {
                        mergeState = .editing
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                }
                .padding()
            }

            Spacer()
        }
        .padding(.top)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Layout & Export")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTrackInfo()
        }
        .onDisappear {
            syncController.deinitPlayers()
        }
        .onChange(of: topAudioVolume) { newValue in
            syncController.topPlayer?.volume = newValue
        }
        .onChange(of: bottomAudioVolume) { newValue in
            syncController.bottomPlayer?.volume = newValue
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView {
                isProUnlocked = true
                performExport()
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedVideoURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Couldn't save video", isPresented: .constant(saveErrorMessage != nil), presenting: saveErrorMessage) { _ in
            Button("OK") { saveErrorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var soundMixer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sound Mixer")
                .font(.caption)
                .foregroundStyle(.gray)
                .padding(.horizontal)

            if topAudioAvailable {
                AudioMixerRow(icon: "film", label: "Video Audio", volume: $topAudioVolume)
                    .padding(.horizontal)
            }

            if bottomAudioAvailable {
                AudioMixerRow(icon: "mic.fill", label: "Your Voice", volume: $bottomAudioVolume)
                    .padding(.horizontal)
            }

            if includeTopAudio == false {
                Text("Video audio isn't included because headphones weren't in use during recording.")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .padding(.horizontal)
            }
        }
    }

    private var exportControls: some View {
        VStack(spacing: 12) {
            Button {
                handleExportTap()
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: didSaveSuccessfully ? .white : .black))
                    }

                    Text(exportButtonTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    exportButtonBackgroundColor,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .foregroundStyle(exportButtonTextColor)
            }
            .disabled(isSaving || didSaveSuccessfully)

            if exportedVideoURL != nil {
                Button {
                    showingShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
            }

            // A clear next step once the export has actually landed in Photos, instead of
            // leaving the user to find their own way back out via the nav bar.
            if didSaveSuccessfully {
                Button {
                    NotificationCenter.default.post(name: .returnToHome, object: nil)
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal)
    }

    private var exportButtonTitle: String {
        if didSaveSuccessfully {
            return "Saved!"
        }

        if isSaving {
            return "Saving..."
        }

        if exportedVideoURL != nil {
            return "Save to Camera Roll"
        }

        return isFirstExportFree || isProUnlocked ? "Export & Save to Photos" : "Unlock Pro & Export"
    }

    private var exportButtonBackgroundColor: Color {
        if didSaveSuccessfully {
            return .green
        }

        return .accentColor
    }

    private var exportButtonTextColor: Color {
        if didSaveSuccessfully {
            return .white
        }

        return .black
    }

    // Hit Testing & Simultaneous Drag/Pinch Gestures
    private func makeGesture(for layerType: LayerType) -> some Gesture {
        // Measured in the fixed canvas coordinate space (named on the render-size container,
        // above .scaleEffect and above each layer's own projectionEffect) so the reported
        // translation is always in true canvas/export pixel units — the same units
        // topLayer.offset / bottomLayer.offset are stored in and VideoMerger.calculateTransform
        // expects. Using the default .local space here would instead measure translation through
        // this layer's own projectionEffect (which bakes in baseScale, mirror, and the live pinch
        // scale), so the stored offset would drift from true canvas pixels whenever a layer's
        // baseScale isn't ~1.0 — most visibly in landscape's half-width side-by-side targetRects,
        // which is why the exported video ends up shifted from the canvas preview there.
        let drag = DragGesture(minimumDistance: 0, coordinateSpace: .named(PreviewExportView.canvasCoordinateSpace))
            .onChanged { value in
                // Intercept touch: bring the touched layer to top-most layer automatically!
                bringToFront(layerType)

                let pixelTranslation = value.translation

                if layerType == .top {
                    activeTopDragOffset = pixelTranslation
                } else {
                    activeBottomDragOffset = pixelTranslation
                }
                
                checkOffCanvasLimits(renderSize: orientation.renderSize)
            }
            .onEnded { value in
                let pixelTranslation = value.translation

                if layerType == .top {
                    topLayer.offset.width += pixelTranslation.width
                    topLayer.offset.height += pixelTranslation.height
                    activeTopDragOffset = .zero
                } else {
                    bottomLayer.offset.width += pixelTranslation.width
                    bottomLayer.offset.height += pixelTranslation.height
                    activeBottomDragOffset = .zero
                }

                checkOffCanvasLimits(renderSize: orientation.renderSize)
            }

        let pinch = MagnificationGesture()
            .onChanged { value in
                bringToFront(layerType)
                if layerType == .top {
                    activeTopScale = value
                } else {
                    activeBottomScale = value
                }
            }
            .onEnded { value in
                if layerType == .top {
                    topLayer.scale *= value
                    activeTopScale = 1.0
                } else {
                    bottomLayer.scale *= value
                    activeBottomScale = 1.0
                }
                checkOffCanvasLimits(renderSize: orientation.renderSize)
            }

        return SimultaneousGesture(drag, pinch)
    }

    enum LayerType {
        case top
        case bottom
    }

    struct LayerOrderItem {
        let id: LayerType
        let isTopMost: Bool
    }

    private func orderedLayers() -> [LayerOrderItem] {
        if bottomLayer.isTopMost {
            return [
                LayerOrderItem(id: .top, isTopMost: false),
                LayerOrderItem(id: .bottom, isTopMost: true)
            ]
        } else {
            return [
                LayerOrderItem(id: .bottom, isTopMost: false),
                LayerOrderItem(id: .top, isTopMost: true)
            ]
        }
    }

    private func bringToFront(_ layer: LayerType) {
        if layer == .top && !topLayer.isTopMost {
            topLayer.isTopMost = true
            bottomLayer.isTopMost = false
        } else if layer == .bottom && !bottomLayer.isTopMost {
            bottomLayer.isTopMost = true
            topLayer.isTopMost = false
        }
    }

    private func toggleRoles() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            isRolesSwapped.toggle()
            
            // Swap positions, but also reset manual offsets/scales to ensure clean defaults
            topLayer = VideoLayoutState(scale: 1.0, offset: .zero, isTopMost: isRolesSwapped)
            bottomLayer = VideoLayoutState(scale: 1.0, offset: .zero, isTopMost: !isRolesSwapped)
            
            activeTopDragOffset = .zero
            activeTopScale = 1.0
            activeBottomDragOffset = .zero
            activeBottomScale = 1.0
            showOffCanvasWarning = false
        }
    }

    private func resetToDefault() {
        isRolesSwapped = false
        topLayer = VideoLayoutState(scale: 1.0, offset: .zero, isTopMost: false)
        bottomLayer = VideoLayoutState(scale: 1.0, offset: .zero, isTopMost: true)
        activeTopDragOffset = .zero
        activeTopScale = 1.0
        activeBottomDragOffset = .zero
        activeBottomScale = 1.0
        showOffCanvasWarning = false
    }

    private func handleExportTap() {
        if exportedVideoURL != nil {
            performExport()
        } else {
            if isFirstExportFree || isProUnlocked {
                runMergeAndSave()
            } else {
                showingPaywall = true
            }
        }
    }

    private func loadTrackInfo() async {
        let topAsset = AVAsset(url: topURL)
        let bottomAsset = AVAsset(url: bottomURL)

        guard let topTrack = try? await topAsset.loadTracks(withMediaType: .video).first,
              let bottomTrack = try? await bottomAsset.loadTracks(withMediaType: .video).first else {
            return
        }

        let topSize = try? await topTrack.load(.naturalSize)
        let topTransform = try? await topTrack.load(.preferredTransform)

        let bottomSize = try? await bottomTrack.load(.naturalSize)
        let bottomTransform = try? await bottomTrack.load(.preferredTransform)

        let topHasAudioTrack = ((try? await topAsset.loadTracks(withMediaType: .audio)) ?? []).isEmpty == false
        let bottomHasAudioTrack = ((try? await bottomAsset.loadTracks(withMediaType: .audio)) ?? []).isEmpty == false

        if let topSize, let topTransform, let bottomSize, let bottomTransform {
            await MainActor.run {
                self.topTrackInfo = TrackInfo(naturalSize: topSize, preferredTransform: topTransform)
                self.bottomTrackInfo = TrackInfo(naturalSize: bottomSize, preferredTransform: bottomTransform)

                // Infer canvas orientation: portrait if height >= width of background asset
                let isTopPortrait = (topTransform.a == 0 && abs(topTransform.b) == 1)
                let actualWidth = isTopPortrait ? topSize.height : topSize.width
                let actualHeight = isTopPortrait ? topSize.width : topSize.height

                self.orientation = (actualHeight >= actualWidth) ? .portrait : .landscape
                self.isMetadataLoaded = true
                self.resetToDefault()

                // The mixer only controls audio that will actually end up in the export -- top
                // audio is only ever kept there when includeTopAudio allowed it in the first place.
                self.topAudioAvailable = topHasAudioTrack && self.includeTopAudio
                self.bottomAudioAvailable = bottomHasAudioTrack

                // Mirror the export's audio composition during live preview too, so what you hear
                // while editing matches what ends up in the final file.
                self.syncController.topPlayer?.volume = self.topAudioAvailable ? self.topAudioVolume : 0
                self.syncController.bottomPlayer?.volume = self.bottomAudioVolume

                // Play synched streams
                self.syncController.play()
            }
        }
    }

    // Runs composition & rendering
    private func runMergeAndSave() {
        mergeState = .merging(progress: 0.0)
        syncController.pause()

        VideoMerger.merge(
            topURL: topURL,
            bottomURL: bottomURL,
            orientation: orientation,
            topLayout: topLayer,
            bottomLayout: bottomLayer,
            isRolesSwapped: isRolesSwapped,
            includeTopAudio: includeTopAudio,
            topAudioVolume: topAudioVolume,
            bottomAudioVolume: bottomAudioVolume,
            progress: { value in
                mergeState = .merging(progress: value)
            },
            completion: { result in
                switch result {
                case .success(let url):
                    exportedVideoURL = url
                    mergeState = .ready(url)
                    performExport() // Trigger Photo Library write once compiled successfully

                case .failure(let error):
                    mergeState = .failed(error.localizedDescription)
                }
            }
        )
    }

    private func performExport() {
        guard let url = exportedVideoURL else { return }

        isSaving = true
        didSaveSuccessfully = false

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    isSaving = false
                    saveErrorMessage = "Allow Photos access in Settings to save your video."
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    isSaving = false

                    if success {
                        exportCount += 1
                        didSaveSuccessfully = true
                    } else {
                        didSaveSuccessfully = false
                        saveErrorMessage = error?.localizedDescription ?? "Something went wrong saving your video."
                    }
                }
            }
        }
    }

    // Helper math functions mapping view coordinates <-> video canvas coordinates
    private func fittedSize(in available: CGSize, for canvasSize: CGSize) -> CGSize {
        let targetRatio = canvasSize.width / canvasSize.height
        let availableRatio = available.width / available.height

        if availableRatio > targetRatio {
            let height = available.height
            return CGSize(width: height * targetRatio, height: height)
        } else {
            let width = available.width
            return CGSize(width: width, height: width / targetRatio)
        }
    }

    private func calculateFullTransform(for layer: LayerType, info: TrackInfo, renderSize: CGSize) -> CGAffineTransform {
        let role: VideoMerger.MergerLayerType = (layer == .top) ? (isRolesSwapped ? .bottom : .top) : (isRolesSwapped ? .top : .bottom)
        let targetRect = VideoMerger.targetRect(for: role, orientation: orientation)
        let mirror = (layer == .bottom) // reaction overlay is mirrored
        let scale: CGFloat
        let offset: CGSize

        if layer == .top {
            scale = topLayer.scale * (activeTopScale != 1.0 ? activeTopScale : 1.0)
            offset = CGSize(
                width: topLayer.offset.width + activeTopDragOffset.width,
                height: topLayer.offset.height + activeTopDragOffset.height
            )
        } else {
            scale = bottomLayer.scale * (activeBottomScale != 1.0 ? activeBottomScale : 1.0)
            offset = CGSize(
                width: bottomLayer.offset.width + activeBottomDragOffset.width,
                height: bottomLayer.offset.height + activeBottomDragOffset.height
            )
        }

        // PREVIEW PATH: To prevent double rotation, pass info.actualSize (upright bounds) with .identity preferredTransform.
        return VideoMerger.calculateTransform(
            naturalSize: info.actualSize,
            preferredTransform: .identity,
            targetRect: targetRect,
            mirrorHorizontally: mirror,
            scale: scale,
            offset: offset
        )
    }

    // Warning detection: is a layer fully off-screen?
    private func checkOffCanvasLimits(renderSize: CGSize) {
        let canvasRect = CGRect(origin: .zero, size: renderSize)

        let topRole: VideoMerger.MergerLayerType = isRolesSwapped ? .bottom : .top
        let bottomRole: VideoMerger.MergerLayerType = isRolesSwapped ? .top : .bottom

        // Validate Background Layer
        let topScale = topLayer.scale * activeTopScale
        let topOffset = CGSize(
            width: topLayer.offset.width + activeTopDragOffset.width,
            height: topLayer.offset.height + activeTopDragOffset.height
        )
        let topTarget = VideoMerger.targetRect(for: topRole, orientation: orientation)
        let topFullWidth = topTarget.width * topScale
        let topFullHeight = topTarget.height * topScale
        let topRect = CGRect(
            x: topTarget.origin.x + (topTarget.width - topFullWidth) / 2.0 + topOffset.width,
            y: topTarget.origin.y + (topTarget.height - topFullHeight) / 2.0 + topOffset.height,
            width: topFullWidth,
            height: topFullHeight
        )

        // Validate Overlay Layer
        let bottomScale = bottomLayer.scale * activeBottomScale
        let bottomOffset = CGSize(
            width: bottomLayer.offset.width + activeBottomDragOffset.width,
            height: bottomLayer.offset.height + activeBottomDragOffset.height
        )
        let bottomTarget = VideoMerger.targetRect(for: bottomRole, orientation: orientation)
        let bottomFullWidth = bottomTarget.width * bottomScale
        let bottomFullHeight = bottomTarget.height * bottomScale
        let bottomRect = CGRect(
            x: bottomTarget.origin.x + (bottomTarget.width - bottomFullWidth) / 2.0 + bottomOffset.width,
            y: bottomTarget.origin.y + (bottomTarget.height - bottomFullHeight) / 2.0 + bottomOffset.height,
            width: bottomFullWidth,
            height: bottomFullHeight
        )

        let topIntersects = canvasRect.intersects(topRect)
        let bottomIntersects = canvasRect.intersects(bottomRect)

        withAnimation(.easeInOut) {
            showOffCanvasWarning = !topIntersects || !bottomIntersects
        }
    }
}

/// Helper coordinator ensuring both live players execute play, pause, seek and loop operations
/// simultaneously to stay perfectly synced during freeform preview manipulations.
class PlayerSyncController: ObservableObject {
    var topPlayer: AVPlayer?
    var bottomPlayer: AVPlayer?

    @Published var isPlaying = false
    private var cancellables = Set<AnyCancellable>()

    init(topURL: URL, bottomURL: URL) {
        let topItem = AVPlayerItem(url: topURL)
        let bottomItem = AVPlayerItem(url: bottomURL)

        self.topPlayer = AVPlayer(playerItem: topItem)
        self.bottomPlayer = AVPlayer(playerItem: bottomItem)

        // Loop playback seamlessly when completed
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: topItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loop() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: bottomItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loop() }
            .store(in: &cancellables)
    }

    func play() {
        topPlayer?.play()
        bottomPlayer?.play()
        isPlaying = true
    }

    func pause() {
        topPlayer?.pause()
        bottomPlayer?.pause()
        isPlaying = false
    }

    func toggle() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: CMTime) {
        topPlayer?.seek(to: time)
        bottomPlayer?.seek(to: time)
    }

    func loop() {
        seek(to: .zero)
        play()
    }

    func deinitPlayers() {
        pause()
        topPlayer = nil
        bottomPlayer = nil
    }
}
