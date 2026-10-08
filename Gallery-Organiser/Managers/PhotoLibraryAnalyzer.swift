import Foundation
import Photos
import CryptoKit
import Vision
import UIKit

struct AssetGroup: Identifiable {
    let id = UUID()
    let assets: [GalleryAsset]
}

actor PhotoLibraryAnalyzer {
    
    // MARK: - Photos
    func fetchPhotos() -> [GalleryAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [GalleryAsset] = []
        for i in 0..<result.count {
            let asset = result.object(at: i)
            assets.append(GalleryAsset(asset: asset, fileSize: getFileSize(for: asset)))
        }
        return assets
    }
    
    // MARK: - Screenshots
    func fetchScreenshots() -> [GalleryAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [GalleryAsset] = []
        for i in 0..<result.count {
            let asset = result.object(at: i)
            assets.append(GalleryAsset(asset: asset, fileSize: getFileSize(for: asset)))
        }
        return assets
    }
    
    // MARK: - Videos
    func fetchVideos() -> [GalleryAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let result = PHAsset.fetchAssets(with: .video, options: options)
        var assets: [GalleryAsset] = []
        for i in 0..<result.count {
            let asset = result.object(at: i)
            assets.append(GalleryAsset(asset: asset, fileSize: getFileSize(for: asset)))
        }
        return assets
    }
    
    // MARK: - Large Videos
    func fetchLargeVideos() -> [GalleryAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let result = PHAsset.fetchAssets(with: .video, options: options)
        
        var assetsWithSizes: [GalleryAsset] = []
        for i in 0..<result.count {
            let asset = result.object(at: i)
            let size = getFileSize(for: asset)
            if size >= MediaCategory.largeVideoThreshold {
                assetsWithSizes.append(GalleryAsset(asset: asset, fileSize: size))
            }
        }
        
        assetsWithSizes.sort { $0.fileSize > $1.fileSize }
        return assetsWithSizes
    }
    
    // MARK: - Exact Duplicates
    func findExactDuplicates(mediaType: PHAssetMediaType) -> [AssetGroup] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let result = PHAsset.fetchAssets(with: mediaType, options: options)
        
        var candidateGroups: [String: [PHAsset]] = [:]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        
        for i in 0..<result.count {
            let asset = result.object(at: i)
            let dateStr = asset.creationDate != nil ? dateFormatter.string(from: asset.creationDate!) : "nodate"
            let key = "\(dateStr)_\(asset.pixelWidth)x\(asset.pixelHeight)"
            candidateGroups[key, default: []].append(asset)
        }
        
        var duplicateGroups: [AssetGroup] = []
        let candidates = candidateGroups.values.filter { $0.count > 1 }
        
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.deliveryMode = .highQualityFormat
        
        for group in candidates {
            var hashDict: [String: [PHAsset]] = [:]
            
            for asset in group {
                var hashValue = UUID().uuidString
                if mediaType == .image {
                    imageManager.requestImageDataAndOrientation(for: asset, options: requestOptions) { data, _, _, _ in
                        if let data = data {
                            let hash = SHA256.hash(data: data)
                            hashValue = hash.compactMap { String(format: "%02x", $0) }.joined()
                        }
                    }
                } else {
                    hashValue = "\(asset.duration)"
                }
                hashDict[hashValue, default: []].append(asset)
            }
            
            for (_, matches) in hashDict where matches.count > 1 {
                let wrapped = matches.map { GalleryAsset(asset: $0, fileSize: getFileSize(for: $0)) }
                duplicateGroups.append(AssetGroup(assets: wrapped))
            }
        }
        
        return duplicateGroups
    }
    
    // MARK: - Similar Photos
    func findSimilarPhotos() -> [AssetGroup] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.predicate = NSPredicate(format: "(mediaSubtype & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        let result = PHAsset.fetchAssets(with: .image, options: options)
        
        var buckets: [String: [PHAsset]] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for i in 0..<result.count {
            let asset = result.object(at: i)
            let ratio = asset.pixelHeight > 0 ? (Double(asset.pixelWidth) / Double(asset.pixelHeight)) : 1.0
            let ratioStr = String(format: "%.2f", ratio)
            let dateStr = asset.creationDate != nil ? dateFormatter.string(from: asset.creationDate!) : "nodate"
            let bucketKey = "\(dateStr)_\(ratioStr)"
            buckets[bucketKey, default: []].append(asset)
        }
        
        let validBuckets = buckets.values.filter { $0.count > 1 }
        var similarGroups: [AssetGroup] = []
        
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.deliveryMode = .fastFormat
        
        let similarityThreshold: Float = 15.0
        
        for bucket in validBuckets {
            var featurePrints: [(PHAsset, VNFeaturePrintObservation)] = []
            
            for asset in bucket {
                imageManager.requestImage(for: asset, targetSize: CGSize(width: 256, height: 256), contentMode: .aspectFit, options: requestOptions) { image, _ in
                    if let cgImage = image?.cgImage {
                        let request = VNGenerateImageFeaturePrintRequest()
                        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                        try? handler.perform([request])
                        if let print = request.results?.first as? VNFeaturePrintObservation {
                            featurePrints.append((asset, print))
                        }
                    }
                }
            }
            
            var processed = Set<String>()
            for i in 0..<featurePrints.count {
                let a1 = featurePrints[i]
                if processed.contains(a1.0.localIdentifier) { continue }
                
                var currentGroup = [a1.0]
                processed.insert(a1.0.localIdentifier)
                
                for j in (i + 1)..<featurePrints.count {
                    let a2 = featurePrints[j]
                    if processed.contains(a2.0.localIdentifier) { continue }
                    
                    var distance: Float = 0
                    try? a1.1.computeDistance(&distance, to: a2.1)
                    if distance < similarityThreshold {
                        currentGroup.append(a2.0)
                        processed.insert(a2.0.localIdentifier)
                    }
                }
                
                if currentGroup.count > 1 {
                    let wrapped = currentGroup.map { GalleryAsset(asset: $0, fileSize: getFileSize(for: $0)) }
                    similarGroups.append(AssetGroup(assets: wrapped))
                }
            }
        }
        
        return similarGroups
    }
    
    // MARK: - Helpers
    func calculateTotalLibrarySize() -> Int64 {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let allAssets = PHAsset.fetchAssets(with: options)
        var totalSize: Int64 = 0
        for i in 0..<allAssets.count {
            let asset = allAssets.object(at: i)
            let resources = PHAssetResource.assetResources(for: asset)
            if let primary = resources.first(where: { $0.type == .video || $0.type == .photo }) ?? resources.first {
                totalSize += (primary.value(forKey: "fileSize") as? Int64) ?? 0
            }
        }
        return totalSize
    }
    
    private func getFileSize(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        if let primary = resources.first(where: { $0.type == .video || $0.type == .photo }) ?? resources.first {
            return (primary.value(forKey: "fileSize") as? Int64) ?? 0
        }
        return 0
    }
}
