import SwiftUI

enum MediaCategory: String, CaseIterable, Identifiable {
    case screenshots = "Screenshots"
    case videos = "Videos"
    case duplicatePhotos = "Duplicate Photos"
    case similarPhotos = "Similar Photos"
    case duplicateVideos = "Duplicate Videos"
    case largeVideos = "Large Videos"
    
    var id: String { rawValue }
    
    /// Videos at or above this size count as "Large". Decimal MB, to match how sizes are displayed.
    static let largeVideoThreshold: Int64 = 100_000_000
    
    var title: String { rawValue }
    
    var subtitlePlaceholder: String {
        switch self {
        case .screenshots: return "Every screen capture"
        case .videos: return "Your entire video library"
        case .duplicatePhotos: return "Exact copies"
        case .similarPhotos: return "Look-alike shots"
        case .duplicateVideos: return "Exact copies"
        case .largeVideos: return "Over 100 MB, biggest first"
        }
    }
    
    var iconSystemName: String {
        switch self {
        case .screenshots: return "crop"
        case .videos: return "play.rectangle"
        case .duplicatePhotos: return "square.on.square"
        case .similarPhotos: return "photo.on.rectangle"
        case .duplicateVideos: return "doc.on.doc"
        case .largeVideos: return "internaldrive"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .screenshots: return .cyan
        case .videos: return .indigo
        case .duplicatePhotos: return .coralRed
        case .similarPhotos: return .yellow
        case .duplicateVideos: return .pink
        case .largeVideos: return .orange
        }
    }
}
