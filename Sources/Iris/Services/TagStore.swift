import Foundation
import SwiftUI

/// ป้ายสี (ใช้ปุ่ม 6–9 แบบเดียวกับ Lightroom/ACDSee) — เก็บเป็น Finder tag จึงเห็นใน Finder ด้วย
enum ColorLabel: Int, CaseIterable, Identifiable, Hashable {
    case none = 0, red, yellow, green, blue, purple

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return "ไม่มีป้าย"
        case .red: return "แดง"
        case .yellow: return "เหลือง"
        case .green: return "เขียว"
        case .blue: return "น้ำเงิน"
        case .purple: return "ม่วง"
        }
    }

    var color: Color {
        switch self {
        case .none: return .clear
        case .red: return Color(red: 0.95, green: 0.27, blue: 0.27)
        case .yellow: return Color(red: 0.98, green: 0.78, blue: 0.18)
        case .green: return Color(red: 0.25, green: 0.78, blue: 0.38)
        case .blue: return Color(red: 0.24, green: 0.52, blue: 0.98)
        case .purple: return Color(red: 0.68, green: 0.40, blue: 0.92)
        }
    }

    /// คีย์ลัดที่แสดงในเมนู
    var shortcutHint: String? {
        switch self {
        case .red: return "6"
        case .yellow: return "7"
        case .green: return "8"
        case .blue: return "9"
        default: return nil
        }
    }

    /// หมายเลขสีของ Finder (0 ไม่มี, 1 เทา, 2 เขียว, 3 ม่วง, 4 น้ำเงิน, 5 เหลือง, 6 แดง, 7 ส้ม)
    var finderColorIndex: Int {
        switch self {
        case .none: return 0
        case .red: return 6
        case .yellow: return 5
        case .green: return 2
        case .blue: return 4
        case .purple: return 3
        }
    }

    init?(finderColorIndex: Int) {
        guard let match = ColorLabel.allCases.first(where: { $0 != .none && $0.finderColorIndex == finderColorIndex })
        else { return nil }
        self = match
    }

    /// ชื่อแท็กที่ถือว่าเป็น "ป้ายสี" (ทั้งที่ Iris สร้างและแท็กมาตรฐานของ Finder)
    static let managedTagNames: Set<String> = [
        "แดง", "เหลือง", "เขียว", "น้ำเงิน", "ม่วง",
        "Red", "Yellow", "Green", "Blue", "Purple"
    ]
}

/// อ่าน/เขียนคะแนนดาวและป้ายสีลง extended attributes ของไฟล์ (ไม่แตะเนื้อไฟล์ภาพ)
enum TagStore {
    static let ratingAttribute = "th.ac.utc.iris.rating"
    static let finderTagsAttribute = "com.apple.metadata:_kMDItemUserTags"

    // MARK: คะแนน

    static func rating(of url: URL) -> Int {
        storedRating(of: url) ?? 0
    }

    /// คะแนนที่ Iris บันทึกไว้ (nil = ยังไม่เคยให้คะแนนใน Iris → ไปอ่านจาก XMP แทน)
    static func storedRating(of url: URL) -> Int? {
        guard let data = XAttr.get(ratingAttribute, at: url),
              let s = String(data: data, encoding: .utf8),
              let n = Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return max(0, min(5, n))
    }

    /// บันทึก "0" ไว้ด้วยเมื่อล้างดาว เพื่อไม่ให้กลับไปอ่านดาวเก่าจาก XMP
    @discardableResult
    static func setRating(_ rating: Int, for url: URL) -> Bool {
        XAttr.set(ratingAttribute, data: Data("\(max(0, min(rating, 5)))".utf8), at: url)
    }

    // MARK: ป้ายสี (Finder tags)

    static func finderTags(of url: URL) -> [String] {
        guard let data = XAttr.get(finderTagsAttribute, at: url),
              let list = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String]
        else { return [] }
        return list
    }

    static func label(of url: URL) -> ColorLabel {
        for tag in finderTags(of: url) {
            let parts = tag.components(separatedBy: "\n")
            if parts.count >= 2, let index = Int(parts[1]), let label = ColorLabel(finderColorIndex: index) {
                return label
            }
        }
        return .none
    }

    @discardableResult
    static func setLabel(_ label: ColorLabel, for url: URL) -> Bool {
        var tags = finderTags(of: url).filter { tag in
            let name = tag.components(separatedBy: "\n").first ?? tag
            return !ColorLabel.managedTagNames.contains(name)
        }
        if label != .none {
            tags.insert("\(label.title)\n\(label.finderColorIndex)", at: 0)
        }
        if tags.isEmpty { return XAttr.remove(finderTagsAttribute, at: url) }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)
        else { return false }
        return XAttr.set(finderTagsAttribute, data: data, at: url)
    }

    // MARK: สำรอง/คืนค่า (ใช้ตอนเขียนไฟล์ใหม่ทับ เช่น หมุนภาพ)

    struct Snapshot {
        let rating: Data?
        let tags: Data?
    }

    static func snapshot(of url: URL) -> Snapshot {
        Snapshot(rating: XAttr.get(ratingAttribute, at: url), tags: XAttr.get(finderTagsAttribute, at: url))
    }

    static func restore(_ snapshot: Snapshot, to url: URL) {
        if let r = snapshot.rating { XAttr.set(ratingAttribute, data: r, at: url) }
        if let t = snapshot.tags { XAttr.set(finderTagsAttribute, data: t, at: url) }
    }
}

/// ตัวช่วยเรียก getxattr/setxattr ของระบบ
enum XAttr {
    static func get(_ name: String, at url: URL) -> Data? {
        let path = url.path
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { buffer in
            getxattr(path, name, buffer.baseAddress, length, 0, 0)
        }
        guard read >= 0 else { return nil }
        return data.prefix(read)
    }

    @discardableResult
    static func set(_ name: String, data: Data, at url: URL) -> Bool {
        let path = url.path
        let result = data.withUnsafeBytes { buffer in
            setxattr(path, name, buffer.baseAddress, data.count, 0, 0)
        }
        return result == 0
    }

    @discardableResult
    static func remove(_ name: String, at url: URL) -> Bool {
        let result = removexattr(url.path, name, 0)
        return result == 0 || errno == ENOATTR
    }
}
