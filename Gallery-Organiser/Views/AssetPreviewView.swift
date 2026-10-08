import SwiftUI
import Photos
import AVKit

// MARK: - Media Pager

struct MediaPagerView: View {
    @State var assets: [GalleryAsset]
    @State var currentIndex: Int
    var onDelete: (GalleryAsset) -> Void
    /// Tells the presenting grid which item is showing, so closing zooms back into the right cell
    var onCurrentChange: (GalleryAsset) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var showControls = true
    @State private var showInfo = false
    @State private var favoriteOverrides: [String: Bool] = [:]
    @State private var shareItem: ShareItem?
    @State private var isPreparingShare = false
    @State private var playback = VideoPlayback()

    // Vertical swipe state
    @State private var isZoomed = false
    @State private var dragMode: DragMode?
    @State private var dragOffset: CGSize = .zero

    private enum DragMode {
        case dismiss    // swipe down: shrink and close the viewer
        case openInfo   // swipe up: show Info
        case closeInfo  // swipe down while Info is open: hide Info
    }

    private var currentAsset: GalleryAsset? {
        assets.indices.contains(currentIndex) ? assets[currentIndex] : nil
    }

    private var isFavorite: Bool {
        guard let item = currentAsset else { return false }
        return favoriteOverrides[item.id] ?? item.asset.isFavorite
    }

    /// Chrome hides while swiping down to close, like Photos
    private var controlsVisible: Bool {
        showControls && dragMode != .dismiss
    }

