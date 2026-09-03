import AVFoundation
import CoreGraphics
import UIKit

public struct VideoLayoutState: Codable, Equatable {
    public var scale: CGFloat = 1.0
    public var offset: CGSize = .zero // Offset in canvas pixels
    public var isTopMost: Bool = false

    public init(scale: CGFloat = 1.0, offset: CGSize = .zero, isTopMost: Bool = false) {
        self.scale = scale
        self.offset = offset
        self.isTopMost = isTopMost
    }
}

enum VideoMergerError: LocalizedError {
    case missingTrack
    case exportFailed(String)
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .missingTrack:
            return "One of the source clips has no video track."
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .exportCancelled:
            return "Export was cancelled."
        }
    }
}

final class VideoMerger {
    
    enum MergerLayerType {
        case top
        case bottom
    }

    /// Centralized coordinate definitions for starting layout configurations.
    /// - Portrait: Top layer fills canvas; bottom layer sits in bottom-right corner as a PiP overlay.
    /// - Landscape: Left and Right side-by-side, taking up equal 50/50 space on the canvas.
    static func targetRect(for layer: MergerLayerType, orientation: ExportOrientation) -> CGRect {
        let renderSize = orientation.renderSize
        
        switch orientation {
        case .portrait:
            if layer == .top {
                // Full screen background
                return CGRect(origin: .zero, size: renderSize)
            } else {
                // Classic corner PIP overlay
                let pipWidth = renderSize.width * 0.25
                let pipHeight = pipWidth * (16.0 / 9.0)
                let paddingX = renderSize.width * 0.05
                let paddingY = renderSize.height * 0.05
                let invertedY = renderSize.height - pipHeight - paddingY
                return CGRect(
                    x: renderSize.width - pipWidth - paddingX,
                    y: invertedY,
                    width: pipWidth,
                    height: pipHeight
                )
            }
            
        case .landscape:
            let halfWidth = renderSize.width / 2.0
            if layer == .top {
                // Left Half Side-by-Side
                return CGRect(x: 0, y: 0, width: halfWidth, height: renderSize.height)
            } else {
                // Right Half Side-by-Side
                return CGRect(x: halfWidth, y: 0, width: halfWidth, height: renderSize.height)
            }
        }
    }

    static func merge(
        topURL: URL,
        bottomURL: URL,
        orientation: ExportOrientation,
        topLayout: VideoLayoutState,
        bottomLayout: VideoLayoutState,
        isRolesSwapped: Bool,
        includeTopAudio: Bool = true,
        topAudioVolume: Float = 1.0,
        bottomAudioVolume: Float = 1.0,
        progress: @escaping (Float) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task {
            do {
                let mergedURL = try await mergeAsync(
                    topURL: topURL,
                    bottomURL: bottomURL,
                    orientation: orientation,
                    topLayout: topLayout,
                    bottomLayout: bottomLayout,
                    isRolesSwapped: isRolesSwapped,
                    includeTopAudio: includeTopAudio,
                    topAudioVolume: topAudioVolume,
                    bottomAudioVolume: bottomAudioVolume,
                    progress: progress
                )

                await MainActor.run {
                    completion(.success(mergedURL))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    private static func mergeAsync(
        topURL: URL,
        bottomURL: URL,
        orientation: ExportOrientation,
        topLayout: VideoLayoutState,
        bottomLayout: VideoLayoutState,
        isRolesSwapped: Bool,
        includeTopAudio: Bool,
        topAudioVolume: Float,
        bottomAudioVolume: Float,
        progress: @escaping (Float) -> Void
    ) async throws -> URL {
        let topAsset = AVAsset(url: topURL)
        let bottomAsset = AVAsset(url: bottomURL)
        let composition = AVMutableComposition()

        let topTracks = try await topAsset.loadTracks(withMediaType: .video)
        let bottomTracks = try await bottomAsset.loadTracks(withMediaType: .video)

        guard let topAssetTrack = topTracks.first,
              let bottomAssetTrack = bottomTracks.first,
              let topVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let bottomVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoMergerError.missingTrack
        }

        let topTimeRange = try await topAssetTrack.load(.timeRange)
        let bottomTimeRange = try await bottomAssetTrack.load(.timeRange)

        let trimTime = CMTime(seconds: 0.1, preferredTimescale: 600)
        let topStart = topTimeRange.start + trimTime
        let bottomStart = bottomTimeRange.start + trimTime
        let duration = CMTimeMinimum(topTimeRange.duration, bottomTimeRange.duration) - trimTime

        // Kept so we can address these specific tracks again below when building the audio mix
        // (volume levels from the Sound Mixer).
        var compBottomAudioTrack: AVMutableCompositionTrack?
        var compTopAudioTrack: AVMutableCompositionTrack?

        do {
            try topVideoTrack.insertTimeRange(
                CMTimeRange(start: topStart, duration: duration),
                of: topAssetTrack,
                at: .zero
            )

            try bottomVideoTrack.insertTimeRange(
                CMTimeRange(start: bottomStart, duration: duration),
                of: bottomAssetTrack,
                at: .zero
            )

            let bottomAudioTracks = try await bottomAsset.loadTracks(withMediaType: .audio)
            if let bottomAudio = bottomAudioTracks.first,
               let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try? compAudio.insertTimeRange(
                    CMTimeRange(start: bottomStart, duration: duration),
                    of: bottomAudio,
                    at: .zero
                )
                compBottomAudioTrack = compAudio
            }

            // Only keep the top track's own audio (the reacted-to video's audio, or the rear
            // camera's own audio in Dual Camera mode) when the caller has determined it's safe /
            // desired to -- see the headphone-use note where this flag is computed.
            if includeTopAudio {
                let topAudioTracks = try await topAsset.loadTracks(withMediaType: .audio)
                if let topAudio = topAudioTracks.first,
                   let compSourceAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try? compSourceAudio.insertTimeRange(
                        CMTimeRange(start: topStart, duration: duration),
                        of: topAudio,
                        at: .zero
                    )
                    compTopAudioTrack = compSourceAudio
                }
            }
        } catch {
            throw error
        }

        let renderSize = orientation.renderSize
        
        let topRole: MergerLayerType = isRolesSwapped ? .bottom : .top
        let bottomRole: MergerLayerType = isRolesSwapped ? .top : .bottom
        
        let topRect = targetRect(for: topRole, orientation: orientation)
        let bottomRect = targetRect(for: bottomRole, orientation: orientation)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let topLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: topVideoTrack)
        let bottomLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: bottomVideoTrack)

