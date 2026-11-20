import Foundation
import ImageIO

/// อ่าน/เขียนคะแนนดาวและป้ายสีแบบ XMP เพื่อใช้ร่วมกับ Lightroom, Bridge, Capture One
/// - อ่าน: ไฟล์ sidecar (.xmp) ก่อน แล้วจึงอ่าน XMP ที่ฝังในไฟล์ภาพ
/// - เขียน: เฉพาะ sidecar ของไฟล์ RAW (ไม่แตะเนื้อไฟล์ภาพ)
enum XMPStore {
    struct Values {
        var rating: Int?
        var label: ColorLabel?

        var isEmpty: Bool { rating == nil && label == nil }
    }

    /// ชื่อป้ายแบบ Lightroom
    private static func xmpName(_ label: ColorLabel) -> String? {
        switch label {
        case .none: return nil
        case .red: return "Red"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }

    private static func label(fromXMP name: String) -> ColorLabel? {
        switch name.lowercased() {
        case "red", "แดง": return .red
        case "yellow", "เหลือง": return .yellow
        case "green", "เขียว": return .green
        case "blue", "น้ำเงิน": return .blue
        case "purple", "ม่วง": return .purple
        default: return nil
        }
    }

    // MARK: - ตำแหน่ง sidecar

    /// IMG_0001.CR3 → IMG_0001.xmp (แบบ Lightroom)
    static func sidecarURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("xmp")
    }

    /// sidecar ที่มีอยู่จริง (รองรับทั้งแบบ IMG_0001.xmp และ IMG_0001.CR3.xmp)
    static func existingSidecars(for url: URL) -> [URL] {
        let fm = FileManager.default
        let candidates = [sidecarURL(for: url), url.appendingPathExtension("xmp")]
        return candidates.filter { fm.fileExists(atPath: $0.path) }
    }

    // MARK: - อ่าน

    static func read(_ url: URL) -> Values {
        for sidecar in existingSidecars(for: url) {
            if let data = try? Data(contentsOf: sidecar),
               let meta = CGImageMetadataCreateFromXMPData(data as CFData) {
                let v = values(from: meta)
                if !v.isEmpty { return v }
            }
        }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let meta = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            return values(from: meta)
        }
        return Values()
    }

    private static func values(from meta: CGImageMetadata) -> Values {
        var v = Values()
        if let s = stringValue(meta, "xmp:Rating"), let n = Int(s.trimmingCharacters(in: .whitespaces)), n > 0 {
            v.rating = min(n, 5)
        }
        if let s = stringValue(meta, "xmp:Label") { v.label = label(fromXMP: s) }
        return v
    }

    private static func stringValue(_ meta: CGImageMetadata, _ path: String) -> String? {
        guard let tag = CGImageMetadataCopyTagWithPath(meta, nil, path as CFString),
              let value = CGImageMetadataTagCopyValue(tag)
        else { return nil }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    // MARK: - เขียน sidecar

    /// อัปเดต/สร้าง sidecar ของไฟล์ (ใช้กับ RAW) โดยคงข้อมูลอื่นใน sidecar เดิมไว้
    @discardableResult
    static func writeSidecar(for url: URL, rating: Int, label: ColorLabel) -> Bool {
        let sidecar = existingSidecars(for: url).first ?? sidecarURL(for: url)

        let meta: CGMutableImageMetadata
        if let data = try? Data(contentsOf: sidecar),
           let existing = CGImageMetadataCreateFromXMPData(data as CFData),
           let copy = CGImageMetadataCreateMutableCopy(existing) {
            meta = copy
        } else {
            meta = CGImageMetadataCreateMutable()
        }

        if rating > 0 {
            CGImageMetadataSetValueWithPath(meta, nil, "xmp:Rating" as CFString, "\(min(rating, 5))" as CFString)
        } else {
            CGImageMetadataRemoveTagWithPath(meta, nil, "xmp:Rating" as CFString)
        }
        if let name = xmpName(label) {
            CGImageMetadataSetValueWithPath(meta, nil, "xmp:Label" as CFString, name as CFString)
        } else {
            CGImageMetadataRemoveTagWithPath(meta, nil, "xmp:Label" as CFString)
        }

        guard let xmp = CGImageMetadataCreateXMPData(meta, nil) else { return false }
        do {
            try (xmp as Data).write(to: sidecar, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