    /// 0 → 1 as the item is dragged down towards closing
    private var dismissProgress: CGFloat {
        guard dragMode == .dismiss else { return 0 }
        return min(max(dragOffset.height, 0) / 400, 1)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    // Fades out while swiping down so the library shows through behind
                    Color.black
                        .opacity(1 - dismissProgress)
                        .ignoresSafeArea()

                    if assets.isEmpty {
                        ContentUnavailableView("No Items", systemImage: "photo.on.rectangle")
                    } else {
                        pager
                            // Like Photos, the media slides into the top half while Info is open
                            .padding(.bottom, showInfo ? proxy.size.height * 0.5 : 0)
                            .animation(.smooth, value: showInfo)
                    }
                }
            }
            .navigationTitle(titleText)
            .navigationSubtitle(subtitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarVisibility(controlsVisible ? .visible : .hidden, for: .navigationBar, .bottomBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if controlsVisible {
                    VStack(spacing: 10) {
                        if currentAsset?.asset.mediaType == .video {
                            VideoControlsBar(playback: playback)
                        }
                        if assets.count > 1 {
                            ThumbnailScrubber(assets: assets, currentIndex: $currentIndex)
                        }
                    }
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
            }
            .statusBarHidden(!controlsVisible)
            .containerBackground(.clear, for: .navigation)
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .presentationBackground(.clear)
        .sheet(isPresented: $showInfo) {
            if let item = currentAsset {
                AssetInfoView(asset: item, isFavorite: isFavorite)
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .interactiveDismissDisabled() // our own swipe-down handles closing
        .onAppear { playback.load(currentAsset?.asset) }
        .onChange(of: currentIndex) {
            isZoomed = false
            playback.load(currentAsset?.asset)
            if let currentAsset { onCurrentChange(currentAsset) }
        }
        .onDisappear { playback.tearDown() }
    }

    private var pager: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(assets.enumerated()), id: \.element.id) { index, item in
                AssetPreviewContentView(
                    asset: item.asset,
                    isCurrent: index == currentIndex,
                    player: playback.assetID == item.id ? playback.player : nil,
                    onTap: toggleControls,
                    onZoomChange: { isZoomed = $0 }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .offset(dragOffset)
        .scaleEffect(1 - dismissProgress * 0.35)
        .ignoresSafeArea()
        .gesture(
            VerticalPanGesture(
                isEnabled: !isZoomed && !assets.isEmpty,
                onChanged: dragChanged,
                onEnded: dragEnded
            )
        )
    }

    // MARK: Vertical Swipes

    private func dragChanged(_ translation: CGSize) {
        if dragMode == nil {
            if showInfo {
                dragMode = translation.height > 0 ? .closeInfo : nil
            } else {
                dragMode = translation.height > 0 ? .dismiss : .openInfo
            }
        }

        switch dragMode {
        case .dismiss:
            // The item follows the finger freely
            dragOffset = translation
        case .openInfo:
            // Rubber-band upwards as a hint that Info is coming
            dragOffset = CGSize(width: 0, height: min(translation.height, 0) * 0.35)
        case .closeInfo:
            dragOffset = CGSize(width: 0, height: max(translation.height, 0) * 0.35)
        case nil:
            break
        }
    }

    private func dragEnded(_ translation: CGSize, _ velocity: CGSize) {
        let mode = dragMode
        dragMode = nil

        switch mode {
        case .dismiss:
            if translation.height > 120 || velocity.height > 900 {
                // Keep the current offset so the cover slides away from where the finger let go
                dragMode = .dismiss
                dismiss()
                return
            }
        case .openInfo:
            if translation.height < -60 || velocity.height < -500 {
                showInfo = true
            }
        case .closeInfo:
            if translation.height > 50 || velocity.height > 500 {
                showInfo = false
            }
        case nil:
            break
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            dragOffset = .zero
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Back", systemImage: "chevron.left") { dismiss() }
        }

        ToolbarItem(placement: .bottomBar) {
            Button(action: shareCurrent) {
                if isPreparingShare {
                    ProgressView()
                } else {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(currentAsset == nil || isPreparingShare)
        }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItemGroup(placement: .bottomBar) {
            Button(isFavorite ? "Unfavourite" : "Favourite", systemImage: isFavorite ? "heart.fill" : "heart", action: toggleFavorite)
                .contentTransition(.symbolEffect(.replace))
                .disabled(currentAsset == nil)

            Button("Info", systemImage: showInfo ? "info.circle.fill" : "info.circle") {
                showInfo.toggle()
            }
            .disabled(currentAsset == nil)
        }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            Button("Delete", systemImage: "trash", action: deleteCurrentAsset)
                .disabled(currentAsset == nil)
        }
    }

    private var titleText: String {
        guard let date = currentAsset?.asset.creationDate else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    private var subtitleText: String {
        guard let date = currentAsset?.asset.creationDate else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Actions

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
    }

    private func toggleFavorite() {
        guard let item = currentAsset else { return }
        let newValue = !isFavorite
        favoriteOverrides[item.id] = newValue

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest(for: item.asset).isFavorite = newValue
        }) { success, _ in
            if !success {
                Task { @MainActor in favoriteOverrides[item.id] = !newValue }
            }
        }
    }

    private func shareCurrent() {
        guard let item = currentAsset else { return }
        isPreparingShare = true
        Task {
            let url = try? await AssetExporter.exportForSharing(item.asset)
            isPreparingShare = false
            if let url {
                shareItem = ShareItem(url: url)
            }
        }
    }

    private func deleteCurrentAsset() {
        guard let item = currentAsset else { return }
        Task {
            do {
                try await DeletionService.shared.deleteAssets([item])
            } catch {
                // The user cancelled the system confirmation, or deletion failed
                return
            }
            onDelete(item)
            withAnimation {
                assets.removeAll { $0.id == item.id }
                if assets.isEmpty {
                    dismiss()
                } else {
                    currentIndex = min(currentIndex, assets.count - 1)
                }
            }
        }
    }
}

// MARK: - Thumbnail Scrubber

/// Photos-style filmstrip: narrow thumbnails with the current item expanded to its real
/// aspect ratio. Dragging the strip scrubs through the library.
struct ThumbnailScrubber: View {
    let assets: [GalleryAsset]
    @Binding var currentIndex: Int

    @State private var isScrubbing = false

    private let height: CGFloat = 38
    private let narrowWidth: CGFloat = 24
    private let spacing: CGFloat = 2
    private let expandedPadding: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: spacing) {
                        ForEach(Array(assets.enumerated()), id: \.element.id) { index, item in
                            let isExpanded = index == currentIndex && !isScrubbing
                            ScrubberThumbnail(asset: item.asset)
                                .frame(width: isExpanded ? expandedWidth(for: item.asset) : narrowWidth, height: height)
                                .clipShape(.rect(cornerRadius: isExpanded ? 3 : 1))
                                .padding(.horizontal, isExpanded ? expandedPadding : 0)
                                .id(index)
                                .onTapGesture {
                                    currentIndex = index
                                }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                // Inset so the first and last items can sit in the centre
                .contentMargins(.horizontal, max(0, geo.size.width / 2 - narrowWidth / 2), for: .scrollContent)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.x + geometry.contentInsets.leading
                } action: { _, offset in
                    // While scrubbing every item is the same width, so the centred item is offset / stride
                    guard isScrubbing, !assets.isEmpty else { return }
                    let index = Int((offset / (narrowWidth + spacing)).rounded())
                    let clamped = min(max(index, 0), assets.count - 1)
                    if clamped != currentIndex {
                        currentIndex = clamped
                    }
                }
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting, !isScrubbing {
                        withAnimation(.snappy(duration: 0.2)) { isScrubbing = true }
                    } else if phase == .idle, isScrubbing {
                        withAnimation(.snappy) {
                            isScrubbing = false
                            proxy.scrollTo(currentIndex, anchor: .center)
                        }
                    }
                }
                .onChange(of: currentIndex) { _, newIndex in
                    guard !isScrubbing else { return }
                    withAnimation(.snappy) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(currentIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(height: height)
        .sensoryFeedback(.selection, trigger: isScrubbing ? currentIndex : nil)
    }

    private func expandedWidth(for asset: PHAsset) -> CGFloat {
        guard asset.pixelHeight > 0 else { return height }
        let aspect = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
        return min(max(height * aspect, height * 0.6), height * 2)
    }
}

private struct ScrubberThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    private static let imageManager = PHCachingImageManager()

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .onAppear(perform: load)
    }

    private func load() {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        Self.imageManager.requestImage(for: asset, targetSize: CGSize(width: 160, height: 160), contentMode: .aspectFill, options: options) { result, _ in
            if let result {
                image = result
            }
        }
    }
}

