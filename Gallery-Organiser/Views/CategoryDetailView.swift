import SwiftUI
import Photos

struct CategoryDetailView: View {
    let category: MediaCategory

    @State private var flatAssets: [GalleryAsset] = []
    @State private var assetGroups: [AssetGroup] = []
    @State private var isLoading = true

    @State private var selectedAssetIDs = Set<String>()
    @State private var previewInitialIndex: Int = 0
    @State private var showMediaPager = false
    @State private var showCleanUp = false
    @State private var isSelectionMode = false
    @State private var deletionBatch: DeletionBatch?

    /// Copies the user chose to keep instead of the automatic "Best" pick (survives regrouping after deletes)
    @State private var keeperOverrides = Set<String>()

    // Zoom transition between a thumbnail and the viewer
    @Namespace private var zoomNamespace
    @State private var zoomSourceID = ""
    @State private var scrollTargetID: String?

    // Drag-to-select
    @State private var cellFrames = CellFrameStore()
    @State private var dragSelection: DragSelection?

    private struct DragSelection {
        let anchorIndex: Int
        let isSelecting: Bool
        let baseSelection: Set<String>
    }

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

    /// Space freed by deleting everything except the kept copy in each group
    var reclaimableSize: Int64 {
        assetGroups.reduce(0) { total, group in
            let keeper = keeper(of: group)
            return total + group.assets.filter { $0.id != keeper.id }.reduce(0) { $0 + $1.fileSize }
        }
    }

    var allAssetsOrdered: [GalleryAsset] {
        if !flatAssets.isEmpty {
            let groups = category == .largeVideos ? sizeGroups : dateGroups
            return groups.flatMap { $0.1 }
        } else {
            return assetGroups.flatMap { orderedAssets(in: $0) }
        }
    }

    // Group flat assets by date
    var dateGroups: [(String, [GalleryAsset])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        var dict: [String: [GalleryAsset]] = [:]
        for asset in flatAssets {
            let dateStr = asset.asset.creationDate.map { formatter.string(from: $0) } ?? "Unknown Date"
            dict[dateStr, default: []].append(asset)
        }

        return dict.map { ($0.key, $0.value) }.sorted { $0.1.first?.asset.creationDate ?? .distantPast > $1.1.first?.asset.creationDate ?? .distantPast }
    }

