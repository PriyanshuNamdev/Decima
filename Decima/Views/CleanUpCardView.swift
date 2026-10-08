import SwiftUI
import Photos

enum SwipeDirection: Equatable {
    case keep    // right
    case delete  // left

    var sign: CGFloat { self == .keep ? 1 : -1 }
}

struct CleanUpCardView: View {
    let asset: GalleryAsset
    /// Set when the card returns via Undo, so it slides back in from the side it left
    var entryDirection: SwipeDirection? = nil
    /// Set by the Keep / Delete buttons to throw the card programmatically
    var swipeRequest: SwipeDirection? = nil
    var onDragProgress: (CGFloat) -> Void = { _ in }
    var onSwiped: (SwipeDirection) -> Void = { _ in }

    @State private var offset: CGSize = .zero
    @State private var image: UIImage? = nil
    @State private var isFlying = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let swipeThreshold: CGFloat = 100.0

    /// 0 → 1 as the card approaches the keep/delete point
    private var progress: CGFloat {
        min(abs(offset.width) / swipeThreshold, 1)
    }

    private var leaning: SwipeDirection? {
        offset.width == 0 ? nil : (offset.width > 0 ? .keep : .delete)
    }

    /// Changes when the card crosses the threshold, for the haptic tick
    private var committedDirection: SwipeDirection? {
        abs(offset.width) >= swipeThreshold ? leaning : nil
    }

    var body: some View {
        GeometryReader { geo in
            let cardSize = fittedSize(in: geo.size)

            card(size: cardSize)
                .offset(x: offset.width, y: offset.height * 0.2)
                .rotationEffect(.degrees(Double(offset.width / max(geo.size.width, 1)) * 15), anchor: .bottom)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            guard !isFlying else { return }
                            offset = gesture.translation
                        }
                        .onEnded { gesture in
                            guard !isFlying else { return }
                            let predicted = gesture.predictedEndTranslation.width
                            if offset.width > swipeThreshold || predicted > swipeThreshold * 3 {
                                flyOff(.keep, width: geo.size.width, velocityY: gesture.predictedEndTranslation.height)
                            } else if offset.width < -swipeThreshold || predicted < -swipeThreshold * 3 {
                                flyOff(.delete, width: geo.size.width, velocityY: gesture.predictedEndTranslation.height)
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    offset = .zero
                                }
                            }
                        }
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .task {
                    await loadImage(targetSize: cardSize)
                }
                .onAppear {
                    guard let entryDirection, !reduceMotion else { return }
                    offset = CGSize(width: entryDirection.sign * geo.size.width * 1.4, height: 0)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        offset = .zero
                    }
                }
                .onChange(of: swipeRequest) { _, request in
                    if let request {
                        flyOff(request, width: geo.size.width, velocityY: 0)
                    }
                }
        }
        .sensoryFeedback(.selection, trigger: committedDirection)
        .onChange(of: offset.width) {
            onDragProgress(progress)
        }
    }

    /// The card takes the media's own aspect ratio, fitted inside the available space.
    private func card(size: CGSize) -> some View {
        let labelSize = min(40, size.width / 7)
        let glowColor: Color = leaning == .keep ? .mint : .coralRed

        return ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.deepBrownBlack)
                .shadow(radius: 5)

            if let uiImage = image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            } else {
                ProgressView()
                    .tint(.coralRed)
            }

            // Tint washes in the direction of the swipe
            RoundedRectangle(cornerRadius: 24)
                .fill(glowColor.opacity(0.18 * progress))
        }
        .frame(width: size.width, height: size.height)
        // Edge glow that strengthens as the card nears the keep/delete point
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(glowColor.opacity(progress), lineWidth: 4)
        )
        .shadow(color: glowColor.opacity(0.7 * progress), radius: 24 * progress)
        // Indicators
        .overlay(alignment: .topLeading) {
            if offset.width > 0 {
                Text("KEEP")
                    .font(.system(size: labelSize, weight: .bold))
                    .foregroundColor(.mint)
                    .padding(labelSize * 0.3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.mint, lineWidth: 4)
                    )
                    .rotationEffect(.degrees(-15))
                    .opacity(Double(offset.width / swipeThreshold))
                    .padding(24)
            }
        }
        .overlay(alignment: .topTrailing) {
            if offset.width < 0 {
                Text("DELETE")
                    .font(.system(size: labelSize, weight: .bold))
                    .foregroundColor(.coralRed)
                    .padding(labelSize * 0.3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.coralRed, lineWidth: 4)
                    )
                    .rotationEffect(.degrees(15))
                    .opacity(Double(-offset.width / swipeThreshold))
                    .padding(24)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if asset.asset.mediaType == .video {
                Label(formatDuration(asset.asset.duration), systemImage: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding()
            }
        }
    }

    /// Throws the card off-screen in the swipe direction, carrying the flick's momentum
    private func flyOff(_ direction: SwipeDirection, width: CGFloat, velocityY: CGFloat) {
        guard !isFlying else { return }
        isFlying = true
        let duration = reduceMotion ? 0.15 : 0.28
        withAnimation(.easeOut(duration: duration)) {
            offset = CGSize(width: direction.sign * width * 1.5, height: offset.height + velocityY * 0.3)
        }
        Task {
            try? await Task.sleep(for: .seconds(duration * 0.85))
            onSwiped(direction)
        }
    }

    private func fittedSize(in container: CGSize) -> CGSize {
        let pixelWidth = CGFloat(asset.asset.pixelWidth)
        let pixelHeight = CGFloat(asset.asset.pixelHeight)
        guard pixelWidth > 0, pixelHeight > 0, container.width > 0, container.height > 0 else { return container }

        let aspect = pixelWidth / pixelHeight
        var width = container.width
        var height = width / aspect
        if height > container.height {
            height = container.height
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }

    private func loadImage(targetSize: CGSize) async {
        let manager = PHCachingImageManager.default()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        let size = CGSize(width: targetSize.width * displayScale, height: targetSize.height * displayScale)

        manager.requestImage(for: asset.asset, targetSize: size, contentMode: .aspectFit, options: options) { result, _ in
            if let result = result {
                DispatchQueue.main.async {
                    self.image = result
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}
