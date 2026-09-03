import AVFoundation
import UIKit

/// Pulls the very first frame of an imported video so the Recording Studio
/// can show something other than a black rectangle while the AVPlayer is
/// paused and waiting for the user to hit Record.
enum ThumbnailGenerator {

    static func firstFrame(of url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let time = CMTime(seconds: 0.03, preferredTimescale: 600)

        do {
            let cgImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, error in
                    if let image, result == .succeeded {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: error ?? NSError(domain: "ThumbnailGenerator", code: -1))
                    }
                }
            }
            return UIImage(cgImage: cgImage)
        } catch {
            print("ThumbnailGenerator: failed to extract first frame — \(error.localizedDescription)")
            return nil
        }
    }
}
