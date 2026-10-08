import SwiftUI

/// The app's warm backdrop: a mesh gradient whose glow drifts slowly
/// (and holds still when Reduce Motion is on).
struct BackgroundGlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, Float(0.42 + 0.06 * sin(t * 0.30))],
                    [Float(0.5 + 0.12 * sin(t * 0.21)), Float(0.38 + 0.08 * cos(t * 0.26))],
                    [1, Float(0.42 + 0.06 * cos(t * 0.24))],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: [
                    Color.coralRed.opacity(0.42), Color.darkBrown, Color.burntOrange.opacity(0.38),
                    Color.deepBrownBlack, Color.nearBlack, Color.deepBrownBlack,
                    Color.nearBlack, Color.nearBlack, Color.nearBlack
                ]
            )
        }
        .background(Color.nearBlack)
        .ignoresSafeArea()
    }
}