    var sizeGroups: [(String, [GalleryAsset])] {
        var dict: [String: [GalleryAsset]] = [:]

        // Decimal units, to match the sizes shown on each thumbnail
        let gb1: Int64 = 1_000_000_000
        let mb500: Int64 = 500_000_000

        // Large Videos only contains videos of 100 MB and up
        for asset in flatAssets {
            if asset.fileSize >= gb1 {
                dict["Larger than 1 GB", default: []].append(asset)
            } else if asset.fileSize >= mb500 {
                dict["500 MB - 1 GB", default: []].append(asset)
            } else {
                dict["100 MB - 500 MB", default: []].append(asset)
            }
        }

        let order = ["Larger than 1 GB", "500 MB - 1 GB", "100 MB - 500 MB"]
        var result: [(String, [GalleryAsset])] = []
        for key in order {
            if let assets = dict[key] {
                let sortedAssets = assets.sorted { $0.fileSize > $1.fileSize }
                result.append((key, sortedAssets))
            }
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.nearBlack.ignoresSafeArea()

            if isLoading {
                SkeletonGrid()
            } else if totalCount == 0 {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            headerView

                            if !flatAssets.isEmpty {
                                flatAssetsView
                            }

                            if !assetGroups.isEmpty {
                                assetGroupsView
                            }

                            Spacer().frame(height: 120) // Padding for bottom bar
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .coordinateSpace(.named(Self.gridSpace))
                        .gesture(
                            SelectionPanGesture(
                                isEnabled: isSelectionMode,
                                coordinateSpace: .named(Self.gridSpace),
                                onBegan: dragSelectBegan,
                                onChanged: dragSelectChanged,
                                onEnded: { dragSelection = nil }
                            )
                        )
                    }
                    .onChange(of: scrollTargetID) { _, id in
                        // Keep the item shown in the viewer on screen, so closing zooms back into it
                        if let id {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }

            if !selectedAssetIDs.isEmpty {
                bottomSelectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selectedAssetIDs.isEmpty)
        .sensoryFeedback(.selection, trigger: selectedAssetIDs.count) { _, _ in dragSelection != nil }
        .navigationTitle(isSelectionMode ? "Select Items" : category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if totalCount > 0 {
                    Button(isSelectionMode ? "Cancel" : "Select") {
                        withAnimation(.snappy) {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedAssetIDs.removeAll()
                            }
                        }
                    }
                    .foregroundColor(isSelectionMode ? .coralRed : .white)
                }
            }
        }
        .task {
            await loadData()
        }
        .fullScreenCover(isPresented: $showMediaPager) {
            MediaPagerView(
                assets: allAssetsOrdered,
                currentIndex: previewInitialIndex,
                onDelete: { deletedAsset in
                    removeLocally([deletedAsset.id])
                },
                onCurrentChange: { asset in
                    zoomSourceID = asset.id
                    scrollTargetID = asset.id
                }
            )
            .navigationTransition(.zoom(sourceID: zoomSourceID, in: zoomNamespace))
        }
        .fullScreenCover(isPresented: $showCleanUp) {
            CleanUpView(assets: flatAssets) { deletedIDs in
                selectedAssetIDs = deletedIDs
                if !deletedIDs.isEmpty {
                    isSelectionMode = true
                }
                showCleanUp = false
            } onCancel: {
                showCleanUp = false
            }
        }
        .fullScreenCover(item: $deletionBatch) { batch in
            ClearingSpaceView(assetsToDelete: batch.assets) {
                removeLocally(Set(batch.assets.map(\.id)))
                isSelectionMode = false
                deletionBatch = nil
            } onCancel: {
                deletionBatch = nil
            }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(totalCount) items • \(GalleryManager.formatSize(totalSize))")
                .font(.subheadline)
                .foregroundColor(.lightGray)
                .contentTransition(.numericText())

            if !assetGroups.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(assetGroups.count) \(category == .similarPhotos ? "similar" : "exact-match") groups")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.softWhite)
                        Text("\(GalleryManager.formatSize(reclaimableSize)) reclaimable")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.mint)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Button(allExtrasSelected ? "Deselect extras" : "Select extras") {
                        withAnimation(.snappy) {
                            toggleExtrasSelection()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.coralRed)
                    .contentTransition(.numericText())
                }
                .padding(.top, 16)
            } else {
                HStack {
                    Text("All items")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.softWhite)
                    Spacer()
                    if category == .screenshots || category == .videos || category == .largeVideos {
                        Button("Clean-Up") {
                            showCleanUp = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.coralRed)
                    } else {
                        Button(selectedAssetIDs.count == totalCount ? "Deselect all" : "Select all") {
                            isSelectionMode = true
                            if selectedAssetIDs.count == totalCount {
                                selectedAssetIDs.removeAll()
                            } else {
                                selectedAssetIDs = Set(flatAssets.map { $0.id })
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.coralRed)
                    }
                }
                .padding(.top, 16)
            }

