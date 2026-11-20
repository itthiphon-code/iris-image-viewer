import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ตัวเลือกการแปลง/ย่อขนาดภาพ
struct ExportOptions: Equatable {
    var format: ExportFormat = .jpeg
    var quality: Double = 0.85
    /// ด้านยาวสุด (พิกเซล); nil = ขนาดเดิม
    var maxLongEdge: Int? = 2560
    var keepMetadata = true
    var removeGPS = true
    var suffix = ""
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case jpeg, heic, png, tiff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        }
    }

    var type: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .png: return .png
        case .tiff: return .tiff
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .png: return "png"
        case .tiff: return "tif"
        }
    }

    var isLossy: Bool { self == .jpeg || self == .heic }
}

enum ImageExporter {
    enum ExportError: LocalizedError {
        case unreadable(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let n): return "อ่านไฟล์ \(n) ไม่ได้"
            case .writeFailed(let n): return "บันทึก \(n) ไม่สำเร็จ"
            }
        }
    }

    /// แปลงไฟล์เดียว คืนค่า URL ของไฟล์ที่สร้าง
    static func export(_ url: URL, to folder: URL, options: ExportOptions) throws -> URL {
        let name = url.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ExportError.unreadable(name)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]

        let size = ImageDecoder.pixelSize(of: url) ?? CGSize(width: 8192, height: 8192)
        let longest = Int(max(size.width, size.height))
        let target = min(options.maxLongEdge ?? longest, longest)

        let decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(target, 1)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary) else {
            throw ExportError.unreadable(name)
        }

        let base = (name as NSString).deletingPathExtension + options.suffix
        let output = uniqueURL(in: folder, base: base, ext: options.format.fileExtension)

        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, options.format.type.identifier as CFString, 1, nil
        ) else { throw ExportError.writeFailed(output.lastPathComponent) }

        var out: [CFString: Any] = [:]
        if options.keepMetadata {
            if var exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension as String)
                exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension as String)
                out[kCGImagePropertyExifDictionary] = exif
            }
            if var tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                tiff[kCGImagePropertyTIFFOrientation as String] = 1
                out[kCGImagePropertyTIFFDictionary] = tiff
            }
            if let iptc = props[kCGImagePropertyIPTCDictionary as String] { out[kCGImagePropertyIPTCDictionary] = iptc }
            if !options.removeGPS, let gps = props[kCGImagePropertyGPSDictionary as String] {
                out[kCGImagePropertyGPSDictionary] = gps
            }
        }
        // ภาพถูกหมุนตาม EXIF แล้วตอนถอดรหัส จึงตั้ง orientation เป็นปกติ
        out[kCGImagePropertyOrientation] = 1
        if options.format.isLossy {
            out[kCGImageDestinationLossyCompressionQuality] = options.quality
        }

        CGImageDestinationAddImage(destination, image, out as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw ExportError.writeFailed(output.lastPathComponent)
        }
        return output
    }

    /// ถ้าชื่อซ้ำ ต่อท้ายด้วย -2, -3, …
    private static func uniqueURL(in folder: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