        // Load natural dimensions & orientation metadata for calculation
        let topNaturalSize = try await topAssetTrack.load(.naturalSize)
        let topPreferredTransform = try await topAssetTrack.load(.preferredTransform)
        let bottomNaturalSize = try await bottomAssetTrack.load(.naturalSize)
        let bottomPreferredTransform = try await bottomAssetTrack.load(.preferredTransform)

        let topTransform = calculateTransform(
            naturalSize: topNaturalSize,
            preferredTransform: topPreferredTransform,
            targetRect: topRect,
            mirrorHorizontally: false,
            scale: topLayout.scale,
            offset: topLayout.offset
        )

        let bottomTransform = calculateTransform(
            naturalSize: bottomNaturalSize,
            preferredTransform: bottomPreferredTransform,
            targetRect: bottomRect,
            mirrorHorizontally: true,
            scale: bottomLayout.scale,
            offset: bottomLayout.offset
        )

        topLayerInstruction.setTransform(topTransform, at: .zero)
        bottomLayerInstruction.setTransform(bottomTransform, at: .zero)

        // Stacking order
        //
        // AVFoundation's compositor corrupts the geometry of whichever layer instruction is
        // listed *second* in `layerInstructions` when one source has a rotated preferredTransform
        // (e.g. a portrait-shot camera recording) and the other has an identity transform (e.g.
        // an already-landscape imported clip) -- the corrupted track renders sampled from the
        // wrong region, appearing shifted. Landscape's two halves are laid out side-by-side and
        // never overlap, so array order has no visible effect on stacking there; always list the
        // rotated source first in that case to sidestep the corruption. Portrait's layers do
        // overlap (full-bleed background + corner PIP), so its stacking keeps following isTopMost.
        let topIsRotated = (topPreferredTransform.a == 0 && abs(topPreferredTransform.b) == 1)
        let bottomIsRotated = (bottomPreferredTransform.a == 0 && abs(bottomPreferredTransform.b) == 1)

