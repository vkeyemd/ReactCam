import Foundation

/// A saved editing session. Created automatically whenever a user reaches the editor (whether
/// from Dual Camera or an imported video), so they can come back later and re-export -- e.g. once
/// in portrait and again in landscape -- without re-recording or re-importing.
///
/// Only the raw top/bottom source clips are kept; the merged/exported output itself isn't part of
/// a project, since it's re-generated fresh every time the user exports from the editor.
struct Project: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    /// Short, human-readable origin label for the projects list, e.g. "Dual Camera" or "Imported Video".
    let sourceLabel: String
    /// User-assigned name via the Rename action, if any. Defaults (via `displayName`) to
    /// `sourceLabel` -- without this, every project from the same flow looks identical in the
    /// list beyond its date, which doesn't scale past a couple of recordings.
    var customName: String? = nil
    /// Filenames only (not full paths) -- resolved against this project's own folder at read time,
    /// since the app's sandbox container path can change across launches/updates.
    let topFileName: String
    let bottomFileName: String
    /// The orientation the editor should open with. PreviewExportView re-detects and overrides this
    /// from the actual clip's aspect ratio on load, so this is just a reasonable starting value.
    let orientation: ExportOrientation
    /// Whether the top track's own audio was captured for this project (headphones were in use at
    /// recording time) -- see the headphone-use note in RecordingStudioView for why this matters.
    let includeTopAudio: Bool

    var displayName: String {
        if let customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customName
        }
        return sourceLabel
    }
}
