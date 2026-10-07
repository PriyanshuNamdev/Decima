import SwiftUI
import Photos

struct AssetThumbnailView: View {
    let asset: PHAsset
    let size: CGSize
    @State private var image: UIImage?
    
    // Shared caching image manager
    private static let imageManager = PHCachingImageManager()
    
    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.warmCharcoal)
                        .overlay(
                            ProgressView()
                                .tint(.lightGray)
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .onAppear {
                loadImage(targetSize: proxy.size)
            }
            // Optional: .onDisappear to cancel requests if needed
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func loadImage(targetSize: CGSize) {
        // Calculate size in pixels based on screen scale
        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        
        Self.imageManager.requestImage(
            for: asset,
            targetSize: pixelSize,
            contentMode: .aspectFill,
            options: options
        ) { result, info in
            if let result = result {
                self.image = result
            }
        }
    }
}
