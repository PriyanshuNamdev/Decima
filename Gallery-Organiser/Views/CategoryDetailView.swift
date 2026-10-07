import SwiftUI
import Photos

struct CategoryDetailView: View {
    let category: MediaCategory
    
    @State private var flatAssets: [GalleryAsset] = []
    @State private var assetGroups: [AssetGroup] = []
    @State private var isLoading = true
    
    let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 2)
    ]
    
    var body: some View {
        ZStack {
            Color.nearBlack.ignoresSafeArea()
            
            if isLoading {
                ProgressView("Analyzing...")
                    .tint(.coralRed)
                    .foregroundColor(.lightGray)
            } else if flatAssets.isEmpty && assetGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: category.iconSystemName)
                        .font(.system(size: 40))
                        .foregroundColor(.mutedDarkGray)
                    Text("No items found")
                        .font(.headline)
                        .foregroundColor(.lightGray)
                }
            } else {
                ScrollView {
                    if !flatAssets.isEmpty {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(flatAssets) { asset in
                                ZStack(alignment: .bottomTrailing) {
                                    AssetThumbnailView(asset: asset.asset, size: CGSize(width: 120, height: 120))
                                    
                                    if asset.fileSize > 0 {
                                        Text(GalleryManager.formatSize(asset.fileSize))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(4)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(4)
                                            .padding(4)
                                    }
                                }
                            }
                        }
                    }
                    
                    if !assetGroups.isEmpty {
                        VStack(spacing: 16) {
                            ForEach(assetGroups) { group in
                                VStack(alignment: .leading) {
                                    Text("Group")
                                        .font(.subheadline)
                                        .foregroundColor(.lightGray)
                                        .padding(.horizontal)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 2) {
                                            ForEach(group.assets) { asset in
                                                AssetThumbnailView(asset: asset.asset, size: CGSize(width: 120, height: 120))
                                                    .frame(width: 120, height: 120)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .background(Color.deepBrownBlack)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
    }
    
    private func loadData() async {
        let analyzer = PhotoLibraryAnalyzer()
        
        switch category {
        case .screenshots:
            let fetched = await analyzer.fetchScreenshots()
            await MainActor.run { self.flatAssets = fetched; self.isLoading = false }
        case .videos:
            let fetched = await analyzer.fetchVideos()
            await MainActor.run { self.flatAssets = fetched; self.isLoading = false }
        case .largeVideos:
            let fetched = await analyzer.fetchLargeVideos()
            await MainActor.run { self.flatAssets = fetched; self.isLoading = false }
        case .duplicatePhotos:
            let fetched = await analyzer.findExactDuplicates(mediaType: .image)
            await MainActor.run { self.assetGroups = fetched; self.isLoading = false }
        case .duplicateVideos:
            let fetched = await analyzer.findExactDuplicates(mediaType: .video)
            await MainActor.run { self.assetGroups = fetched; self.isLoading = false }
        case .similarPhotos:
            let fetched = await analyzer.findSimilarPhotos()
            await MainActor.run { self.assetGroups = fetched; self.isLoading = false }
        }
    }
}
