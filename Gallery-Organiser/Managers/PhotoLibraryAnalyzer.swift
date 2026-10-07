import Foundation
import Photos
import CryptoKit
import Vision
import UIKit

// Define a group of assets (for duplicates and similar)
struct AssetGroup: Identifiable {
    let id = UUID()
    let assets: [GalleryAsset]
}

actor PhotoLibraryAnalyzer {
    
    // MARK: - Screenshots
    func fetchScreenshots() -> [GalleryAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [GalleryAsset] = []
        result.enumerateObjects { (asset, _, _) in
            assets.append(GalleryAsset(asset: asset))
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
        result.enumerateObjects { (asset, _, _) in
            assets.append(GalleryAsset(asset: asset))
        }
        return assets
    }
    
    // MARK: - Large Videos
    func fetchLargeVideos() async -> [GalleryAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let result = PHAsset.fetchAssets(with: .video, options: options)
        
        var assetsWithSizes: [GalleryAsset] = []
        for i in 0..<result.count {
            let asset = result.object(at: i)
            let resources = PHAssetResource.assetResources(for: asset)
            if let primaryResource = resources.first(where: { $0.type == .video }) ?? resources.first {
                let size = (primaryResource.value(forKey: "fileSize") as? Int64) ?? 0
                assetsWithSizes.append(GalleryAsset(asset: asset, fileSize: size))
            }
        }
        
        assetsWithSizes.sort { $0.fileSize > $1.fileSize }
        return assetsWithSizes
    }
    
    // MARK: - Exact Duplicates (Photos & Videos)
    func findExactDuplicates(mediaType: PHAssetMediaType) async -> [AssetGroup] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let result = PHAsset.fetchAssets(with: mediaType, options: options)
        
        // 1. Group by exact file size and dimensions to avoid unnecessary hashing
        var candidateGroups: [String: [PHAsset]] = [:]
        for i in 0..<result.count {
            let asset = result.object(at: i)
            let resources = PHAssetResource.assetResources(for: asset)
            if let primary = resources.first {
                let size = (primary.value(forKey: "fileSize") as? Int64) ?? 0
                let key = "\(size)_\(asset.pixelWidth)x\(asset.pixelHeight)"
                candidateGroups[key, default: []].append(asset)
            }
        }
        
        // Filter out unique items
        let duplicateCandidates = candidateGroups.values.filter { $0.count > 1 }
        var duplicateGroups: [AssetGroup] = []
        
        let resourceManager = PHAssetResourceManager.default()
        
        // 2. Hash exact resources
        for candidates in duplicateCandidates {
            var hashToAssets: [String: [PHAsset]] = [:]
            
            for asset in candidates {
                let resources = PHAssetResource.assetResources(for: asset)
                guard let primary = resources.first else { continue }
                
                let hashString = await withCheckedContinuation { continuation in
                    var hasher = SHA256()
                    let options = PHAssetResourceRequestOptions()
                    options.isNetworkAccessAllowed = true // allow downloading from iCloud if needed
                    
                    resourceManager.requestData(for: primary, options: options, dataReceivedHandler: { data in
                        hasher.update(data: data)
                    }) { error in
                        if error == nil {
                            let digest = hasher.finalize()
                            let hexString = digest.compactMap { String(format: "%02x", $0) }.joined()
                            continuation.resume(returning: hexString)
                        } else {
                            continuation.resume(returning: UUID().uuidString) // random string if failed
                        }
                    }
                }
                
                hashToAssets[hashString, default: []].append(asset)
            }
            
            // Add actual duplicates
            for (_, exactMatches) in hashToAssets where exactMatches.count > 1 {
                let wrapped = exactMatches.map { GalleryAsset(asset: $0) }
                duplicateGroups.append(AssetGroup(assets: wrapped))
            }
        }
        
        return duplicateGroups
    }
    
    // MARK: - Similar Photos (Vision)
    func findSimilarPhotos() async -> [AssetGroup] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        // Exclude screenshots from similar photos
        options.predicate = NSPredicate(format: "(mediaSubtype & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        let result = PHAsset.fetchAssets(with: .image, options: options)
        
        // 1. Candidate Bucketing by Time (within 2 minutes) and Aspect Ratio
        var buckets: [[PHAsset]] = []
        var currentBucket: [PHAsset] = []
        var lastDate: Date?
        
        var allAssets: [PHAsset] = []
        for i in 0..<result.count { allAssets.append(result.object(at: i)) }
        allAssets.sort { ($0.creationDate ?? Date.distantPast) < ($1.creationDate ?? Date.distantPast) }
        
        for asset in allAssets {
            guard let date = asset.creationDate else { continue }
            if let last = lastDate, date.timeIntervalSince(last) > 120 {
                if currentBucket.count > 1 { buckets.append(currentBucket) }
                currentBucket = []
            }
            currentBucket.append(asset)
            lastDate = date
        }
        if currentBucket.count > 1 { buckets.append(currentBucket) }
        
        var similarGroups: [AssetGroup] = []
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.deliveryMode = .fastFormat // Fast for vision
        
        let similarityThreshold: Float = 10.0
        
        // 2. Vision comparison within buckets
        for bucket in buckets {
            var featurePrints: [(PHAsset, VNFeaturePrintObservation)] = []
            
            for asset in bucket {
                let print: VNFeaturePrintObservation? = await withCheckedContinuation { continuation in
                    imageManager.requestImage(for: asset, targetSize: CGSize(width: 256, height: 256), contentMode: .aspectFit, options: requestOptions) { image, _ in
                        guard let cgImage = image?.cgImage else {
                            continuation.resume(returning: nil)
                            return
                        }
                        let request = VNGenerateImageFeaturePrintRequest()
                        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                        do {
                            try handler.perform([request])
                            continuation.resume(returning: request.results?.first as? VNFeaturePrintObservation)
                        } catch {
                            continuation.resume(returning: nil)
                        }
                    }
                }
                if let print = print { featurePrints.append((asset, print)) }
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
                    do {
                        try a1.1.computeDistance(&distance, to: a2.1)
                        if distance < similarityThreshold {
                            currentGroup.append(a2.0)
                            processed.insert(a2.0.localIdentifier)
                        }
                    } catch {}
                }
                
                if currentGroup.count > 1 {
                    similarGroups.append(AssetGroup(assets: currentGroup.map { GalleryAsset(asset: $0) }))
                }
            }
        }
        return similarGroups
    }
    
    // MARK: - Overview Stats
    func fetchCategoryOverviewStats() -> (sizes: [MediaCategory: Int64], counts: [MediaCategory: Int]) {
        var sizes: [MediaCategory: Int64] = [:]
        var counts: [MediaCategory: Int] = [:]
        
        let screenOptions = PHFetchOptions()
        screenOptions.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        counts[.screenshots] = PHAsset.fetchAssets(with: .image, options: screenOptions).count
        counts[.videos] = PHAsset.fetchAssets(with: .video, options: PHFetchOptions()).count
        
        return (sizes, counts)
    }
}
