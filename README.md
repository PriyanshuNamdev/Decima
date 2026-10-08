# Decima

Decima is a SwiftUI iOS app that helps you free up storage by cleaning up your Photos library. It scans your library, groups clutter into categories (screenshots, duplicates, look-alikes, large videos), and lets you review and delete it in bulk or one card at a time.

Everything runs on-device. No photos or analysis results leave your phone.

## Features

| Category | What it finds |
|---|---|
| **Screenshots** | Every screen capture in the library |
| **Videos** | Your entire video library |
| **Duplicate Photos** | Exact copies (byte-identical image data) |
| **Similar Photos** | Look-alike shots, such as burst or retake photos |
| **Duplicate Videos** | Byte-identical video files (SHA-256 of the file) |
| **Large Videos** | Videos of 100 MB or more, biggest first |

Other highlights:

- **Dashboard** with total library size, device storage, a storage usage bar, and a card with a photo mosaic for each category.
- **Category detail view** with grouped results, drag-to-select across thumbnails, and an automatic "keeper" pick in each duplicate/similar group (you can change it).
- **Clean Up mode**: a swipe-card flow. Swipe right (or tap ♥) to keep, left (or tap ✕) to delete, with undo.
- **Photos-style viewer** with an info panel for each asset.
- **Deletion flow** with an animated "clearing space" screen (dissolve, dust and confetti effects) and a summary of the space reclaimed.
- **Live updates**: the app observes the Photos library and rescans when it changes.
- Dark-only design, with a permission screen for first launch.

## Requirements

- Xcode with an iOS SDK that supports the project's deployment target, `IPHONEOS_DEPLOYMENT_TARGET = 27.0`
- Swift 5 language mode
- A device or simulator with a Photos library. A real device with real photos gives the most meaningful results.

Device families: iPhone, iPad and Vision (`TARGETED_DEVICE_FAMILY = 1,2,7`).

## Getting started

```bash
git clone https://github.com/PriyanshuNamdev/Decima.git
cd Decima
open Decima.xcodeproj
```

1. Select the **Decima** scheme and a device or simulator.
2. In *Signing & Capabilities*, choose your own development team. The bundle identifier is currently `com.gallerycleaner.appf57c4e9d`; change it if it conflicts with your account.
3. Build and run (⌘R).
4. Grant Photos access when prompted. Decima needs **read/write** access, because deleting requires it.

There are no third-party dependencies and no package manager setup.

### Permissions

The app declares `NSPhotoLibraryUsageDescription` (set in the build settings, since the Info.plist is generated):

> Decima needs access to your photos to find duplicates, large videos and screenshots. Everything stays on your device.

Both full and limited library access are supported. With limited access, only the photos you've shared with the app are scanned.

## Project structure

```
Decima/
├── Decima.xcodeproj
└── Decima/
    ├── DecimaApp.swift              App entry point (forces dark mode)
    ├── ContentView.swift            Dashboard: storage summary and category cards
    ├── Models/
    │   ├── MediaCategory.swift      The six categories: titles, icons, colors, large-video threshold
    │   ├── GalleryAsset.swift       PHAsset wrapper with its file size
    │   └── CleanUpSession.swift     Swipe-session state: keep/delete sets and undo history
    ├── Managers/
    │   ├── GalleryManager.swift     Authorization, scanning, per-category stats, library-change refresh
    │   ├── PhotoLibraryAnalyzer.swift  Fetching, duplicate detection, similarity detection, file sizes
    │   ├── StorageAnalysisService.swift  Builds the storage-bar segments
    │   └── DeletionService.swift    Deletes assets through PhotoKit
    ├── Views/
    │   ├── CategoryCardView.swift / CategoryDetailView.swift
    │   ├── CleanUpView.swift / CleanUpCardView.swift
    │   ├── AssetPreviewView.swift / AssetInfoView.swift / AssetThumbnailView.swift
    │   ├── ClearingSpaceView.swift  Deletion progress and animation
    │   ├── StorageDetailView.swift / StorageUsageBar.swift
    │   ├── PermissionView.swift
    │   └── Effects.swift / BackgroundGlowView.swift
    ├── Theme/Color+Theme.swift      Custom app colors
    └── Assets.xcassets              App icon, accent color, sample images
```

## How it works

**Architecture.** The app is SwiftUI with the Observation framework (`@Observable`). `GalleryManager` is the main `@MainActor` source of truth. It holds the authorization status, library totals, and per-category counts, sizes and preview assets. Views read it directly. Scanning is run through `PhotoLibraryAnalyzer`, and a change observer on the Photos library triggers a rescan. If a refresh is requested while a scan is already running, one more pass is queued instead of running two at once.

**Exact duplicates.** Assets are first grouped by creation time (to the second) and pixel dimensions. Only groups with more than one member are hashed. Photos are hashed with SHA-256 over the full image data. Videos are hashed the same way, but streamed in chunks from the original (or edited) video resource, so memory stays low. Matching hashes form a duplicate group.

**Similar photos.** Screenshots are excluded. Photos are bucketed by creation date and aspect ratio. Within each bucket, a 256×256 thumbnail of each photo gets a Vision feature print (`VNGenerateImageFeaturePrintRequest`). Photos whose feature-print distance is under `15.0` are grouped together.

**Keeper selection.** In each group, the app picks the best asset to keep (`CategoryDetailView.bestAsset(in:)`), shows it with a badge, and pre-selects the rest for deletion. You can change the keeper.

**Deleting.** `DeletionService` calls `PHAssetChangeRequest.deleteAssets` inside `PHPhotoLibrary.performChanges`. iOS shows its own confirmation dialog, and deleted items go to *Recently Deleted* in Photos, where they stay for the usual 30 days. Space is only fully reclaimed after they are removed from there.

**File sizes.** Sizes come from the asset's primary resource via `PHAssetResource`, using the `fileSize` key. This is not a documented public API, so treat sizes as approximate.
