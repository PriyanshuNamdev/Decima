import SwiftUI
import Photos

/// Deletes the given assets (iOS shows its own confirmation first), then plays the clean-up:
/// each photo dissolves into dust made of its own colours, the dust is pulled into a storage
/// ring that fills as space is freed, and a confetti burst celebrates the result.
struct ClearingSpaceView: View {
    let assetsToDelete: [GalleryAsset]
    let onComplete: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        case confirming
        case clearing
        case done
        case cancelled(message: String?)
    }

    @State private var phase: Phase = .confirming

    // Showcase: the photos that visibly dissolve (a sample when deleting many)
    @State private var showcase: [GalleryAsset] = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var palettes: [String: [Color]] = [:]
    @State private var showcaseIndex = 0
    @State private var dissolveProgress: CGFloat = 0

    // Counters
    @State private var itemsCleared = 0
    @State private var bytesFreed: Int64 = 0

    // Particles
    @State private var dust: [DustParticle] = []
    @State private var confetti: [ConfettiPiece] = []

    private let totalItems: Int
    private let totalBytes: Int64

    // Stage geometry
    private static let stageSize: CGFloat = 300
    private static let ringDiameter: CGFloat = 240
    private static let cardSize: CGFloat = 120

    init(assetsToDelete: [GalleryAsset], onComplete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.assetsToDelete = assetsToDelete
        self.onComplete = onComplete
        self.onCancel = onCancel
        self.totalItems = assetsToDelete.count
        self.totalBytes = assetsToDelete.reduce(0) { $0 + $1.fileSize }
    }

    private var ringProgress: CGFloat {
        if phase == .done { return 1 }
        guard totalItems > 0 else { return 0 }
        if totalBytes > 0 { return CGFloat(bytesFreed) / CGFloat(totalBytes) }
        return CGFloat(itemsCleared) / CGFloat(totalItems)
    }

    var body: some View {
        ZStack {
            BackgroundGlowView()

            VStack(spacing: 28) {
                Spacer()
                stage
                statusText
                Spacer()
                actions
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            confettiLayer
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: itemsCleared)
        .sensoryFeedback(.success, trigger: phase == .done)
        .task {
            await run()
        }
    }

    // MARK: - Stage

    private var stage: some View {
        ZStack {
            // Storage ring
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 10)
                .frame(width: Self.ringDiameter, height: Self.ringDiameter)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    AngularGradient(colors: [.coralRed, .brightOrange, .mint, .coralRed], center: .center),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: Self.ringDiameter, height: Self.ringDiameter)
                .shadow(color: .coralRed.opacity(0.6), radius: 12)
                .animation(.smooth(duration: 0.5), value: ringProgress)

            switch phase {
            case .confirming, .clearing:
                cardStack
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.mint)
                    .transition(.symbolEffect(.drawOn))
            case .cancelled:
                Image(systemName: "photo.stack")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(Color.lightGray)
                    .transition(.scale.combined(with: .opacity))
            }

            dustLayer
        }
        .frame(width: Self.stageSize, height: Self.stageSize)
    }

    /// Up to three photos fanned out; the top one dissolves
    private var cardStack: some View {
        let visible = Array(showcase.enumerated().dropFirst(showcaseIndex).prefix(3))
        return ZStack {
            ForEach(visible.reversed(), id: \.element.id) { index, asset in
                let depth = index - showcaseIndex
                thumbnail(for: asset)
                    .frame(width: Self.cardSize, height: Self.cardSize)
                    .clipShape(.rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
                    .rotationEffect(.degrees(Double(depth) * 7))
                    .offset(x: CGFloat(depth) * 10, y: CGFloat(depth) * -6)
                    .scaleEffect(1 - CGFloat(depth) * 0.06)
                    // The top card hands over to the dissolving canvas once it starts breaking up
                    .opacity(depth == 0 && dissolveProgress > 0 ? (reduceMotion ? 1 - dissolveProgress : 0) : 1)
                    .overlay {
                        if depth == 0, dissolveProgress > 0, !reduceMotion {
                            DissolvingImage(image: thumbnails[asset.id], cardSize: Self.cardSize, progress: dissolveProgress)
                                .frame(width: Self.cardSize + DissolvingImage.margin * 2, height: Self.cardSize + DissolvingImage.margin * 2)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for asset: GalleryAsset) -> some View {
        if let image = thumbnails[asset.id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(Color.warmCharcoal)
        }
    }

    // MARK: - Particles

    private var dustLayer: some View {
        TimelineView(.animation(paused: dust.isEmpty)) { timeline in
            Canvas { context, _ in
                let now = timeline.date
                for particle in dust {
                    guard let state = particle.state(at: now) else { continue }
                    context.opacity = state.opacity
                    let rect = CGRect(x: state.position.x - particle.size / 2, y: state.position.y - particle.size / 2, width: particle.size, height: particle.size)
                    context.fill(Path(ellipseIn: rect), with: .color(particle.color))
                }
            }
        }
        .frame(width: Self.stageSize, height: Self.stageSize)
        .allowsHitTesting(false)
    }

    private var confettiLayer: some View {
        TimelineView(.animation(paused: confetti.isEmpty)) { timeline in
            Canvas { context, size in
                let now = timeline.date
                for piece in confetti {
                    guard let state = piece.state(at: now, in: size) else { continue }
                    var pieceContext = context
                    pieceContext.opacity = state.opacity
                    pieceContext.translateBy(x: state.position.x, y: state.position.y)
                    pieceContext.rotate(by: .radians(state.rotation))
                    pieceContext.scaleBy(x: 1, y: state.flip)
                    pieceContext.fill(
                        Path(roundedRect: CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2, width: piece.size.width, height: piece.size.height), cornerRadius: 1.5),
                        with: .color(piece.color)
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Text

    @ViewBuilder
    private var statusText: some View {
        VStack(spacing: 10) {
            switch phase {
            case .confirming:
                Text("Confirm to continue")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("iOS will ask you to confirm deleting \(totalItems) \(totalItems == 1 ? "item" : "items").")
                    .font(.subheadline)
                    .foregroundStyle(Color.lightGray)
                    .multilineTextAlignment(.center)

            case .clearing, .done:
                Text(phase == .done ? GalleryManager.formatSize(totalBytes) : GalleryManager.formatSize(bytesFreed).nonEmpty ?? "0 MB")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(bytesFreed)))
                    .animation(.snappy, value: bytesFreed)
                Text(phase == .done ? "freed — all clear" : "\(itemsCleared) of \(totalItems) items cleared")
                    .font(.headline)
                    .foregroundStyle(phase == .done ? .mint : Color.lightGray)
                    .contentTransition(.numericText(value: Double(itemsCleared)))
                    .animation(.snappy, value: itemsCleared)

                if phase == .done {
                    if let comparison = roomComparison {
                        Text(comparison)
                            .font(.subheadline)
                            .foregroundStyle(Color.softWhite)
                            .multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    Label("Deleted items stay in Recently Deleted for 30 days. Empty it in Photos to get the space back straight away.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Color.lightGray)
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

            case .cancelled(let message):
                Text("Nothing was deleted")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(message ?? "Your photos and videos are just as you left them.")
                    .font(.subheadline)
                    .foregroundStyle(Color.lightGray)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth, value: phase)
    }

    /// e.g. "That's room for about 800 more photos."
    private var roomComparison: String? {
        let averagePhoto: Int64 = 3_000_000
        let photos = totalBytes / averagePhoto
        guard photos >= 2 else { return nil }
        let rounded: Int64 = photos >= 1000 ? (photos / 100) * 100 : photos >= 100 ? (photos / 10) * 10 : photos
        return "That's room for about \(rounded.formatted()) more photos."
    }

    @ViewBuilder
    private var actions: some View {
        switch phase {
        case .done:
            Button(action: onComplete) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.coralRed)
            .transition(.opacity)
        case .cancelled:
            Button(action: onCancel) {
                Text("Back")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            .transition(.opacity)
        case .confirming, .clearing:
            // Keeps the layout steady while there is no button
            Color.clear.frame(height: 50)
        }
    }

    // MARK: - Sequence

    private func run() async {
        showcase = Array(assetsToDelete.prefix(8))
        await loadThumbnails()

        do {
            try await DeletionService.shared.deleteAssets(assetsToDelete)
        } catch {
            let cancelledByUser = (error as? PHPhotosError)?.code == .userCancelled
            withAnimation(.smooth) {
                phase = .cancelled(message: cancelledByUser ? nil : error.localizedDescription)
            }
            return
        }

        withAnimation(.smooth) { phase = .clearing }

        // Aim for roughly three seconds however many items there are
        let perItem = min(max(3.0 / Double(max(showcase.count, 1)), 0.35), 0.6)

        for index in showcase.indices {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                showcaseIndex = index
                dissolveProgress = 0
            }

            if !reduceMotion {
                emitDust(for: showcase[index], duration: perItem)
            }
            withAnimation(.easeIn(duration: perItem)) {
                dissolveProgress = 1
            }
            try? await Task.sleep(for: .seconds(perItem))

            let fraction = Double(index + 1) / Double(showcase.count)
            itemsCleared = Int((Double(totalItems) * fraction).rounded())
            bytesFreed = Int64(Double(totalBytes) * fraction)
        }

        // Let the last of the dust reach the ring
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.1 : 0.5))

        itemsCleared = totalItems
        bytesFreed = totalBytes
        withAnimation(.smooth(duration: 0.6)) {
            showcaseIndex = showcase.count
            phase = .done
        }
        if !reduceMotion {
            launchConfetti()
        }
    }

    private func loadThumbnails() async {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        for asset in showcase {
            let image: UIImage? = await withCheckedContinuation { continuation in
                manager.requestImage(for: asset.asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: options) { image, _ in
                    continuation.resume(returning: image)
                }
            }
            if let image {
                thumbnails[asset.id] = image
                palettes[asset.id] = Self.palette(from: image)
            }
        }
    }

    // MARK: - Particle Emission

    private func emitDust(for asset: GalleryAsset, duration: Double) {
        let now = Date()
        dust.removeAll { $0.isFinished(at: now) }

        let colors = palettes[asset.id].flatMap { $0.isEmpty ? nil : $0 } ?? [.coralRed, .brightOrange, .white]
        let center = CGPoint(x: Self.stageSize / 2, y: Self.stageSize / 2)
        let half = Self.cardSize / 2
        let radius = Self.ringDiameter / 2

        for _ in 0..<70 {
            // Follow the shader's left-to-right sweep
            let sweep = Double.random(in: 0...1)
            let start = CGPoint(
                x: center.x - half + CGFloat(sweep) * Self.cardSize + .random(in: -6...6),
                y: center.y + .random(in: -half...half)
            )
            let angle = Double.random(in: 0..<(2 * .pi))
            let end = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let control = CGPoint(x: start.x + .random(in: -50...70), y: start.y - .random(in: 40...110))

            dust.append(DustParticle(
                birth: now.addingTimeInterval(sweep * duration * 0.8),
                start: start,
                control: control,
                end: end,
                duration: .random(in: 0.8...1.3),
                color: colors.randomElement()!,
                size: .random(in: 1.5...3.5)
            ))
        }
    }

    private func launchConfetti() {
        let now = Date()
        let colors: [Color] = [.coralRed, .brightOrange, .burntOrange, .mint, .white, .yellow]
        confetti = (0..<120).map { _ in
            ConfettiPiece(
                birth: now.addingTimeInterval(.random(in: 0...0.25)),
                originX: .random(in: 0...1),
                velocity: CGVector(dx: .random(in: -60...60), dy: .random(in: 120...320)),
                spin: .random(in: -8...8),
                flipSpeed: .random(in: 4...10),
                sway: .random(in: 10...40),
                lifetime: .random(in: 2.4...3.6),
                color: colors.randomElement()!,
                size: CGSize(width: .random(in: 6...10), height: .random(in: 10...16))
            )
        }
    }

    /// A 4×4 sample of the image's colours, so the dust looks like it came from the photo
    private static func palette(from image: UIImage) -> [Color] {
        guard let cgImage = image.cgImage else { return [] }
        let side = 4
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }
        return stride(from: 0, to: pixels.count, by: 4).map { i in
            Color(red: Double(pixels[i]) / 255, green: Double(pixels[i + 1]) / 255, blue: Double(pixels[i + 2]) / 255)
        }
    }
}

// MARK: - Dissolve

/// Cuts the photo into a grid of tiles that drift up and to the right and fade,
/// sweeping from left to right as `progress` goes 0 → 1 (animatable, so it follows `withAnimation`).
private struct DissolvingImage: View, Animatable {
    let image: UIImage?
    let cardSize: CGFloat
    var progress: CGFloat
    
    /// Room around the card for the tiles to travel into
    static let margin: CGFloat = 80
    private static let gridCount = 20
    
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    
    var body: some View {
        Canvas { context, _ in
            guard let image else { return }
            let resolved = context.resolve(Image(uiImage: image))
            let card = CGRect(x: Self.margin, y: Self.margin, width: cardSize, height: cardSize)
            let imageRect = Self.aspectFill(image.size, in: card)
            let n = Self.gridCount
            let tile = cardSize / CGFloat(n)
            
            for row in 0..<n {
                for col in 0..<n {
                    let noise = Self.hash(row, col, 1)
                    let start = Double(col) / Double(n) * 0.55 + noise * 0.35
                    let t = min(max((Double(progress) * 1.25 - start) / 0.3, 0), 1)
                    guard t < 1 else { continue }
                    // Tiles also vanish at random as they travel
                    guard t * 0.9 < Self.hash(row, col, 4) else { continue }
                    
                    let jitterX = Self.hash(row, col, 2) - 0.5
                    let jitterY = Self.hash(row, col, 3) - 0.5
                    let dx = t * t * 60 + jitterX * t * 36
                    let dy = -1.6 * t * t * 60 + jitterY * t * 36
                    let tileRect = CGRect(x: card.minX + CGFloat(col) * tile, y: card.minY + CGFloat(row) * tile, width: tile + 0.5, height: tile + 0.5)
                    
                    var tileContext = context
                    tileContext.opacity = 1 - t
                    tileContext.translateBy(x: dx, y: dy)
                    tileContext.clip(to: Path(tileRect))
                    tileContext.draw(resolved, in: imageRect)
                }
            }
        }
    }
    
    private static func aspectFill(_ imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
    
    /// Stable pseudo-random value in 0..<1 per tile
    private static func hash(_ a: Int, _ b: Int, _ seed: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663 ^ seed &* 83_492_791)
        x ^= x >> 13
        x &*= 0x5bd1_e995
        x ^= x >> 15
        return Double(x % 10_000) / 10_000
    }
}

// MARK: - Particles

private struct DustParticle {
    let birth: Date
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint
    let duration: Double
    let color: Color
    let size: CGFloat

    func isFinished(at date: Date) -> Bool {
        date.timeIntervalSince(birth) > duration
    }

    /// Position along a curve into the ring, accelerating as it's pulled in
    func state(at date: Date) -> (position: CGPoint, opacity: Double)? {
        let elapsed = date.timeIntervalSince(birth)
        guard elapsed >= 0, elapsed <= duration else { return nil }
        let t = elapsed / duration
        let u = t * t
        let inv = 1 - u
        let x = inv * inv * start.x + 2 * inv * u * control.x + u * u * end.x
        let y = inv * inv * start.y + 2 * inv * u * control.y + u * u * end.y
        return (CGPoint(x: x, y: y), min(1, (1 - t) * 1.6))
    }
}

private struct ConfettiPiece {
    let birth: Date
    let originX: CGFloat
    let velocity: CGVector
    let spin: Double
    let flipSpeed: Double
    let sway: CGFloat
    let lifetime: Double
    let color: Color
    let size: CGSize

    /// Falls from just above the top of the screen with a little drift and flutter
    func state(at date: Date, in canvas: CGSize) -> (position: CGPoint, rotation: Double, flip: CGFloat, opacity: Double)? {
        let t = date.timeIntervalSince(birth)
        guard t >= 0, t <= lifetime else { return nil }
        let gravity: CGFloat = 260
        let x = originX * canvas.width + velocity.dx * t + sin(t * 3) * sway
        let y = -20 + velocity.dy * t + 0.5 * gravity * t * t
        let fade = t > lifetime - 0.6 ? (lifetime - t) / 0.6 : 1
        return (CGPoint(x: x, y: y), spin * t, CGFloat(cos(t * flipSpeed)), fade)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