// MARK: - Page Content

struct AssetPreviewContentView: View {
    let asset: PHAsset
    var isCurrent: Bool
    var player: AVPlayer?
    var onTap: () -> Void
    var onZoomChange: (Bool) -> Void = { _ in }

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if asset.mediaType == .video {
                ZStack {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                    if let player {
                        PlayerLayerView(player: player)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .onTapGesture(perform: onTap)
            } else if let image {
                ZoomableScrollView(contentSize: image.size, isActive: isCurrent, onSingleTap: onTap, onZoomChange: onZoomChange) {
                    Image(uiImage: image)
                        .resizable()
                }
            } else {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: onTap)
                    .overlay {
                        if failed {
                            ContentUnavailableView("Can’t Load Photo", systemImage: "exclamationmark.icloud")
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: asset.localIdentifier) {
            loadImage()
        }
    }

    private func loadImage() {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        // Opportunistic delivers a quick low-res frame first, then the sharp one, as Photos does
        options.deliveryMode = .opportunistic

        // Enough resolution for zooming without decoding a full 48 MP original
        let maxDimension: CGFloat = 4096
        let width = CGFloat(asset.pixelWidth)
        let height = CGFloat(asset.pixelHeight)
        let scale = min(1, maxDimension / max(width, height, 1))
        let targetSize = CGSize(width: width * scale, height: height * scale)

        PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { result, _ in
            DispatchQueue.main.async {
                if let result {
                    image = result
                } else if image == nil {
                    failed = true
                }
            }
        }
    }
}

// MARK: - Vertical Pan

/// A UIKit pan that only begins on mostly-vertical drags, so horizontal paging and
/// pinch/pan inside a zoomed photo keep working untouched.
struct VerticalPanGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var onChanged: (CGSize) -> Void
    var onEnded: (_ translation: CGSize, _ velocity: CGSize) -> Void

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
        let translation = recognizer.translation(in: recognizer.view)
        let size = CGSize(width: translation.x, height: translation.y)
        switch recognizer.state {
        case .changed:
            onChanged(size)
        case .ended, .cancelled, .failed:
            let velocity = recognizer.velocity(in: recognizer.view)
            onEnded(size, CGSize(width: velocity.x, height: velocity.y))
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = true

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x) * 1.2
        }
    }
}

// MARK: - Zooming

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private let contentSize: CGSize
    private let isActive: Bool
    private let onSingleTap: () -> Void
    private let onZoomChange: (Bool) -> Void
    private let content: Content

    init(contentSize: CGSize, isActive: Bool, onSingleTap: @escaping () -> Void, onZoomChange: @escaping (Bool) -> Void = { _ in }, @ViewBuilder content: () -> Content) {
        self.contentSize = contentSize
        self.isActive = isActive
        self.onSingleTap = onSingleTap
        self.onZoomChange = onZoomChange
        self.content = content()
    }

    func makeUIView(context: Context) -> CenteringScrollView {
        let scrollView = CenteringScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5
        scrollView.minimumZoomScale = 1
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.backgroundColor = .clear

        let host = context.coordinator.hostingController
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        scrollView.addSubview(host.view)
        scrollView.hostedView = host.view
        scrollView.mediaSize = contentSize

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: CenteringScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onZoomChange = onZoomChange
        context.coordinator.isActive = isActive
        if scrollView.mediaSize != contentSize {
            scrollView.mediaSize = contentSize
            scrollView.setNeedsLayout()
        }
        // Photos resets zoom once you swipe to another item
        if !isActive && scrollView.zoomScale != scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: content), onSingleTap: onSingleTap, onZoomChange: onZoomChange)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let hostingController: UIHostingController<Content>
        var onSingleTap: () -> Void
        var onZoomChange: (Bool) -> Void
        var isActive = false
        private var isZoomed = false

        init(hostingController: UIHostingController<Content>, onSingleTap: @escaping () -> Void, onZoomChange: @escaping (Bool) -> Void) {
            self.hostingController = hostingController
            self.onSingleTap = onSingleTap
            self.onZoomChange = onZoomChange
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.setNeedsLayout()
            // Only the visible page reports, and only on change (off-screen pages are reset mid-update)
            let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
            guard isActive, zoomed != isZoomed else {
                isZoomed = zoomed
                return
            }
            isZoomed = zoomed
            onZoomChange(zoomed)
        }

        @objc func handleSingleTap() {
            onSingleTap()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView, let view = hostingController.view else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: view)
                let scale = min(scrollView.maximumZoomScale, 2.5)
                let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
                let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

