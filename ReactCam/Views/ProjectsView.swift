import SwiftUI
import AVFoundation

struct ProjectsView: View {
    @ObservedObject private var store = ProjectStore.shared
    @State private var selectedProject: Project?
    @State private var navigateToEditor = false
    @State private var renamingProject: Project?
    @State private var renameText = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            NavigationLink(
                destination: Group {
                    if let project = selectedProject {
                        PreviewExportView(
                            topURL: store.topURL(for: project),
                            bottomURL: store.bottomURL(for: project),
                            orientation: project.orientation,
                            includeTopAudio: project.includeTopAudio
                        )
                    }
                },
                isActive: $navigateToEditor
            ) {
                EmptyView()
            }
            .hidden()

            if store.projects.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("No Projects Yet")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Every recording or import you edit is saved here automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                List {
                    ForEach(store.projects) { project in
                        Button {
                            selectedProject = project
                            navigateToEditor = true
                        } label: {
                            ProjectRow(project: project)
                        }
                        .listRowBackground(Color(white: 0.1))
                        // Swipe from the left to rename -- the standard, discoverable iOS
                        // affordance for this, rather than relying on a long-press context menu
                        // alone (still offered below too, as a shortcut for those who know it).
                        .swipeActions(edge: .leading) {
                            Button {
                                renameText = project.displayName
                                renamingProject = project
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.accentColor)
                        }
                        .contextMenu {
                            Button {
                                renameText = project.displayName
                                renamingProject = project
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                store.delete(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { store.delete(at: $0) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.projects.isEmpty {
                EditButton()
            }
        }
        .onAppear { store.reload() }
        .alert(
            "Rename Project",
            isPresented: Binding(
                get: { renamingProject != nil },
                set: { if !$0 { renamingProject = nil } }
            )
        ) {
            TextField("Project Name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renamingProject = nil
            }
            Button("Save") {
                if let renamingProject {
                    store.rename(renamingProject, to: renameText)
                }
                renamingProject = nil
            }
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    @State private var thumbnail: UIImage?
    @State private var durationText: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.15))

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(project.displayName)
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack(spacing: 5) {
                    Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let durationText {
                        Text("·")
                        Text(durationText)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .task {
            thumbnail = await ThumbnailGenerator.firstFrame(of: ProjectStore.shared.topURL(for: project))
            durationText = await Self.formattedDuration(of: ProjectStore.shared.topURL(for: project))
        }
    }

    private static func formattedDuration(of url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds, seconds.isFinite, seconds > 0 else {
            return nil
        }
        let totalSeconds = Int(seconds.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
