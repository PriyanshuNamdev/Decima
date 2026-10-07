import SwiftUI

enum MediaCategory: String, CaseIterable, Identifiable {
    case screenshots = "Screenshots"
    case videos = "Videos"
    case duplicatePhotos = "Duplicate Photos"
    case similarPhotos = "Similar Photos"
    case duplicateVideos = "Duplicate Videos"
    case largeVideos = "Large Videos"
    
    var id: String { rawValue }
    
    var title: String { rawValue }
    
    var subtitlePlaceholder: String {
        switch self {
        case .screenshots: return "Every screen capture"
        case .videos: return "Your entire video library"
        case .duplicatePhotos: return "Exact copies"
        case .similarPhotos: return "Look-alike shots"
        case .duplicateVideos: return "Exact copies"
        case .largeVideos: return "Biggest files first"
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
}
