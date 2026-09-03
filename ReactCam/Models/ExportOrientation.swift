import CoreGraphics

enum ExportOrientation: String, CaseIterable, Identifiable {
    case portrait
    case landscape

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .portrait: return "Portrait (9:16)"
        case .landscape: return "Landscape (16:9)"
        }
    }

    var renderSize: CGSize {
        switch self {
        case .portrait: return CGSize(width: 1080, height: 1920)
        case .landscape: return CGSize(width: 1920, height: 1080)
        }
    }

    var previewAspectRatio: CGFloat {
        switch self {
        case .portrait: return 9.0 / 16.0
        case .landscape: return 16.0 / 9.0
        }
    }
}
