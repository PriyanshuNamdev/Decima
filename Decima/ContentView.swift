import SwiftUI
import Photos

struct ContentView: View {
    @State private var manager = GalleryManager()
    @State private var displayedLibrarySize: Double = 0
    @State private var displayedReclaimable: Double = 0

    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGlowView()

                if manager.authorizationStatus == .authorized || manager.authorizationStatus == .limited {
                    mainContent
                } else if manager.authorizationStatus == .notDetermined {
                    PermissionView(
                        allowAction: { manager.requestAuthorization() },
                        denyAction: { /* Do nothing or dismiss */ }
                    )
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
                    Text("Clean Up Your Library")
                        .font(.largeTitle.bold())
                        .foregroundColor(.softWhite)
                    Text("Find duplicates, large videos and screenshots that are taking up space.")
                        .font(.callout)
                        .foregroundColor(.lightGray)
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)

                // Storage Card
                NavigationLink(destination: StorageDetailView(manager: manager)) {
                    storageCard
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 20)

                reclaimCallToAction
                    .padding(.horizontal, 20)

                // Categories
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Choose a category")
                            .font(.headline)
                            .foregroundColor(.softWhite)
                        Spacer()
                        Text("\(MediaCategory.allCases.count) collections")
                            .font(.footnote)
                            .foregroundColor(.mutedDarkGray)
                    }
                    .padding(.horizontal, 20)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(MediaCategory.allCases) { category in
                            NavigationLink(destination: CategoryDetailView(category: category)) {
                                CategoryCardView(
                                    category: category,
                                    count: manager.categoryCounts[category] ?? 0,
                                    sizeString: GalleryManager.formatSize(manager.categorySizes[category] ?? 0),
                                    previews: manager.categoryPreviews[category] ?? [],
                                    isLoading: manager.loadingCategories.contains(category)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Footer
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(.mutedDarkGray)
                    Text("Loads only what you open. Your library stays on device.")
                        .font(.caption)
                        .foregroundColor(.mutedDarkGray)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .refreshable {
            await manager.refresh()
        }
        .onAppear {
            countUp()
        }
        .onChange(of: manager.totalLibrarySize) { countUp() }
        .onChange(of: manager.reclaimableSize) { countUp() }
    }

    /// Numbers roll up to their new values rather than snapping
    private func countUp() {
        withAnimation(.easeOut(duration: 1.1)) {
            displayedLibrarySize = Double(manager.totalLibrarySize)
            displayedReclaimable = Double(manager.reclaimableSize)
        }
    }

    // MARK: - Storage Card

    var storageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("YOUR LIBRARY")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundColor(.white.opacity(0.8))
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if manager.totalLibrarySize > 0 {
                    CountingText(value: displayedLibrarySize) { Self.sizeParts(Int64($0)).value }
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()

                    CountingText(value: displayedLibrarySize) { "\(Self.sizeParts(Int64($0)).unit) of \(manager.formattedDeviceSizeValue) \(manager.formattedDeviceSizeUnit)" }
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                } else {
                    // Placeholder while the library is measured
                    Text("00.0")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .redacted(reason: .placeholder)
                        .shimmering()
                    Text("GB of 000 GB")
                        .font(.callout.weight(.semibold))
                        .redacted(reason: .placeholder)
                        .shimmering()
                }

                Spacer()

                Text("\(manager.totalLibraryCount) items")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.8))
                    .contentTransition(.numericText(value: Double(manager.totalLibraryCount)))
            }
            .foregroundColor(.white.opacity(0.6))

            libraryCompositionBar
        }
        .padding(20)
        .background(Color.primaryGradient)
        .cornerRadius(20)
        .shadow(color: Color.coralRed.opacity(0.3), radius: 10, x: 0, y: 5)
    }

    /// What the library is made of: photos, videos and screenshots
    private var libraryCompositionBar: some View {
        let parts: [(name: String, bytes: Int64, opacity: Double)] = [
            ("Photos", manager.photosSize, 1.0),
            ("Videos", manager.categorySizes[.videos] ?? 0, 0.65),
            ("Screenshots", manager.categorySizes[.screenshots] ?? 0, 0.38)
        ]
        let total = max(parts.reduce(0) { $0 + $1.bytes }, 1)
        let isReady = manager.totalLibrarySize > 0

        return VStack(alignment: .leading, spacing: 10) {
            CompositionBar(
                shares: parts.map { Double($0.bytes) / Double(total) },
                opacities: parts.map(\.opacity),
                isReady: isReady
            )

            HStack(spacing: 14) {
                ForEach(parts, id: \.name) { part in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.white.opacity(part.opacity))
                            .frame(width: 7, height: 7)
                        Text(part.name)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
            }
        }
    }

    // MARK: - Call to Action

    @ViewBuilder
    private var reclaimCallToAction: some View {
        if manager.isScanningForDuplicates && manager.reclaimableSize == 0 {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.lightGray)
                Text("Looking for duplicates and look-alikes…")
                    .font(.subheadline)
                    .foregroundColor(.lightGray)
                Spacer()
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .transition(.opacity)
        } else if let category = manager.bestReclaimCategory {
            NavigationLink(destination: CategoryDetailView(category: category)) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You could free")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.lightGray)
                        CountingText(value: displayedReclaimable) { GalleryManager.formatSize(Int64($0)).isEmpty ? "0 MB" : GalleryManager.formatSize(Int64($0)) }
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primaryGradient)
                            .monospacedDigit()
                        Text("by removing extra copies and look-alikes")
                            .font(.caption)
                            .foregroundColor(.mutedDarkGray)
                    }
                    Spacer()
                    Text("Review")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.primaryGradient, in: .capsule)
                }
                .padding(18)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else if !manager.isScanningForDuplicates {
            Label("No duplicates found — your library is tidy.", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.mint)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .transition(.opacity)
        }
    }

    private static func sizeParts(_ bytes: Int64) -> (value: String, unit: String) {
        let formatted = GalleryManager.formatSize(bytes)
        let parts = formatted.components(separatedBy: " ")
        return (parts.first ?? "0", parts.count > 1 ? parts[1] : "MB")
    }
}
