import SwiftUI
import Photos

@Observable
class GalleryManager {
    var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    // Global Stats
    var totalLibrarySize: Int64 = 0
    var totalLibraryCount: Int = 0
    var totalDeviceStorage: Int64 = 0
    var isCalculatingTotal = true
    
    // Category Stats (Count, Size)
    var categoryCounts: [MediaCategory: Int] = [:]
    var categorySizes: [MediaCategory: Int64] = [:]
    
    init() {
        fetchDeviceStorage()
        checkAuthorization()
    }
    
    private func fetchDeviceStorage() {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let total = attrs[.systemSize] as? NSNumber {
                totalDeviceStorage = total.int64Value
            }
        } catch {
            print("Error fetching device storage: \(error)")
        }
    }
    
    func checkAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationStatus = status
        
        if status == .authorized || status == .limited {
            Task {
                await calculateAllStats()
            }
        }
    }
    
    func requestAuthorization() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            Task.detached { @MainActor in
                self.authorizationStatus = status
                if status == .authorized || status == .limited {
                    await self.calculateAllStats()
                }
            }
        }
    }
    
    @MainActor
    private func calculateAllStats() async {
        self.isCalculatingTotal = true
        
        let analyzer = PhotoLibraryAnalyzer()
        
        // Fast calculations
        let screenshots = await analyzer.fetchScreenshots()
        self.categoryCounts[.screenshots] = screenshots.count
        self.categorySizes[.screenshots] = screenshots.reduce(0) { $0 + $1.fileSize }
        
        let videos = await analyzer.fetchVideos()
        self.categoryCounts[.videos] = videos.count
        self.categorySizes[.videos] = videos.reduce(0) { $0 + $1.fileSize }
        
        let largeVideos = await analyzer.fetchLargeVideos()
        self.categoryCounts[.largeVideos] = largeVideos.count
        self.categorySizes[.largeVideos] = largeVideos.reduce(0) { $0 + $1.fileSize }
        
        // Overall Totals
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let allAssets = PHAsset.fetchAssets(with: options)
        self.totalLibraryCount = allAssets.count
        
        // Heavy calculations (Duplicates, Similar, Total Size)
        Task.detached {
            // Get accurate total size
            let accurateTotalSize = await analyzer.calculateTotalLibrarySize()
            
            await MainActor.run {
                self.totalLibrarySize = accurateTotalSize
            }
            
            let dupPhotos = await analyzer.findExactDuplicates(mediaType: .image)
            let dupPhotosCount = dupPhotos.count
            let dupPhotosSize = dupPhotos.reduce(0) { $0 + $1.assets.dropFirst().reduce(0) { sum, asset in sum + asset.fileSize } }
            
            let dupVids = await analyzer.findExactDuplicates(mediaType: .video)
            let dupVidsCount = dupVids.count
            let dupVidsSize = dupVids.reduce(0) { $0 + $1.assets.dropFirst().reduce(0) { sum, asset in sum + asset.fileSize } }
            
            let simPhotos = await analyzer.findSimilarPhotos()
            let simPhotosCount = simPhotos.count
            let simPhotosSize = simPhotos.reduce(0) { $0 + $1.assets.dropFirst().reduce(0) { sum, asset in sum + asset.fileSize } }
            
            await MainActor.run {
                self.categoryCounts[.duplicatePhotos] = dupPhotosCount
                self.categorySizes[.duplicatePhotos] = dupPhotosSize
                
                self.categoryCounts[.duplicateVideos] = dupVidsCount
                self.categorySizes[.duplicateVideos] = dupVidsSize
                
                self.categoryCounts[.similarPhotos] = simPhotosCount
                self.categorySizes[.similarPhotos] = simPhotosSize
                
                self.isCalculatingTotal = false
            }
        }
    }
    
    var totalWastedSize: Int64 {
        return categorySizes.values.reduce(0, +)
    }
    
    var formattedLibrarySizeValue: String {
        guard totalLibrarySize > 0 else { return "--" }
        let formatted = GalleryManager.formatSize(totalLibrarySize)
        // Extract the number part
        return formatted.components(separatedBy: " ").first ?? "--"
    }
    
    var formattedLibrarySizeUnit: String {
        guard totalLibrarySize > 0 else { return "GB" }
        let formatted = GalleryManager.formatSize(totalLibrarySize)
        // Extract the unit part
        return formatted.components(separatedBy: " ").last ?? "GB"
    }
    
    var formattedDeviceSizeValue: String {
        guard totalDeviceStorage > 0 else { return "--" }
        let formatted = GalleryManager.formatSize(totalDeviceStorage)
        return formatted.components(separatedBy: " ").first ?? "--"
    }
    
    var formattedDeviceSizeUnit: String {
        guard totalDeviceStorage > 0 else { return "GB" }
        let formatted = GalleryManager.formatSize(totalDeviceStorage)
        return formatted.components(separatedBy: " ").last ?? "GB"
    }
    
    // Formatter helper
    static func formatSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
