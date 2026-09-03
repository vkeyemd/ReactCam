import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Wraps `PHPickerViewController`, filtered to videos only, and copies the
/// picked item out of the Photos sandbox into our own temp directory so the
/// rest of the app (AVPlayer, the merger) can treat it like any other file URL.
struct PHPickerView: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void
    let onCancel: () -> Void

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
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (URL) -> Void
        let onCancel: () -> Void

        init(onPicked: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                onCancel()
                return
            }

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
