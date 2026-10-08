import SwiftUI
import Foundation

struct StorageSegment: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let bytes: Int64
    let isGallery: Bool
}

@MainActor
@Observable
class StorageAnalysisService {
    var totalDeviceCapacity: Int64 = 0
    var usedDeviceCapacity: Int64 = 0
    var freeDeviceCapacity: Int64 = 0
    
    var photosSize: Int64 = 0
    var videosSize: Int64 = 0
    var screenshotsSize: Int64 = 0
    
    var duplicatePhotosSize: Int64 = 0
    var similarPhotosSize: Int64 = 0
    var duplicateVideosSize: Int64 = 0
    var largeVideosSize: Int64 = 0
    
    var isLoading: Bool = false
    
    init() {}
    
    func populate(from manager: GalleryManager) {
        // Device Storage
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let total = attrs[.systemSize] as? NSNumber {
                totalDeviceCapacity = total.int64Value
            }
            if let free = attrs[.systemFreeSize] as? NSNumber {
                freeDeviceCapacity = free.int64Value
            }
            usedDeviceCapacity = max(0, totalDeviceCapacity - freeDeviceCapacity)
        } catch {
            print("Error fetching device storage: \(error)")
        }
        
        // Gallery Categories
        self.screenshotsSize = manager.categorySizes[.screenshots] ?? 0
        self.videosSize = manager.categorySizes[.videos] ?? 0
        
        // Since manager.totalLibrarySize is the total size of all media,
        // Photos = Total - Videos - Screenshots
        let galleryTotal = manager.totalLibrarySize
        let photos = max(0, galleryTotal - self.videosSize - self.screenshotsSize)
        self.photosSize = photos
        
        self.duplicatePhotosSize = manager.categorySizes[.duplicatePhotos] ?? 0
        self.similarPhotosSize = manager.categorySizes[.similarPhotos] ?? 0
        self.duplicateVideosSize = manager.categorySizes[.duplicateVideos] ?? 0
        self.largeVideosSize = manager.categorySizes[.largeVideos] ?? 0
    }
    
    var segments: [StorageSegment] {
        let galleryTotal = photosSize + videosSize + screenshotsSize
        let systemAndOther = max(0, usedDeviceCapacity - galleryTotal)
        let free = max(0, totalDeviceCapacity - usedDeviceCapacity)
        
        return [
            StorageSegment(name: "Photos", color: .mint, bytes: photosSize, isGallery: true),
            StorageSegment(name: "Videos", color: .indigo, bytes: videosSize, isGallery: true),
            StorageSegment(name: "Screenshots", color: .cyan, bytes: screenshotsSize, isGallery: true),
            StorageSegment(name: "System & Other", color: .charcoalBorder, bytes: systemAndOther, isGallery: false),
            StorageSegment(name: "Free", color: .clear, bytes: free, isGallery: false)
        ].filter { $0.bytes > 0 }
    }
    
    func formattedSize(_ bytes: Int64) -> String {
        return GalleryManager.formatSize(bytes)
    }
    
    var percentageUsed: Int {
        guard totalDeviceCapacity > 0 else { return 0 }
        let fraction = Double(usedDeviceCapacity) / Double(totalDeviceCapacity)
        return Int(fraction * 100)
    }
}