        if orientation == .landscape && topIsRotated != bottomIsRotated {
            instruction.layerInstructions = topIsRotated
                ? [topLayerInstruction, bottomLayerInstruction]
                : [bottomLayerInstruction, topLayerInstruction]
        } else if bottomLayout.isTopMost {
            instruction.layerInstructions = [bottomLayerInstruction, topLayerInstruction]
        } else {
            instruction.layerInstructions = [topLayerInstruction, bottomLayerInstruction]
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = renderSize
        videoComposition.renderScale = 1.0

        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.backgroundColor = UIColor.black.cgColor // Hard black fill underneath
        parentLayer.addSublayer(videoLayer)

        // Determine which layer is acting as the overlay corner
        let overlayTrackIsTopTrack = (topRole == .bottom)
        let isOverlayTopMost = overlayTrackIsTopTrack ? topLayout.isTopMost : bottomLayout.isTopMost

        if isOverlayTopMost && orientation == .portrait {
            let borderLayerContainer = CALayer()
            borderLayerContainer.frame = CGRect(origin: .zero, size: renderSize)
            
            // Flip vertically to match top-left AVVideoComposition space
            borderLayerContainer.transform = CATransform3DMakeScale(1, -1, 1)
            borderLayerContainer.position = CGPoint(x: 0, y: renderSize.height)

            let borderLayer = CAShapeLayer()
            borderLayer.anchorPoint = .zero
            
            if overlayTrackIsTopTrack {
                let isTopPortrait = (topPreferredTransform.a == 0 && abs(topPreferredTransform.b) == 1)
                let topActualWidth = isTopPortrait ? topNaturalSize.height : topNaturalSize.width
                let topActualHeight = isTopPortrait ? topNaturalSize.width : topNaturalSize.height
                let topAssetActualSize = CGSize(width: topActualWidth, height: topActualHeight)
                
                borderLayer.frame = CGRect(origin: .zero, size: topAssetActualSize)
                borderLayer.path = UIBezierPath(
                    roundedRect: borderLayer.bounds.insetBy(dx: 5, dy: 5),
                    cornerRadius: 16
                ).cgPath
                borderLayer.strokeColor = UIColor.white.cgColor
                borderLayer.fillColor = UIColor.clear.cgColor
                borderLayer.lineWidth = 10
                borderLayer.transform = CATransform3DMakeAffineTransform(topTransform)
            } else {
                let isBottomPortrait = (bottomPreferredTransform.a == 0 && abs(bottomPreferredTransform.b) == 1)
                let bottomActualWidth = isBottomPortrait ? bottomNaturalSize.height : bottomNaturalSize.width
                let bottomActualHeight = isBottomPortrait ? bottomNaturalSize.width : bottomNaturalSize.height
                let bottomAssetActualSize = CGSize(width: bottomActualWidth, height: bottomActualHeight)
                
                borderLayer.frame = CGRect(origin: .zero, size: bottomAssetActualSize)
                borderLayer.path = UIBezierPath(
                    roundedRect: borderLayer.bounds.insetBy(dx: 5, dy: 5),
                    cornerRadius: 16
                ).cgPath
                borderLayer.strokeColor = UIColor.white.cgColor
                borderLayer.fillColor = UIColor.clear.cgColor
                borderLayer.lineWidth = 10
                borderLayer.transform = CATransform3DMakeAffineTransform(bottomTransform)
            }

            borderLayerContainer.addSublayer(borderLayer)
            parentLayer.addSublayer(borderLayerContainer)
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Merged_\(UUID().uuidString).mp4")

        if FileManager.default.fileExists(atPath: exportURL.path) {
            try? FileManager.default.removeItem(at: exportURL)
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoMergerError.exportFailed("Could not create exporter")
        }

        exporter.outputURL = exportURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition

        // Sound Mixer volumes, applied per audio track at export time.
        var audioMixParameters: [AVMutableAudioMixInputParameters] = []
        if let compBottomAudioTrack {
            let params = AVMutableAudioMixInputParameters(track: compBottomAudioTrack)
            params.setVolume(bottomAudioVolume, at: .zero)
            audioMixParameters.append(params)
        }
        if let compTopAudioTrack {
            let params = AVMutableAudioMixInputParameters(track: compTopAudioTrack)
            params.setVolume(topAudioVolume, at: .zero)
            audioMixParameters.append(params)
        }
        if !audioMixParameters.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixParameters
            exporter.audioMix = audioMix
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                progress(exporter.progress)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                timer.invalidate()

                switch exporter.status {
                case .completed:
                    continuation.resume(returning: exportURL)

                case .cancelled:
                    continuation.resume(throwing: VideoMergerError.exportCancelled)

                default:
                    continuation.resume(
                        throwing: VideoMergerError.exportFailed(
                            exporter.error?.localizedDescription ?? "Unknown error"
                        )
                    )
                }
            }
        }
    }

    /// Pure, mathematical mapping from native asset track coordinates to the canvas,
    /// integrating both the base aspect-fill scaling and the user's freeform translations.
    static func calculateTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        targetRect: CGRect,
        mirrorHorizontally: Bool,
        scale: CGFloat,
        offset: CGSize
    ) -> CGAffineTransform {
        let isPortrait = (preferredTransform.a == 0 && abs(preferredTransform.b) == 1)
        let actualWidth = isPortrait ? naturalSize.height : naturalSize.width
        let actualHeight = isPortrait ? naturalSize.width : naturalSize.height

        let baseScale = max(targetRect.width / actualWidth, targetRect.height / actualHeight)
        let scaledWidth = actualWidth * baseScale
        let scaledHeight = actualHeight * baseScale

        let tx = targetRect.origin.x + (targetRect.width - scaledWidth) / 2.0
        let ty = targetRect.origin.y + (targetRect.height - scaledHeight) / 2.0

        var transform = preferredTransform
        let rectAfterPref = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)

        transform = transform.concatenating(
            CGAffineTransform(
                translationX: -rectAfterPref.minX,
                y: -rectAfterPref.minY
            )
        )

        if mirrorHorizontally {
            transform = transform.concatenating(CGAffineTransform(scaleX: -1.0, y: 1.0))
            transform = transform.concatenating(CGAffineTransform(translationX: actualWidth, y: 0.0))
        }

        transform = transform.concatenating(CGAffineTransform(scaleX: baseScale, y: baseScale))
        transform = transform.concatenating(CGAffineTransform(translationX: tx, y: ty))

        // Center around which user gestures (pinch-zoom and drag-recenter) operate
        let cx = targetRect.midX
        let cy = targetRect.midY

        let userTransform = CGAffineTransform(translationX: cx + offset.width, y: cy + offset.height)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -cx, y: -cy)

        return transform.concatenating(userTransform)
    }
}
