import SwiftUI
import Photos
import MapKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Info Sheet

/// Photos-style Info panel: capture date, camera and lens, file details, exposure and location.
struct AssetInfoView: View {
    let asset: GalleryAsset
    var isFavorite: Bool

    @State private var details: AssetDetails?
    @State private var place: MKMapItem?

    private var phAsset: PHAsset { asset.asset }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                metadataCard
                locationSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task(id: asset.id) {
            details = nil
            place = nil
            details = await AssetDetails.load(for: asset)
        }
        .task(id: asset.id) {
            guard let location = phAsset.location,
                  let request = MKReverseGeocodingRequest(location: location) else { return }
            place = try? await request.mapItems.first
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date = phAsset.creationDate {
                Text([
                    date.formatted(.dateTime.weekday(.wide)),
                    date.formatted(.dateTime.day().month(.wide).year()),
                    date.formatted(date: .omitted, time: .shortened)
                ].joined(separator: " • "))
            } else {
                Text("No Date")
            }

            let tags = mediaTags
            if !tags.isEmpty || isFavorite {
                HStack(spacing: 6) {
                    if isFavorite {
                        TagView(text: "Favourite", systemImage: "heart.fill")
                    }
                    ForEach(tags, id: \.self) { tag in
                        TagView(text: tag)
                    }
                }
            }
        }
        .font(.headline)
    }

    private var mediaTags: [String] {
        let subtypes = phAsset.mediaSubtypes
        var tags: [String] = []
        if subtypes.contains(.photoScreenshot) { tags.append("Screenshot") }
        if subtypes.contains(.photoLive) { tags.append("Live") }
        if subtypes.contains(.photoHDR) { tags.append("HDR") }
        if subtypes.contains(.photoPanorama) { tags.append("Panorama") }
        if subtypes.contains(.photoDepthEffect) { tags.append("Portrait") }
        if subtypes.contains(.videoHighFrameRate) { tags.append("Slo-mo") }
        if subtypes.contains(.videoTimelapse) { tags.append("Time-lapse") }
        if subtypes.contains(.videoCinematic) { tags.append("Cinematic") }
        if phAsset.hasAdjustments { tags.append("Edited") }
        return tags
    }

    // MARK: Metadata Card

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Device + format badge
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(details?.deviceName ?? fallbackDeviceName)
                        .font(.headline)
                    if let filename = details?.filename {
                        Text(filename)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let format = details?.formatName {
                    Text(format)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .rect(cornerRadius: 4))
                }
            }
            .padding(14)

            Divider().padding(.leading, 14)

            VStack(alignment: .leading, spacing: 4) {
                if let lens = details?.lensDescription {
                    Text(lens)
                }
                Text(primarySpecLine)
                if let secondary = secondarySpecLine {
                    Text(secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .redacted(reason: details == nil ? .placeholder : [])

            if let exposure = details?.exposureValues, !exposure.isEmpty {
                Divider()
                HStack(spacing: 0) {
                    ForEach(Array(exposure.enumerated()), id: \.offset) { index, value in
                        if index > 0 {
                            Divider().frame(height: 16)
                        }
                        Text(value)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 10)
                .background(.white.opacity(0.04))
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var fallbackDeviceName: String {
        if details == nil { return "Loading…" }
        if phAsset.mediaSubtypes.contains(.photoScreenshot) { return "Screenshot" }
        return "No Camera Information"
    }

    /// e.g. "12 MP • 4032 × 3024 • 2.4 MB" or "4K • 3840 × 2160 • 60 fps"
    private var primarySpecLine: String {
        let width = phAsset.pixelWidth
        let height = phAsset.pixelHeight
        var parts: [String] = []

        if phAsset.mediaType == .video {
            parts.append(AssetDetails.resolutionName(width: width, height: height))
            parts.append("\(width) × \(height)")
            if let fps = details?.frameRate, fps > 0 {
                parts.append("\(Int(fps.rounded())) fps")
            }
        } else {
            let megapixels = Double(width * height) / 1_000_000
            parts.append(megapixels >= 1 ? "\(Int(megapixels.rounded())) MP" : String(format: "%.1f MP", megapixels))
            parts.append("\(width) × \(height)")
            if let size = details?.fileSize, size > 0 {
                parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
        }
        return parts.joined(separator: " • ")
    }

    /// Videos only, e.g. "HEVC • 1:23 • 214 MB"
    private var secondarySpecLine: String? {
        guard phAsset.mediaType == .video else { return nil }
        var parts: [String] = []
        if let codec = details?.codec { parts.append(codec) }
        parts.append(VideoControlsBar.format(phAsset.duration))
        if let size = details?.fileSize, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.joined(separator: " • ")
    }

    // MARK: Location

    @ViewBuilder
    private var locationSection: some View {
        if let location = phAsset.location {
            let coordinate = location.coordinate
            VStack(alignment: .leading, spacing: 0) {
                Map(
                    initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)),
                    interactionModes: []
                ) {
                    Annotation("", coordinate: coordinate) {
                        AssetThumbnailView(asset: phAsset, size: CGSize(width: 44, height: 44))
                            .frame(width: 44, height: 44)
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 2))
                            .shadow(radius: 3)
                    }
                }
                .frame(height: 180)
                .id(asset.id)
                .onTapGesture { place?.openInMaps() }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place?.addressRepresentations?.cityWithContext ?? place?.name ?? "Location")
                            .font(.headline)
                        Text(place?.address?.shortAddress ?? coordinateText(coordinate))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if place != nil {
                        Button("Open in Maps", systemImage: "arrow.up.forward.square") {
                            place?.openInMaps()
                        }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                    }
                }
                .padding(14)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
        } else {
            HStack {
                Image(systemName: "location.slash")
                Text("No Location")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
}

private struct TagView: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: .capsule)
    }
}

