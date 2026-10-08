import SwiftUI

struct CleanUpView: View {
    let initialAssets: [GalleryAsset]
    let onComplete: (Set<String>) -> Void // Returns deleted asset IDs
    let onCancel: () -> Void

    @State private var session: CleanUpSession
    @State private var showHint = true

    // Card choreography
    @State private var dragProgress: CGFloat = 0
    @State private var swipeRequest: SwipeDirection?
    @State private var entryDirection: SwipeDirection?

    init(assets: [GalleryAsset], onComplete: @escaping (Set<String>) -> Void, onCancel: @escaping () -> Void) {
        self.initialAssets = assets
        self.onComplete = onComplete
        self.onCancel = onCancel
        self._session = State(initialValue: CleanUpSession(assets: assets))
    }

    private var reviewedFraction: CGFloat {
        guard !session.assets.isEmpty else { return 0 }
        return CGFloat(session.currentIndex) / CGFloat(session.assets.count)
    }

    var body: some View {
        ZStack {
            BackgroundGlowView()

            VStack(spacing: 0) {
                header

                if session.isFinished {
                    Spacer()
                    completionView
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    Spacer()
                } else {
                    cardsStack
                    actionButtons
                }
            }
            .animation(.smooth, value: session.isFinished)
        }
        .sensoryFeedback(.success, trigger: session.isFinished) { _, finished in finished }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .foregroundColor(.lightGray)

                Spacer()

                Text("\(session.currentIndex) of \(session.assets.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .contentTransition(.numericText(value: Double(session.currentIndex)))
                    .animation(.snappy, value: session.currentIndex)

                Spacer()

                // Balances the Cancel button so the counter stays centred
                Text("Cancel").hidden()
            }

            // Progress through the stack
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(Color.primaryGradient)
                        .frame(width: geo.size.width * reviewedFraction)
                        .animation(.smooth, value: reviewedFraction)
                }
            }
            .frame(height: 4)

            HStack(spacing: 6) {
                Image(systemName: "trash")
                Text("Marked: \(GalleryManager.formatSize(session.markedBytes).isEmpty ? "0 MB" : GalleryManager.formatSize(session.markedBytes)) · \(session.deletedAssetIDs.count) \(session.deletedAssetIDs.count == 1 ? "item" : "items")")
                    .contentTransition(.numericText(value: Double(session.markedBytes)))
            }
            .font(.footnote.weight(.medium))
            .foregroundColor(session.deletedAssetIDs.isEmpty ? .mutedDarkGray : .coralRed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy, value: session.markedBytes)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Cards

    private var cardsStack: some View {
        ZStack {
            // Next card waits underneath and only shows once the top card starts moving
            if let nextAsset = session.nextAsset, dragProgress > 0 {
                CleanUpCardView(asset: nextAsset)
                    .allowsHitTesting(false)
                    .scaleEffect(0.92 + 0.08 * dragProgress)
                    .opacity(Double(dragProgress))
                    .zIndex(0)
            }

            // Current card (on top)
            if let currentAsset = session.currentAsset {
                CleanUpCardView(
                    asset: currentAsset,
                    entryDirection: entryDirection,
                    swipeRequest: swipeRequest,
                    onDragProgress: { dragProgress = $0 },
                    onSwiped: handleSwipe
                )
                .zIndex(1)
                .id(currentAsset.id) // Fresh card state for each asset
            }

            if showHint {
                VStack {
                    Spacer()
                    Text("Swipe right or tap ♥ to keep · left or ✕ to delete")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.lightGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                }
                .padding(.bottom, 8)
                .allowsHitTesting(false)
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .padding(20)
    }

    private var actionButtons: some View {
        HStack(spacing: 28) {
            Button {
                swipeRequest = .delete
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.coralRed)
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Delete")

            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(session.history.isEmpty)
            .accessibilityLabel("Undo")

            Button {
                swipeRequest = .keep
            } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.mint)
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Keep")
        }
        .tint(.white)
        .disabled(session.currentAsset == nil)
        .padding(.bottom, 20)
    }

    // MARK: - Actions

    private func handleSwipe(_ direction: SwipeDirection) {
        if showHint {
            withAnimation {
                showHint = false
            }
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            swipeRequest = nil
            entryDirection = nil
            dragProgress = 0
            if direction == .keep {
                session.keepCurrent()
            } else {
                session.deleteCurrent()
            }
        }
    }

    private func undo() {
        guard let last = session.history.last else { return }
        // The card comes back from the side it was thrown to
        entryDirection = last.wasKept ? .keep : .delete
        swipeRequest = nil
        dragProgress = 0
        withAnimation(.smooth) {
            _ = session.undoLast()
        }
    }

    // MARK: - Completion

    private var completionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.mint)
                .symbolEffect(.bounce, value: session.isFinished)

            Text("You're all caught up")
                .font(.title2.bold())
                .foregroundColor(.white)

            VStack(spacing: 12) {
                summaryRow(title: "Reviewed", value: "\(session.totalReviewed)", color: .white)
                summaryRow(title: "Kept", value: "\(session.keptAssetIDs.count)", color: .mint)
                summaryRow(title: "Marked for deletion", value: "\(session.deletedAssetIDs.count)", color: .coralRed)
                if session.markedBytes > 0 {
                    summaryRow(title: "Space to free", value: GalleryManager.formatSize(session.markedBytes), color: .coralRed)
                }
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal, 40)

            HStack(spacing: 12) {
                Button {
                    undo()
                } label: {
                    Text("Back")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)

                Button {
                    onComplete(session.deletedAssetIDs)
                } label: {
                    Text(session.deletedAssetIDs.isEmpty ? "Done" : "Review \(session.deletedAssetIDs.count)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.coralRed)
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
    }

    private func summaryRow(title: String, value: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.callout)
                .foregroundColor(.lightGray)
            Spacer()
            Text(value)
                .font(.callout.bold())
                .fontDesign(.rounded)
                .foregroundColor(color)
        }
    }
}
