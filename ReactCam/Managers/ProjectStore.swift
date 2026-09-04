import Combine
import Foundation

/// Persists Projects to disk: an on-disk index (JSON) plus a per-project folder holding durable
/// copies of its top/bottom source clips.
///
/// This exists because every other source of video URLs in the app -- camera recordings
/// (CameraManager writes to `temporaryDirectory`), PHPickerView's copy, even
/// DocumentPickerView's `asCopy` output -- lives in the OS's temporary/inbox storage, which isn't
/// guaranteed to survive between app launches or under storage pressure. A project that's meant
/// to be revisited "as often as they want" needs its own stable copy.
@MainActor
final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()

    @Published private(set) var projects: [Project] = []

    private let fileManager = FileManager.default

    private var projectsRootURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Projects", isDirectory: true)
    }

    private var indexURL: URL {
        projectsRootURL.appendingPathComponent("index.json")
    }

    private init() {
        try? fileManager.createDirectory(at: projectsRootURL, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Project].self, from: data) else {
            projects = []
            return
        }
        projects = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    func folderURL(for project: Project) -> URL {
        projectsRootURL.appendingPathComponent(project.id.uuidString, isDirectory: true)
    }

    func topURL(for project: Project) -> URL {
        folderURL(for: project).appendingPathComponent(project.topFileName)
    }

    func bottomURL(for project: Project) -> URL {
        folderURL(for: project).appendingPathComponent(project.bottomFileName)
    }

    /// Copies the given source clips into a new project folder and records it in the index.
    /// Returns `nil` (leaving no partial state behind) if the copy fails, e.g. out of disk space --
    /// callers should fall back to using the original source URLs directly in that case rather
    /// than failing the whole recording/import flow over it.
    @discardableResult
    func createProject(
        topSourceURL: URL,
        bottomSourceURL: URL,
        sourceLabel: String,
        orientation: ExportOrientation,
        includeTopAudio: Bool
    ) -> Project? {
        let id = UUID()
        let folder = projectsRootURL.appendingPathComponent(id.uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

            let topExtension = topSourceURL.pathExtension.isEmpty ? "mov" : topSourceURL.pathExtension
            let bottomExtension = bottomSourceURL.pathExtension.isEmpty ? "mov" : bottomSourceURL.pathExtension
            let topFileName = "top.\(topExtension)"
            let bottomFileName = "bottom.\(bottomExtension)"

            try fileManager.copyItem(at: topSourceURL, to: folder.appendingPathComponent(topFileName))
            try fileManager.copyItem(at: bottomSourceURL, to: folder.appendingPathComponent(bottomFileName))

            let project = Project(
                id: id,
                createdAt: Date(),
                sourceLabel: sourceLabel,
                topFileName: topFileName,
                bottomFileName: bottomFileName,
                orientation: orientation,
                includeTopAudio: includeTopAudio
            )
            projects.insert(project, at: 0)
            persistIndex()
            return project
        } catch {
            try? fileManager.removeItem(at: folder)
            print("ProjectStore: failed to create project — \(error.localizedDescription)")
            return nil
        }
    }

    func rename(_ project: Project, to newName: String) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        projects[index].customName = trimmed.isEmpty ? nil : trimmed
        persistIndex()
    }

    func delete(_ project: Project) {
        try? fileManager.removeItem(at: folderURL(for: project))
        projects.removeAll { $0.id == project.id }
        persistIndex()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            delete(projects[index])
        }
    }
}