// MARK: - Metadata Loading

struct AssetDetails {
    var filename: String?
    var formatName: String?
    var fileSize: Int64 = 0

    // Camera (photos via EXIF/TIFF, videos via QuickTime metadata)
    var make: String?
    var model: String?
    var lensModel: String?

    // Exposure (photos)
    var iso: Int?
    var focalLength: Double?
    var focalLength35mm: Double?
    var aperture: Double?
    var exposureTime: Double?
    var exposureBias: Double?

    // Video
    var frameRate: Double?
    var codec: String?

    var deviceName: String? {
        guard let model, !model.isEmpty else { return make }
        // "NIKON CORPORATION" + "NIKON D90" → "NIKON D90"; "Apple" + "iPhone 15 Pro" → "Apple iPhone 15 Pro"
        let brand = make?.split(separator: " ").first.map(String.init) ?? ""
        guard let make, !brand.isEmpty, !model.localizedCaseInsensitiveContains(brand) else { return model }
        return "\(make) \(model)"
    }

    /// e.g. "Main Camera — 24 mm ƒ1.78"
    var lensDescription: String? {
        var name: String?
        if let lensModel {
            let lens = lensModel.lowercased()
            if make?.lowercased() == "apple" {
                if lens.contains("front") {
                    name = "Front Camera"
                } else if let focal = focalLength35mm {
                    name = focal < 20 ? "Ultra Wide Camera" : focal < 40 ? "Main Camera" : "Telephoto Camera"
                } else {
                    name = "Back Camera"
                }
            } else {
                name = lensModel
            }
        }

        var specs: [String] = []
        if let focal = focalLength35mm ?? focalLength {
            specs.append("\(Int(focal.rounded())) mm")
        }
        if let aperture {
            specs.append(Self.formatAperture(aperture))
        }

        switch (name, specs.isEmpty) {
        case (nil, true): return nil
        case (nil, false): return specs.joined(separator: " ")
        case (let name?, true): return name
        case (let name?, false): return "\(name) — " + specs.joined(separator: " ")
        }
    }

