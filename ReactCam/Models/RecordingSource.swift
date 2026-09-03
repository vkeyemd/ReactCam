import Foundation

/// How the primary content of the recording is produced.
///
/// - `importedVideo`: the classic reaction flow — play an imported video while
///   recording the front camera.
/// - `cameraRollArchitectureWithRearCamera`: reuse that same camera-roll-style
///   architecture, but replace the imported video pane with a live rear camera
///   feed while keeping the front camera feed and export layout identical.
///
/// This replaces the old dual-capture mode that offered portrait/landscape
/// variants.
enum RecordingSource: Equatable {
    case importedVideo(url: URL)
    case cameraRollArchitectureWithRearCamera

    var usesRearCameraAsPrimaryFeed: Bool {
        if case .cameraRollArchitectureWithRearCamera = self { return true }
        return false
    }

    var importedURL: URL? {
        if case .importedVideo(let url) = self { return url }
        return nil
    }
}

/// Where an imported source video came from — kept mainly for UI messaging
/// ("Imported from Photos" vs "Imported from Files").
enum ImportOrigin {
    case cameraRoll
    case filesApp
}
