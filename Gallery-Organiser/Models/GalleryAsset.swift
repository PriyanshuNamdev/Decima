import Foundation
import Photos
import SwiftUI

struct GalleryAsset: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let fileSize: Int64
    
    init(asset: PHAsset, fileSize: Int64 = 0) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.fileSize = fileSize
    }
    
    static func == (lhs: GalleryAsset, rhs: GalleryAsset) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
