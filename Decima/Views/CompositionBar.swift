import SwiftUI

/// The library breakdown bar. Segments grow from the leading edge by animating one piece of state
/// (`shown`) that only feeds the segment shapes. Layout is fixed (full width, 6 pt tall), so nothing
/// can scale or slide vertically, whatever else on the card is animating at the same time.
struct CompositionBar: View {
    /// Each part's share of the whole, 0...1
    let shares: [Double]
    let opacities: [Double]
    let isReady: Bool

    @State private var shown: [Double] = []

    private static let height: CGFloat = 6

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Color.white.opacity(0.2))

            ForEach(opacities.indices, id: \.self) { index in
                let fractions = fractions(for: index)
                SegmentShape(start: fractions.start, end: fractions.end)
                    .fill(Color.white.opacity(opacities[index]))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .onChange(of: Target(shares: shares, isReady: isReady), initial: true) { _, target in
            // Starts empty on first appearance, so the first update is the left-to-right growth
            if shown.isEmpty { shown = Array(repeating: 0, count: shares.count) }
            withAnimation(.smooth(duration: 1.0)) {
                shown = target.isReady ? target.shares : Array(repeating: 0, count: shares.count)
            }
        }
    }

    private func fractions(for index: Int) -> (start: Double, end: Double) {
        guard shown.count == shares.count else { return (0, 0) }
        let start = shown[..<index].reduce(0, +)
        return (start, start + shown[index])
    }

    private struct Target: Equatable {
        let shares: [Double]
        let isReady: Bool
    }
}

/// A capsule covering `start...end` of the width, with a small gap before the next segment
private struct SegmentShape: Shape {
    var start: Double
    var end: Double

    private let gap: CGFloat = 2
    private let minimumWidth: CGFloat = 3

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, end) }
        set {
            start = newValue.first
            end = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard end > start else { return Path() }
        let x = rect.width * CGFloat(start)
        let width = max(minimumWidth, rect.width * CGFloat(end - start) - gap)
        let segment = CGRect(x: x, y: 0, width: width, height: rect.height)
        return Capsule().path(in: segment)
    }
}
