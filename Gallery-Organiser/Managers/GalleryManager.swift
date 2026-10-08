import SwiftUI
import Photos

@MainActor
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
    /// A few assets per category for the dashboard card mosaics
    var categoryPreviews: [MediaCategory: [PHAsset]] = [:]
    /// Categories whose scan hasn't finished yet
    var loadingCategories: Set<MediaCategory> = Set(MediaCategory.allCases)

    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var libraryObserver: LibraryChangeObserver?

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
            startObservingLibrary()
            Task {
                await refresh()
            }
        }
    }

    func requestAuthorization() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            self.authorizationStatus = status
            if status == .authorized || status == .limited {
                startObservingLibrary()
                await refresh()
            }
        }
    }

    /// Rescans the library. Safe to call while a scan is running: it queues one more pass.
    func refresh() async {
        if isRefreshing {
            needsAnotherPass = true
            return
        }
        isRefreshing = true
        repeat {
            needsAnotherPass = false
            await calculateAllStats()
        } while needsAnotherPass
        isRefreshing = false
    }

    // MARK: - Library Changes

    private func startObservingLibrary() {
        guard libraryObserver == nil else { return }
        libraryObserver = LibraryChangeObserver { [weak self] in
            self?.scheduleRefresh()
        }
    }

    /// Deletions often arrive in bursts; wait for things to settle before rescanning
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    // MARK: - Scanning

    private func calculateAllStats() async {
        self.isCalculatingTotal = true

        let analyzer = PhotoLibraryAnalyzer()

        // Fast calculations
        apply(.screenshots, assets: await analyzer.fetchScreenshots())
        apply(.videos, assets: await analyzer.fetchVideos())
        apply(.largeVideos, assets: await analyzer.fetchLargeVideos())

        // Overall Totals
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        self.totalLibraryCount = PHAsset.fetchAssets(with: options).count
        self.totalLibrarySize = await analyzer.calculateTotalLibrarySize()

        // Heavy calculations (Duplicates, Similar). The analyzer is an actor, so these run off the main thread.
        apply(.duplicatePhotos, groups: await analyzer.findExactDuplicates(mediaType: .image))
        apply(.duplicateVideos, groups: await analyzer.findExactDuplicates(mediaType: .video))
        apply(.similarPhotos, groups: await analyzer.findSimilarPhotos())

        self.isCalculatingTotal = false
    }

    private func apply(_ category: MediaCategory, assets: [GalleryAsset]) {
        categoryCounts[category] = assets.count
        categorySizes[category] = assets.reduce(0) { $0 + $1.fileSize }
        categoryPreviews[category] = assets.prefix(4).map(\.asset)
        loadingCategories.remove(category)
    }

    /// Group sizes count only the copies that would be deleted (everything but the best copy)
    private func apply(_ category: MediaCategory, groups: [AssetGroup]) {
        categoryCounts[category] = groups.count
        categorySizes[category] = groups.reduce(0) { total, group in
            let keeper = CategoryDetailView.bestAsset(in: group)
            return total + group.assets.filter { $0.id != keeper.id }.reduce(0) { $0 + $1.fileSize }
        }
        categoryPreviews[category] = groups.prefix(4).compactMap { $0.assets.first?.asset }
        loadingCategories.remove(category)
    }

    // MARK: - Derived

    var totalWastedSize: Int64 {
        return categorySizes.values.reduce(0, +)
    }

    /// Space that can be freed without losing anything unique: extra copies and look-alikes
    var reclaimableSize: Int64 {
        [MediaCategory.duplicatePhotos, .duplicateVideos, .similarPhotos].reduce(0) { $0 + (categorySizes[$1] ?? 0) }
    }

    var isScanningForDuplicates: Bool {
        !loadingCategories.isDisjoint(with: [.duplicatePhotos, .duplicateVideos, .similarPhotos])
    }

    /// The group category with the most to reclaim, for the dashboard call to action
    var bestReclaimCategory: MediaCategory? {
        [MediaCategory.duplicatePhotos, .duplicateVideos, .similarPhotos]
            .filter { (categorySizes[$0] ?? 0) > 0 }
            .max { (categorySizes[$0] ?? 0) < (categorySizes[$1] ?? 0) }
    }

    /// Library composition for the dashboard bar
    var photosSize: Int64 {
        max(0, totalLibrarySize - (categorySizes[.videos] ?? 0) - (categorySizes[.screenshots] ?? 0))
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
    nonisolated static func formatSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// Calls back when photos or videos are added to or removed from the library
/// (edits and favourites are ignored, since they don't change the scan results).
final class LibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private var fetchResult: PHFetchResult<PHAsset>
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.fetchResult = PHAsset.fetchAssets(with: nil)
        self.onChange = onChange
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // Photos calls this serially on a background queue
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let details = changeInstance.changeDetails(for: fetchResult) else { return }
        fetchResult = details.fetchResultAfterChanges

        let membershipChanged = !details.hasIncrementalChanges
            || (details.removedIndexes?.count ?? 0) > 0
            || (details.insertedIndexes?.count ?? 0) > 0
        guard membershipChanged else { return }

        Task { @MainActor in
            onChange()
        }
    }
}
