import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageAttachment: Sendable {
    static let uploadSizeLimit = 5_000_000

    let data: Data
    let filename: String
    let format: ImageFormat

    @MainActor
    static func prepare(from provider: NSItemProvider) async throws -> ImageAttachment {
        try Task.checkCancellation()
        // Ask for a concrete representation first so the provider can share its original format.
        let identifier = provider.registeredTypeIdentifiers.first {
            ImageFormat(rawValue: $0) != nil
        } ?? UTType.image.identifier
        guard provider.hasItemConformingToTypeIdentifier(identifier) else {
            throw PreparationError.unsupportedType
        }

        let progress = Progress(totalUnitCount: 1)
        let prepared: (data: Data, format: ImageFormat) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let loading = provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, error in
                    // The provider's background callback owns the file only until it returns.
                    let result = Result {
                        try autoreleasepool {
                            if progress.isCancelled { throw CancellationError() }
                            guard error == nil, let url else { throw PreparationError.unreadable }
                            return try loadImage(at: url, progress: progress)
                        }
                    }
                    continuation.resume(with: result)
                }
                progress.addChild(loading, withPendingUnitCount: 1)
                if progress.isCancelled { loading.cancel() }
            }
        } onCancel: {
            progress.cancel()
        }
        try Task.checkCancellation()
        let suggestedName = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = if let suggestedName, !suggestedName.isEmpty {
            suggestedName
        } else {
            "photo-\(UUID().uuidString)"
        }
        return ImageAttachment(data: prepared.data, filename: filename, format: prepared.format)
    }

    private nonisolated static func loadImage(at url: URL, progress: Progress) throws -> (data: Data, format: ImageFormat) {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw PreparationError.unreadable
        }
        guard let identifier = CGImageSourceGetType(source) as String?,
              let format = ImageFormat(rawValue: identifier) else {
            throw PreparationError.unsupportedType
        }
        if format == .jpeg {
            return (try encodeJPEG(source, progress: progress), format)
        }

        // Limit the read even if the provider writes a file larger than the API allows.
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let data = try file.read(upToCount: uploadSizeLimit), !data.isEmpty else {
            throw PreparationError.unreadable
        }
        guard data.count < uploadSizeLimit else { throw PreparationError.tooLarge }
        return (data, format)
    }

    private nonisolated static func encodeJPEG(_ source: CGImageSource, progress: Progress) throws -> Data {
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2560,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw PreparationError.unreadable
        }

        for quality in [0.85, 0.7, 0.55, 0.4] {
            if progress.isCancelled { throw CancellationError() }
            let buffer = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(buffer, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw PreparationError.cannotEncode
            }
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality,
                kCGImageMetadataShouldExcludeGPS: true,
                kCGImageMetadataShouldExcludeXMP: true
            ]
            CGImageDestinationAddImage(destination, image, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw PreparationError.cannotEncode }
            if buffer.length < uploadSizeLimit { return Data(referencing: buffer) }
        }
        throw PreparationError.cannotCompress
    }

    private enum PreparationError: LocalizedError {
        case unsupportedType, unreadable, cannotEncode, cannotCompress, tooLarge

        var errorDescription: String? {
            switch self {
            case .unsupportedType: "JPEG、PNG、GIF、WebP、HEIC、HEIFの画像を選択してください。"
            case .unreadable: "画像を読み込めませんでした。"
            case .cannotEncode: "写真をJPEGに変換できませんでした。"
            case .cannotCompress: "写真を5 MB未満に圧縮できませんでした。"
            case .tooLarge: "5 MB未満の画像を選択してください。"
            }
        }
    }
}

enum ImageFormat: String, Sendable {
    case jpeg = "public.jpeg"
    case png = "public.png"
    case gif = "com.compuserve.gif"
    case webp = "org.webmproject.webp"
    case heic = "public.heic"
    case heif = "public.heif"

    var filenameExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .gif: "gif"
        case .webp: "webp"
        case .heic: "heic"
        case .heif: "heif"
        }
    }

    var mimeType: String {
        "image/" + (self == .jpeg ? "jpeg" : filenameExtension)
    }

    var displayName: String {
        self == .jpeg ? "JPEG" : filenameExtension.uppercased()
    }
}
