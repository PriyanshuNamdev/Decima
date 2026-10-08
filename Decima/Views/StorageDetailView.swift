import SwiftUI

struct StorageDetailView: View {
    let manager: GalleryManager
    @State private var service = StorageAnalysisService()
    
    var body: some View {
        ZStack {
            BackgroundGlowView()
            
            ScrollView {
                VStack(spacing: 24) {
                    summaryCard
                    categoryList
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("Your Library")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Populate on load
            service.populate(from: manager)
        }
    }
    
    // MARK: - Summary Card
    private var summaryCard: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Storage")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(service.percentageUsed)% Used")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.coralRed)
            }
            
            VStack(spacing: 8) {
                HStack(alignment: .lastTextBaseline) {
                    Text(service.formattedSize(service.usedDeviceCapacity))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    Text(" / \(service.formattedSize(service.totalDeviceCapacity))")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.lightGray)
                    Spacer()
                }
                
                StorageUsageBar(segments: service.segments, totalCapacity: service.totalDeviceCapacity)
                    .frame(height: 12)
                    .padding(.top, 8)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Category List
    private var categoryList: some View {
        VStack(spacing: 0) {
            
            categoryRow(category: .videos, bytes: service.videosSize)
            Divider().background(Color.charcoalBorder).padding(.leading, 40)
            
            categoryRow(category: .screenshots, bytes: service.screenshotsSize)
            Divider().background(Color.charcoalBorder).padding(.leading, 40)
            

            categoryRow(category: .duplicatePhotos, bytes: service.duplicatePhotosSize)
            Divider().background(Color.charcoalBorder).padding(.leading, 40)
            
            categoryRow(category: .similarPhotos, bytes: service.similarPhotosSize)
            Divider().background(Color.charcoalBorder).padding(.leading, 40)
            
            categoryRow(category: .duplicateVideos, bytes: service.duplicateVideosSize)
            Divider().background(Color.charcoalBorder).padding(.leading, 40)
            
            categoryRow(category: .largeVideos, bytes: service.largeVideosSize)
            // No divider for the last item
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.deepBrownBlack.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.charcoalBorder, lineWidth: 1)
        )
    }
    
    private func categoryRow(category: MediaCategory, bytes: Int64) -> some View {
        NavigationLink(destination: CategoryDetailView(category: category)) {
            HStack(spacing: 12) {
                Circle()
                    .fill(category.iconColor)
                    .frame(width: 12, height: 12)
                
                Text(category.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.softWhite)
                
                Spacer()
                
                Text(service.formattedSize(bytes))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.lightGray)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.mutedDarkGray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}
