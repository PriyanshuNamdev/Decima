import SwiftUI
import Photos

struct CategoryDetailView: View {
    let category: MediaCategory
    
    @State private var flatAssets: [GalleryAsset] = []
    @State private var assetGroups: [AssetGroup] = []
    @State private var isLoading = true
    
    @State private var selectedAssetIDs = Set<String>()
    
    // Derived properties for UI
    var totalCount: Int {
        flatAssets.count + assetGroups.reduce(0) { $0 + $1.assets.count }
    }
    
    var totalSize: Int64 {
        flatAssets.reduce(0) { $0 + $1.fileSize } + assetGroups.reduce(0) { $0 + $1.assets.reduce(0) { sum, a in sum + a.fileSize } }
    }
    
    var selectedSize: Int64 {
        var size: Int64 = 0
        let allAssets = flatAssets + assetGroups.flatMap { $0.assets }
        for asset in allAssets {
            if selectedAssetIDs.contains(asset.id) {
                size += asset.fileSize
            }
        }
        return size
    }
    
    // Group flat assets by date
    var dateGroups: [(String, [GalleryAsset])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.doesRelativeDateFormatting = true
        
        var dict: [String: [GalleryAsset]] = [:]
        for asset in flatAssets {
            let dateStr = asset.asset.creationDate.map { formatter.string(from: $0) } ?? "Unknown Date"
            dict[dateStr, default: []].append(asset)
        }
        
        // Sort keys by the latest date (simplified: just keeping them as they are, but normally you'd sort by actual Date)
        return dict.map { ($0.key, $0.value) }.sorted { $0.1.first?.asset.creationDate ?? .distantPast > $1.1.first?.asset.creationDate ?? .distantPast }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.nearBlack.ignoresSafeArea()
            
            if isLoading {
                ProgressView("Analyzing...")
                    .tint(.coralRed)
                    .foregroundColor(.lightGray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if totalCount == 0 {
                VStack(spacing: 12) {
                    Image(systemName: category.iconSystemName)
                        .font(.system(size: 40))
                        .foregroundColor(.mutedDarkGray)
                    Text("No items found")
                        .font(.headline)
                        .foregroundColor(.lightGray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerView
                        
                        if !flatAssets.isEmpty {
                            flatAssetsView
                        }
                        
                        if !assetGroups.isEmpty {
                            assetGroupsView
                        }
                        
                        Spacer().frame(height: 100) // Padding for bottom bar
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            
            if !selectedAssetIDs.isEmpty {
                bottomSelectionBar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.nearBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await loadData()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.deepBrownBlack)
                        .frame(width: 44, height: 44)
                    Image(systemName: category.iconSystemName)
                        .foregroundColor(.coralRed)
                        .font(.system(size: 20))
                }
                Text(category.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.softWhite)
            }
            
            Text("\(totalCount) items • \(GalleryManager.formatSize(totalSize))")
                .font(.system(size: 15))
                .foregroundColor(.lightGray)
            
            if !assetGroups.isEmpty {
                HStack(alignment: .top) {
                    Image(systemName: "checkmark.square.fill")
                        .foregroundColor(.mutedDarkGray)
                    Text("Exact copies only. Keep one original in each group; select the extra copies to delete.")
                        .font(.system(size: 13))
                        .foregroundColor(.lightGray)
                }
                .padding()
                .background(Color.deepBrownBlack)
                .cornerRadius(12)
                .padding(.top, 8)
                
                HStack {
                    Text("\(assetGroups.count) exact-match groups")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.softWhite)
                    Spacer()
                    Button("Select extras") {
                        selectAllExtras()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.coralRed)
                }
                .padding(.top, 16)
            } else {
                HStack {
                    Text("All items")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.softWhite)
                    Spacer()
                    Button(selectedAssetIDs.count == totalCount ? "Deselect all" : "Select all") {
                        if selectedAssetIDs.count == totalCount {
                            selectedAssetIDs.removeAll()
                        } else {
                            selectedAssetIDs = Set(flatAssets.map { $0.id })
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.coralRed)
                }
                .padding(.top, 16)
            }
        }
    }
    
    // MARK: - Flat Assets View (Screenshots/Videos)
    private var flatAssetsView: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(dateGroups, id: \.0) { dateStr, assets in
                VStack(alignment: .leading, spacing: 12) {
                    Text(dateStr)
                        .font(.system(size: 14))
                        .foregroundColor(.lightGray)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(assets) { asset in
                            selectableAssetThumbnail(asset: asset)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Asset Groups View (Duplicates)
    private var assetGroupsView: some View {
        LazyVStack(spacing: 24) {
            ForEach(Array(assetGroups.enumerated()), id: \.element.id) { index, group in
                let groupSize = group.assets.reduce(0) { $0 + $1.fileSize }
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Group \(index + 1)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.softWhite)
                        Spacer()
                        Text("\(group.assets.count) copies • \(GalleryManager.formatSize(groupSize))")
                            .font(.system(size: 12))
                            .foregroundColor(.mutedDarkGray)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(group.assets.enumerated()), id: \.element.id) { aIndex, asset in
                                ZStack(alignment: .bottomLeading) {
                                    selectableAssetThumbnail(asset: asset, width: 140, height: 100)
                                    
                                    if aIndex == 0 {
                                        Text("Keep original")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(4)
                                            .padding(8)
                                    }
                                }
                            }
                        }
                    }
                    
                    HStack {
                        Text("Original stays in library")
                            .font(.system(size: 12))
                            .foregroundColor(.mutedDarkGray)
                        Spacer()
                        let selectedInGroup = group.assets.filter { selectedAssetIDs.contains($0.id) }.count
                        if selectedInGroup > 0 {
                            Text("\(selectedInGroup) selected to delete")
                                .font(.system(size: 12))
                                .foregroundColor(.coralRed)
                        }
                    }
                }
                .padding(16)
                .background(Color.deepBrownBlack)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.charcoalBorder, lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Selectable Thumbnail
    private func selectableAssetThumbnail(asset: GalleryAsset, width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        let isSelected = selectedAssetIDs.contains(asset.id)
        
        return ZStack(alignment: .topTrailing) {
            AssetThumbnailView(asset: asset.asset, size: CGSize(width: width ?? 120, height: height ?? 120))
                .frame(width: width, height: height)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.coralRed : Color.clear, lineWidth: 3)
                )
            
            // Checkmark circle
            ZStack {
                Circle()
                    .fill(isSelected ? Color.coralRed : Color.black.opacity(0.4))
                    .frame(width: 24, height: 24)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(6)
        }
        .onTapGesture {
            if isSelected {
                selectedAssetIDs.remove(asset.id)
            } else {
                selectedAssetIDs.insert(asset.id)
            }
        }
    }
    
    // MARK: - Bottom Bar
    private var bottomSelectionBar: some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(selectedAssetIDs.count) selected")
                    .font(.system(size: 14))
                    .foregroundColor(.lightGray)
                Spacer()
                Text(GalleryManager.formatSize(selectedSize))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.softWhite)
            }
            
            Button(action: {
                // Trigger delete
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Review \(selectedAssetIDs.count) selected")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.primaryGradient)
                .cornerRadius(16)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.nearBlack.opacity(0.95))
        // separator line
        .overlay(
            Rectangle()
                .fill(Color.charcoalBorder)
                .frame(height: 1),
            alignment: .top
        )
    }
    
    // MARK: - Logic
    private func selectAllExtras() {
        for group in assetGroups {
            // keep the first one, select the rest
            for asset in group.assets.dropFirst() {
                selectedAssetIDs.insert(asset.id)
            }
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
