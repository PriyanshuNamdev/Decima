import SwiftUI
import Photos

struct ContentView: View {
    @State private var manager = GalleryManager()
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.nearBlack.ignoresSafeArea()
                
                if manager.authorizationStatus == .authorized || manager.authorizationStatus == .limited {
                    mainContent
                } else if manager.authorizationStatus == .notDetermined {
                    VStack {
                        Text("Gallery Access Required")
                            .font(.title2.bold())
                            .foregroundColor(.softWhite)
                        Button("Allow Access") {
                            manager.requestAuthorization()
                        }
                        .padding()
                        .background(Color.coralRed)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                } else {
                    Text("Please enable photo access in Settings.")
                        .foregroundColor(.lightGray)
                }
            }
        }
    }
    
    var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Make room.")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.softWhite)
                    Text("A little less clutter. A lot more possibility.")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.lightGray)
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)
                
                // Storage Card
                storageCard
                    .padding(.horizontal, 20)
                
                // Categories
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Choose a category")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.softWhite)
                        Spacer()
                        Text("6 collections")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.mutedDarkGray)
                    }
                    .padding(.horizontal, 20)
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(MediaCategory.allCases) { category in
                            NavigationLink(destination: CategoryDetailView(category: category)) {
                                CategoryCardView(
                                    category: category,
                                    count: manager.categoryCounts[category] ?? 0,
                                    sizeString: GalleryManager.formatSize(manager.categorySizes[category] ?? 0)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                // Footer
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.mutedDarkGray)
                    Text("Loads only what you open. Your library stays on device.")
                        .font(.system(size: 12))
                        .foregroundColor(.mutedDarkGray)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }
    
    var storageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("YOUR LIBRARY")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.mutedDarkGray)
                Spacer()
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundColor(.mutedDarkGray)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(manager.totalLibrarySize > 0 ? GalleryManager.formatSize(manager.totalLibrarySize).replacingOccurrences(of: " GB", with: "") : "--")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.softWhite)
                
                Text("GB")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.lightGray)
                
                Spacer()
                
                Text("\(manager.totalLibraryCount) items")
                    .font(.system(size: 13))
                    .foregroundColor(.mutedDarkGray)
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.charcoalBorder)
                        .frame(height: 4)
                    
                    Capsule()
                        .fill(Color.primaryGradient)
                        .frame(width: geo.size.width * 0.65, height: 4) // Example progress
                }
            }
            .frame(height: 4)
        }
        .padding(20)
        .background(Color.deepBrownBlack)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.charcoalBorder, lineWidth: 1)
        )
    }
}
