import Foundation
import UniformTypeIdentifiers

struct ImageItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let fileSize: Int64
    let modified: Date
    let created: Date
    let type: UTType
    /// คะแนนดาว 0–5
    var rating: Int = 0
    /// ป้ายสี
    var label: ColorLabel = .none
    /// ไฟล์คู่ที่ถูกรวมไว้ (เช่น RAW ของ JPEG ชื่อเดียวกัน)
    var companions: [URL] = []
    /// ยังไม่เคยให้ดาว/ป้ายใน Iris → ควรอ่านค่าจาก XMP (Lightroom/กล้อง)
    var needsXMPCheck = false

    var id: URL { url }

    var ext: String { url.pathExtension.uppercased() }

    /// ไฟล์ทั้งหมดของรายการนี้ (ตัวหลัก + ไฟล์คู่)
    var allURLs: [URL] { [url] + companions }

    var badgeText: String {
        guard let first = companions.first else { return ext }
        return "\(ext)+\(first.pathExtension.uppercased())"
    }
    var isRaw: Bool { type.conforms(to: .rawImage) }
    var isAnimated: Bool { type.conforms(to: .gif) }
}

enum SortKey: String, CaseIterable, Identifiable {
    case name, modified, created, size, type, rating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "ชื่อไฟล์"
        case .modified: return "วันที่แก้ไข"
        case .created: return "วันที่สร้าง"
        case .size: return "ขนาดไฟล์"
        case .type: return "ชนิดไฟล์"
        case .rating: return "คะแนนดาว"
        }
    }
}

/// ตัวกรองตามป้ายสี
enum LabelFilter: Hashable {
    case any
    case unlabeled
    case label(ColorLabel)
}
