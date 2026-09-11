import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Wraps `PHPickerViewController`, filtered to videos only, and copies the
/// picked item out of the Photos sandbox into our own temp directory so the
/// rest of the app (AVPlayer, the merger) can treat it like any other file URL.
struct PHPickerView: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void
    let onCancel: () -> Void
    /// Fired once we know a video was actually picked and the (potentially slow,
    /// e.g. iCloud-backed) load is starting -- the caller's cue to show a loading screen.
    let onImportStart: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel, onImportStart: onImportStart)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (URL) -> Void
        let onCancel: () -> Void
        let onImportStart: () -> Void

        init(
            onPicked: @escaping (URL) -> Void,
            onCancel: @escaping () -> Void,
            onImportStart: @escaping () -> Void
        ) {
            self.onPicked = onPicked
            self.onCancel = onCancel
            self.onImportStart = onImportStart
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Deliberately not calling picker.dismiss(animated:) here -- the sheet is dismissed
            // by the caller's onPicked/onCancel (via the isPresented binding) only once the load
            // below has actually finished, so our loading overlay (a sibling on top of this
            // picker, inside the same sheet) stays visible for the load's real duration instead
            // of racing an early dismiss animation that could finish before the load does.
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                onCancel()
                return
            }

            onImportStart()

            // PHPicker's Progress for loadFileRepresentation doesn't report reliable,
            // continuously-advancing fractionCompleted for Photos-library items (it can
            // report a small value once and then stall until the whole load finishes),
            // so we don't surface it as a percentage -- just that a load is in progress.
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [onPicked, onCancel] tempURL, error in
                guard let tempURL, error == nil else {
                    DispatchQueue.main.async { onCancel() }
                    return
                }
                // loadFileRepresentation's URL is deleted as soon as this
                // closure returns, so copy it to a stable location first.
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(tempURL.pathExtension.isEmpty ? "mov" : tempURL.pathExtension)
                do {
                    try FileManager.default.copyItem(at: tempURL, to: destination)
                    DispatchQueue.main.async { onPicked(destination) }
                } catch {
                    DispatchQueue.main.async { onCancel() }
                }
            }
        }
    }
}
