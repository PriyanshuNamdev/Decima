import SwiftUI
import Photos

@Observable
class CleanUpSession {
    var assets: [GalleryAsset] = []
    var currentIndex: Int = 0
    var keptAssetIDs: Set<String> = []
    var deletedAssetIDs: Set<String> = []
    var isFinished: Bool = false
    
    // History for Undo
    var history: [CleanUpAction] = []
    
    struct CleanUpAction {
        let index: Int
        let assetID: String
        let wasKept: Bool
    }
    
    init(assets: [GalleryAsset]) {
        self.assets = assets
    }
    
    var currentAsset: GalleryAsset? {
        guard currentIndex < assets.count else { return nil }
        return assets[currentIndex]
    }
    
    var nextAsset: GalleryAsset? {
        guard currentIndex + 1 < assets.count else { return nil }
        return assets[currentIndex + 1]
    }
    
    func keepCurrent() {
        guard let current = currentAsset else { return }
        keptAssetIDs.insert(current.id)
        history.append(CleanUpAction(index: currentIndex, assetID: current.id, wasKept: true))
        advance()
    }
    
    func deleteCurrent() {
        guard let current = currentAsset else { return }
        deletedAssetIDs.insert(current.id)
        history.append(CleanUpAction(index: currentIndex, assetID: current.id, wasKept: false))
        advance()
    }
    
    /// Undoes the last swipe and returns it, so the card can come back from the side it left
    @discardableResult
    func undoLast() -> CleanUpAction? {
        guard let last = history.popLast() else { return nil }
        if last.wasKept {
            keptAssetIDs.remove(last.assetID)
        } else {
            deletedAssetIDs.remove(last.assetID)
        }
        currentIndex = last.index
        if isFinished {
            isFinished = false
        }
        return last
    }
    
    private func advance() {
        currentIndex += 1
        if currentIndex >= assets.count {
            isFinished = true
        }
    }
    
    /// Total size of everything marked for deletion so far
    var markedBytes: Int64 {
        assets.reduce(0) { total, asset in deletedAssetIDs.contains(asset.id) ? total + asset.fileSize : total }
    }
    
    var totalReviewed: Int {
        return history.count
    }
}
