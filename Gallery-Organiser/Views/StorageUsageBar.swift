import SwiftUI

struct StorageUsageBar: View {
    let segments: [StorageSegment]
    let totalCapacity: Int64
    
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    let width = max(0, (CGFloat(segment.bytes) / CGFloat(totalCapacity)) * geo.size.width)
                    if width > 0 {
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: width)
                    }
                }
            }
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
        }
    }
}
