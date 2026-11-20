import Foundation
import ImageIO

struct ImageMetadata {
    var pixelWidth: Int?
    var pixelHeight: Int?
    var bitDepth: Int?
    var colorModel: String?
    var profileName: String?
    var dpi: Int?

    var cameraMake: String?
    var cameraModel: String?
    var lens: String?
    var focalLength: Double?
    var focalLength35: Int?
    var fNumber: Double?
    var exposureTime: Double?
    var iso: Int?
    var exposureBias: Double?
    var flashFired: Bool?
    var dateTaken: Date?
    var software: String?

    var latitude: Double?
    var longitude: Double?

    var hasCameraInfo: Bool {
        cameraModel != nil || lens != nil || fNumber != nil || exposureTime != nil || iso != nil
    }

    var megapixels: Double? {
        guard let w = pixelWidth, let h = pixelHeight else { return nil }
        return Double(w * h) / 1_000_000
    }
}

enum MetadataReader {
    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()

    static func read(_ url: URL) -> ImageMetadata {
        var m = ImageMetadata()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return m }

        var w = p[kCGImagePropertyPixelWidth as String] as? Int
        var h = p[kCGImagePropertyPixelHeight as String] as? Int
        let orientation = p[kCGImagePropertyOrientation as String] as? Int ?? 1
        if orientation >= 5 { swap(&w, &h) }
        m.pixelWidth = w
        m.pixelHeight = h
        m.bitDepth = p[kCGImagePropertyDepth as String] as? Int
        m.colorModel = p[kCGImagePropertyColorModel as String] as? String
        m.profileName = p[kCGImagePropertyProfileName as String] as? String
        if let dpi = p[kCGImagePropertyDPIWidth as String] as? Double { m.dpi = Int(dpi.rounded()) }

        if let tiff = p[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            m.cameraMake = clean(tiff[kCGImagePropertyTIFFMake as String] as? String)
            m.cameraModel = clean(tiff[kCGImagePropertyTIFFModel as String] as? String)
            m.software = clean(tiff[kCGImagePropertyTIFFSoftware as String] as? String)
        }

        if let exif = p[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            m.lens = clean(exif[kCGImagePropertyExifLensModel as String] as? String)
            m.focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double
            m.focalLength35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Int
            m.fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double
            m.exposureTime = exif[kCGImagePropertyExifExposureTime as String] as? Double
            m.iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first
            m.exposureBias = exif[kCGImagePropertyExifExposureBiasValue as String] as? Double
            if let flash = exif[kCGImagePropertyExifFlash as String] as? Int {
                m.flashFired = (flash & 1) == 1
            }
            if let s = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                m.dateTaken = exifDateFormatter.date(from: s)
            }
        }

        if let gps = p[kCGImagePropertyGPSDictionary as String] as? [String: Any],
           let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String ?? "E"
            m.latitude = latRef == "S" ? -lat : lat
            m.longitude = lonRef == "W" ? -lon : lon
        }
        return m
    }

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)),
              !t.isEmpty else { return nil }
        return t
    }
}

// MARK: - การจัดรูปแบบสำหรับแสดงผล

enum Format {
    static func exposure(_ t: Double) -> String {
        if t >= 1 { return String(format: t == t.rounded() ? "%.0f s" : "%.1f s", t) }
        return "1/\(Int((1 / t).rounded())) s"
    }

    static func aperture(_ f: Double) -> String {
        String(format: f == f.rounded() ? "ƒ/%.0f" : "ƒ/%.1f", f)
    }

    static func focal(_ mm: Double, eq35: Int?) -> String {
        let base = String(format: mm == mm.rounded() ? "%.0f mm" : "%.1f mm", mm)
        if let eq35, eq35 > 0, Double(eq35) != mm.rounded() { return "\(base)  (≈ \(eq35) mm FF)" }
        return base
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func date(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .shortened)
    }

    static func coordinate(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.5f, %.5f", lat, lon)
    }
}