/// Sizes the zoomable view to the image's fitted rect (so letterboxing is never zoomed)
/// and keeps it centred while zooming.
final class CenteringScrollView: UIScrollView {
    weak var hostedView: UIView?
    var mediaSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let hostedView, bounds.width > 0, bounds.height > 0 else { return }

        if zoomScale == minimumZoomScale {
            let fitted = AVMakeRect(aspectRatio: mediaSize == .zero ? bounds.size : mediaSize, insideRect: bounds).size
            if hostedView.bounds.size != fitted {
                hostedView.bounds = CGRect(origin: .zero, size: fitted)
                contentSize = fitted
            }
        }

        let offsetX = max((bounds.width - contentSize.width) / 2, 0)
        let offsetY = max((bounds.height - contentSize.height) / 2, 0)
        hostedView.center = CGPoint(x: contentSize.width / 2 + offsetX, y: contentSize.height / 2 + offsetY)
    }
}

// MARK: - Video

@MainActor
@Observable
final class VideoPlayback {
    let player = AVPlayer()
    private(set) var assetID: String?
    var isPlaying = false
    var isMuted = false
    var currentTime: Double = 0
    var duration: Double = 0
    var isSeeking = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var requestID: PHImageRequestID?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                self.currentTime = time.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.isPlaying = false
                self.currentTime = 0
                self.player.seek(to: .zero)
            }
        }
    }

    /// Swaps the single shared player to the given asset, and autoplays it if it's a video.
    func load(_ asset: PHAsset?) {
        guard asset?.localIdentifier != assetID else { return }

        pause()
        player.replaceCurrentItem(with: nil)
        currentTime = 0
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }

        guard let asset, asset.mediaType == .video else {
            assetID = nil
            duration = 0
            return
        }

        let id = asset.localIdentifier
        assetID = id
        duration = asset.duration

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        requestID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.assetID == id, let item else { return }
                self.player.replaceCurrentItem(with: item)
                self.play()
            }
        }
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        player.isMuted = isMuted
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }

    func seek(to seconds: Double, precise: Bool) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance: CMTime = precise ? .zero : CMTime(seconds: 0.1, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    func tearDown() {
        pause()
        player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
    }
}

struct VideoControlsBar: View {
    let playback: VideoPlayback

    var body: some View {
        HStack(spacing: 12) {
            Button {
                playback.togglePlay()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            Text(Self.format(playback.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Slider(value: timeBinding, in: 0...max(playback.duration, 0.1)) { editing in
                playback.isSeeking = editing
                if !editing {
                    playback.seek(to: playback.currentTime, precise: true)
                }
            }

            Text("-" + Self.format(max(playback.duration - playback.currentTime, 0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                playback.toggleMute()
            } label: {
                Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.body)
                    .frame(width: 28, height: 28)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(playback.isMuted ? "Unmute" : "Mute")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
    }

    private var timeBinding: Binding<Double> {
        Binding(
            get: { playback.currentTime },
            set: { newValue in
                playback.currentTime = newValue
                playback.seek(to: newValue, precise: false)
            }
        )
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Sharing

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum AssetExporter {
    /// Writes the asset (edited version if there is one) to a temp file named like the original.
    static func exportForSharing(_ asset: PHAsset) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: asset)
        let original = resources.first { $0.type == .photo || $0.type == .video } ?? resources.first
        let preferredTypes: [PHAssetResourceType] = [.fullSizePhoto, .fullSizeVideo, .photo, .video]
        guard let original,
              let resource = preferredTypes.lazy.compactMap({ type in resources.first { $0.type == type } }).first
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        let baseName = (original.originalFilename as NSString).deletingPathExtension
        let ext = (resource.originalFilename as NSString).pathExtension
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Share", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(baseName).appendingPathExtension(ext)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
        return url
    }
}
