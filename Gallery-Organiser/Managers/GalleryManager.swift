import SwiftUI
import Photos

@Observable
class GalleryManager {
    var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    // Global Stats
    var totalLibrarySize: Int64 = 0
    var totalLibraryCount: Int = 0
    var isCalculatingTotal = false
    
    // Category Stats (Count, Size)
    var categoryCounts: [MediaCategory: Int] = [:]
    var categorySizes: [MediaCategory: Int64] = [:]
    
    init() {
        checkAuthorization()
    }
    
    func checkAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationStatus = status
        
        if status == .authorized || status == .limited {
            Task {
                await calculateGlobalStats()
            }
        }
    }
    
    func requestAuthorization() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            Task.detached { @MainActor in
                self.authorizationStatus = status
                if status == .authorized || status == .limited {
                    await self.calculateGlobalStats()
                }
            }
        }
    }
    
    @MainActor
    private func calculateGlobalStats() async {
        isCalculatingTotal = true
        
        let allPhotosOptions = PHFetchOptions()
        allPhotosOptions.includeHiddenAssets = false
        let allAssets = PHAsset.fetchAssets(with: allPhotosOptions)
        totalLibraryCount = allAssets.count
        
        // Fetch fast counts for categories off the main thread
        let analyzer = PhotoLibraryAnalyzer()
        let stats = await analyzer.fetchCategoryOverviewStats()
        
        self.categoryCounts = stats.counts
        self.categorySizes = stats.sizes
        
        isCalculatingTotal = false
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