            if isSelectionMode {
                Label("Drag sideways across photos to select several", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundColor(.mutedDarkGray)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        let (title, message): (String, String) = switch category {
        case .duplicatePhotos: ("No Duplicate Photos", "Every photo in your library is one of a kind. Nice!")
        case .duplicateVideos: ("No Duplicate Videos", "No exact copies found among your videos.")
        case .similarPhotos: ("No Similar Photos", "Nothing to tidy up here. Your shots are all different.")
        case .screenshots: ("No Screenshots", "Your library is screenshot-free.")
        case .videos: ("No Videos", "There are no videos in your library.")
        case .largeVideos: ("No Large Videos", "None of your videos are over 100 MB.")
        }
        return ContentUnavailableView {
            Label(title, systemImage: "checkmark.seal")
                .foregroundStyle(.mint)
        } description: {
            Text(message)
                .foregroundStyle(Color.lightGray)
        }
    }

    // MARK: - Flat Assets View (Screenshots/Videos)
    private var flatAssetsView: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            let groups = category == .largeVideos ? sizeGroups : dateGroups

            ForEach(groups, id: \.0) { groupTitle, assets in
                VStack(alignment: .leading, spacing: 12) {
                    Text(groupTitle)
                        .font(.subheadline)
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
                let keeper = keeper(of: group)
                let isAutoPick = !keeperOverrides.contains(keeper.id)
                let groupReclaimable = group.assets.filter { $0.id != keeper.id }.reduce(0) { $0 + $1.fileSize }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Group \(index + 1)")
                            .font(.callout.weight(.semibold))
                            .foregroundColor(.softWhite)
                        Spacer()
                        Text("\(group.assets.count) copies • \(GalleryManager.formatSize(groupReclaimable)) reclaimable")
                            .font(.caption)
                            .foregroundColor(.mutedDarkGray)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(orderedAssets(in: group)) { asset in
                            let isKeeper = asset.id == keeper.id
                            selectableAssetThumbnail(asset: asset)
                                .overlay(alignment: .bottomLeading) {
                                    if isKeeper {
                                        KeeperBadge(isAutoPick: isAutoPick)
                                            .padding(6)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .contextMenu {
                                    if !isKeeper {
                                        Button("Keep This Copy", systemImage: "star") {
                                            withAnimation(.snappy) {
                                                setKeeper(asset, in: group)
                                            }
                                        }
                                    }
                                } preview: {
                                    AssetThumbnailView(asset: asset.asset, size: CGSize(width: 300, height: 300))
                                        .frame(width: 300, height: 300)
                                }
                        }
                    }

                    let selectedInGroup = group.assets.filter { selectedAssetIDs.contains($0.id) }.count
                    HStack {
                        Text("Touch and hold a copy to keep it instead")
                            .font(.caption2)
                            .foregroundColor(.mutedDarkGray)
                        Spacer()
                        if selectedInGroup > 0 {
                            Text("\(selectedInGroup) selected to delete")
                                .font(.caption)
                                .foregroundColor(.coralRed)
                                .contentTransition(.numericText())
                        }
                    }
                }
                .padding(12)
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

        return AssetThumbnailView(asset: asset.asset, size: CGSize(width: width ?? 120, height: height ?? 120))
            .frame(width: width, height: height)
            .cornerRadius(8)
            .overlay {
                // Dim selected items, like Photos
                if isSelected && isSelectionMode {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.3))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected && isSelectionMode ? Color.coralRed : Color.clear, lineWidth: 3)
            )
            .overlay(alignment: .topTrailing) {
                if isSelectionMode {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.coralRed : Color.black.opacity(0.4))
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .transition(.scale)
                        }
                    }
                    .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if category == .largeVideos && asset.fileSize > 0 {
                    Text(GalleryManager.formatSize(asset.fileSize))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .padding(6)
                }
            }
            .animation(.snappy(duration: 0.2), value: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .matchedTransitionSource(id: asset.id, in: zoomNamespace)
            .id(asset.id)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.gridSpace))
            } action: { frame in
                cellFrames.frames[asset.id] = frame
            }
            .onTapGesture {
                if isSelectionMode {
                    if isSelected {
                        selectedAssetIDs.remove(asset.id)
                    } else {
                        selectedAssetIDs.insert(asset.id)
                    }
                } else {
                    openViewer(at: asset)
                }
            }
            .onLongPressGesture {
                if isSelectionMode {
                    openViewer(at: asset)
                }
            }
    }

    // MARK: - Bottom Bar
    private var bottomSelectionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedAssetIDs.count) selected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.softWhite)
                    .contentTransition(.numericText(value: Double(selectedAssetIDs.count)))
                Text(GalleryManager.formatSize(selectedSize))
                    .font(.footnote)
                    .fontDesign(.rounded)
                    .foregroundColor(.lightGray)
                    .contentTransition(.numericText(value: Double(selectedSize)))
            }
            .animation(.snappy, value: selectedAssetIDs.count)

            Spacer()

            Button {
                startDeletion()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(.coralRed)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Keepers

    /// The copy that stays in a group: the user's choice, otherwise the best-quality copy
    private func keeper(of group: AssetGroup) -> GalleryAsset {
        if let chosen = group.assets.first(where: { keeperOverrides.contains($0.id) }) {
            return chosen
        }
        return Self.bestAsset(in: group)
    }

    /// Keeper first, so the group reads "this one stays, these go"
    private func orderedAssets(in group: AssetGroup) -> [GalleryAsset] {
        let keeper = keeper(of: group)
        return [keeper] + group.assets.filter { $0.id != keeper.id }
    }

    /// Favourited beats edited beats higher resolution beats larger file
    static func bestAsset(in group: AssetGroup) -> GalleryAsset {
        func score(_ item: GalleryAsset) -> (Int, Int, Int, Int64) {
            (item.asset.isFavorite ? 1 : 0,
             item.asset.hasAdjustments ? 1 : 0,
             item.asset.pixelWidth * item.asset.pixelHeight,
             item.fileSize)
        }
        return group.assets.max { score($0) < score($1) } ?? group.assets[0]
    }

    private func setKeeper(_ asset: GalleryAsset, in group: AssetGroup) {
        let oldKeeper = keeper(of: group)
        let extrasWereSelected = group.assets.filter { $0.id != oldKeeper.id }.allSatisfy { selectedAssetIDs.contains($0.id) }

        keeperOverrides.subtract(group.assets.map(\.id))
        if asset.id != Self.bestAsset(in: group).id {
            keeperOverrides.insert(asset.id)
        }

        // Never leave the kept copy selected for deletion
        selectedAssetIDs.remove(asset.id)
        if extrasWereSelected {
            selectedAssetIDs.insert(oldKeeper.id)
        }
    }

    /// Every copy except the kept one in each group
    private var extraAssetIDs: Set<String> {
        Set(assetGroups.flatMap { group in
            let keeper = keeper(of: group)
            return group.assets.filter { $0.id != keeper.id }.map(\.id)
        })
    }

    private var allExtrasSelected: Bool {
        let extras = extraAssetIDs
        return !extras.isEmpty && extras.isSubset(of: selectedAssetIDs)
    }

    private func toggleExtrasSelection() {
        if allExtrasSelected {
            selectedAssetIDs.subtract(extraAssetIDs)
            if selectedAssetIDs.isEmpty {
                isSelectionMode = false
            }
        } else {
            isSelectionMode = true
            selectedAssetIDs.formUnion(extraAssetIDs)
        }
    }

    // MARK: - Drag to Select

    private static let gridSpace = "categoryGrid"

    private func assetIndex(at point: CGPoint, in ordered: [GalleryAsset]) -> Int? {
        guard let id = cellFrames.frames.first(where: { $0.value.contains(point) })?.key else { return nil }
        return ordered.firstIndex { $0.id == id }
    }

    private func dragSelectBegan(_ point: CGPoint) {
        let ordered = allAssetsOrdered
        guard let index = assetIndex(at: point, in: ordered) else { return }
        let isSelecting = !selectedAssetIDs.contains(ordered[index].id)
        dragSelection = DragSelection(anchorIndex: index, isSelecting: isSelecting, baseSelection: selectedAssetIDs)
        dragSelectChanged(point)
    }

    /// Selects (or deselects) the whole range between where the drag began and the finger, like Photos
    private func dragSelectChanged(_ point: CGPoint) {
        guard let drag = dragSelection else { return }
        let ordered = allAssetsOrdered
        guard let index = assetIndex(at: point, in: ordered) else { return }
        let range = min(drag.anchorIndex, index)...max(drag.anchorIndex, index)
        let rangeIDs = Set(ordered[range].map(\.id))
        let updated = drag.isSelecting ? drag.baseSelection.union(rangeIDs) : drag.baseSelection.subtracting(rangeIDs)
        if updated != selectedAssetIDs {
            selectedAssetIDs = updated
        }
    }

    // MARK: - Logic

    private func openViewer(at asset: GalleryAsset) {
        guard let index = allAssetsOrdered.firstIndex(where: { $0.id == asset.id }) else { return }
        zoomSourceID = asset.id
        previewInitialIndex = index
        showMediaPager = true
    }

    private func startDeletion() {
        let allAssets = flatAssets + assetGroups.flatMap { $0.assets }
        let assets = allAssets.filter { selectedAssetIDs.contains($0.id) }
        guard !assets.isEmpty else { return }
        deletionBatch = DeletionBatch(assets: assets)
    }

    private func removeLocally(_ ids: Set<String>) {
        withAnimation(.snappy) {
            flatAssets.removeAll { ids.contains($0.id) }

            var newGroups: [AssetGroup] = []
            for group in assetGroups {
                let remaining = group.assets.filter { !ids.contains($0.id) }
                if remaining.count > 1 {
                    newGroups.append(AssetGroup(assets: remaining))
                }
            }
            assetGroups = newGroups
            selectedAssetIDs.subtract(ids)
            keeperOverrides.subtract(ids)
        }
        for id in ids {
            cellFrames.frames[id] = nil
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

// MARK: - Supporting Types

struct DeletionBatch: Identifiable {
    let id = UUID()
    let assets: [GalleryAsset]
}

/// Cell frames for drag-to-select. A plain class so recording frames never re-renders the grid.
final class CellFrameStore {
    var frames: [String: CGRect] = [:]
}

private struct KeeperBadge: View {
    let isAutoPick: Bool

    var body: some View {
        Label(isAutoPick ? "Best" : "Keeping", systemImage: isAutoPick ? "star.fill" : "checkmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isAutoPick ? AnyShapeStyle(Color.primaryGradient) : AnyShapeStyle(Color.mint.opacity(0.85)), in: .capsule)
    }
}

/// Placeholder grid shown while a category is being analysed
struct SkeletonGrid: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 6)
                    .frame(width: 180, height: 14)
                RoundedRectangle(cornerRadius: 6)
                    .frame(width: 120, height: 14)
                    .padding(.top, 8)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(0..<15, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .foregroundStyle(Color.warmCharcoal)
            .padding(16)
            .shimmering()
        }
        .scrollDisabled(true)
        .accessibilityLabel("Analysing your library")
    }
}

/// A UIKit pan that only begins on sideways drags, so vertical scrolling is untouched
struct SelectionPanGesture<Space: CoordinateSpaceProtocol>: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var coordinateSpace: Space
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let location = context.converter.location(in: coordinateSpace)
        switch recognizer.state {
        case .began:
            onBegan(location)
        case .changed:
            onChanged(location)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = false

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }
    }
}