    /// The strip along the bottom of the card: ISO 80 | 24 mm | 0 ev | ƒ1.78 | 1/120 s
    var exposureValues: [String] {
        var values: [String] = []
        if let iso { values.append("ISO \(iso)") }
        if let focal = focalLength35mm ?? focalLength { values.append("\(Int(focal.rounded())) mm") }
        if let bias = exposureBias {
            values.append(abs(bias) < 0.05 ? "0 ev" : String(format: "%+.1f ev", bias))
        }
        if let aperture { values.append(Self.formatAperture(aperture)) }
        if let time = exposureTime, time > 0 {
            if time < 1 {
                values.append("1/\(Int((1 / time).rounded())) s")
            } else {
                values.append(String(format: "%g s", time))
            }
        }
        return values
    }

    static func formatAperture(_ value: Double) -> String {
        "ƒ" + String(format: "%.3g", value)
    }

    static func resolutionName(width: Int, height: Int) -> String {
        let shortSide = min(width, height)
        switch shortSide {
        case 4320...: return "8K"
        case 2160...: return "4K"
        case 1440...: return "1440p"
        case 1080...: return "HD 1080p"
        case 720...: return "HD 720p"
        default: return "SD"
        }
    }

    // MARK: Loading

    static func load(for item: GalleryAsset) async -> AssetDetails {
        let asset = item.asset
        var details = AssetDetails()

        let resources = PHAssetResource.assetResources(for: asset)
        if let original = resources.first(where: { $0.type == .photo || $0.type == .video }) ?? resources.first {
            details.filename = original.originalFilename
            details.formatName = formatName(for: original.uniformTypeIdentifier)
            details.fileSize = item.fileSize > 0 ? item.fileSize : ((original.value(forKey: "fileSize") as? Int64) ?? 0)
        }

        if asset.mediaType == .video {
            await loadVideoMetadata(for: asset, into: &details)
        } else {
            await loadPhotoMetadata(for: asset, into: &details)
        }
        return details
    }

    private static func formatName(for uti: String) -> String? {
        guard let type = UTType(uti) else { return nil }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return "HEIF" }
        if type.conforms(to: .jpeg) { return "JPEG" }
        if type.conforms(to: .quickTimeMovie) { return "MOV" }
        if type.conforms(to: .mpeg4Movie) { return "MP4" }
        if type.conforms(to: .rawImage) { return "RAW" }
        return type.preferredFilenameExtension?.uppercased()
    }

    private static func loadPhotoMetadata(for asset: PHAsset, into details: inout AssetDetails) async {
        let data: Data? = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .original
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }

        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return }

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]

        details.make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
        details.model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
        details.lensModel = exif[kCGImagePropertyExifLensModel] as? String
        details.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        details.focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
        details.focalLength35mm = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Double
        details.aperture = exif[kCGImagePropertyExifFNumber] as? Double
        details.exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double
        details.exposureBias = exif[kCGImagePropertyExifExposureBiasValue] as? Double
    }

    private static func loadVideoMetadata(for asset: PHAsset, into details: inout AssetDetails) async {
        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .original
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
        guard let avAsset else { return }

        if let track = try? await avAsset.loadTracks(withMediaType: .video).first {
            if let fps = try? await track.load(.nominalFrameRate) {
                details.frameRate = Double(fps)
            }
            if let description = try? await track.load(.formatDescriptions).first {
                details.codec = codecName(CMFormatDescriptionGetMediaSubType(description))
            }
        }

        let metadata = (try? await avAsset.load(.metadata)) ?? []
        if let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeMetadataMake).first {
            details.make = try? await item.load(.stringValue)
        }
        if let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeMetadataModel).first {
            details.model = try? await item.load(.stringValue)
        }
    }

    private static func codecName(_ code: FourCharCode) -> String {
        switch code {
        case kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha: return "HEVC"
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ,
             kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy,
             kCMVideoCodecType_AppleProRes4444, kCMVideoCodecType_AppleProRes4444XQ: return "ProRes"
        case kCMVideoCodecType_MPEG4Video: return "MPEG-4"
        default:
            let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
            return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces).uppercased() ?? "Video"
        }
    }
}
