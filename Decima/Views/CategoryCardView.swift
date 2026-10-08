import SwiftUI
import Photos

struct CategoryCardView: View {
    let category: MediaCategory
    let count: Int
    let sizeString: String
    /// A few assets from the category, shown as a mosaic behind the card
    var previews: [PHAsset] = []
    var isLoading: Bool = false

    private var isGrouped: Bool {
        [.duplicatePhotos, .duplicateVideos, .similarPhotos].contains(category)
    }

    private var countText: String {
        if isLoading { return "Scanning…" }
        if count == 0 { return "None found" }
        return "\(count) \(isGrouped ? (count == 1 ? "group" : "groups") : (count == 1 ? "item" : "items"))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: category.iconSystemName)
                    .font(.title2)
                    .foregroundColor(category.iconColor)
                    .frame(width: 32, height: 32, alignment: .leading)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.lightGray)
                } else if count > 0 && !sizeString.isEmpty {
                    Text(sizeString)
                        .font(.footnote.weight(.semibold))
                        .fontDesign(.rounded)
                        .foregroundColor(.softWhite)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.35), in: .capsule)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.headline)
                    .foregroundColor(.softWhite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(countText)
                    .font(.subheadline)
                    .foregroundColor(.softWhite.opacity(0.9))
                    .contentTransition(.numericText(value: Double(count)))

                Text(category.subtitlePlaceholder)
                    .font(.caption)
                    .foregroundColor(.lightGray)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(minHeight: 150)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                if !previews.isEmpty {
                    PreviewMosaic(assets: previews)
                        .opacity(0.5)
                        .overlay(
                            LinearGradient(
                                colors: [.black.opacity(0.1), .black.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .transition(.opacity)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .animation(.smooth, value: isLoading)
        .animation(.smooth, value: previews.count)
    }
}

/// One large tile with up to two stacked beside it, like Photos' Collections
private struct PreviewMosaic: View {
    let assets: [PHAsset]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                MosaicTile(asset: assets[0])
                    .frame(width: assets.count > 1 ? geo.size.width * 0.62 : geo.size.width)
                if assets.count > 1 {
                    VStack(spacing: 2) {
                        MosaicTile(asset: assets[1])
                        if assets.count > 2 {
                            MosaicTile(asset: assets[2])
                        }
                    }
                }
            }
        }
    }
}

private struct MosaicTile: View {
    let asset: PHAsset
    @State private var image: UIImage?

    private static let imageManager = PHCachingImageManager()

    var body: some View {
        Color.clear
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
        Self.imageManager.requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: options) { result, _ in
            if let result {
                image = result
            }
        }
    }
}
