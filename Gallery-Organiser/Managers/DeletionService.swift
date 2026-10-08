import Foundation
import Photos

class DeletionService {
    static let shared = DeletionService()
    
    func deleteAssets(_ assets: [GalleryAsset]) async throws {
        let phAssets = assets.map { $0.asset }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(phAssets as NSArray)
        }
    }
}
