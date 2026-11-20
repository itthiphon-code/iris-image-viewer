import Foundation

/// เปลี่ยนชื่อหลายไฟล์ตามแม่แบบ เช่น "{folder}_{n}" หรือ "{date}_{name}"
struct RenameTemplate: Equatable {
    var pattern = "{folder}_{n}"
    var startNumber = 1
    var digits = 3
    var extensionCase: ExtensionCase = .keep

    enum ExtensionCase: String, CaseIterable, Identifiable {
        case keep, lower, upper
        var id: String { rawValue }
        var title: String {
            switch self {
            case .keep: return "คงเดิม"
            case .lower: return "ตัวเล็ก (.jpg)"
            case .upper: return "ตัวใหญ่ (.JPG)"
            }
        }
    }

    static let tokens: [(token: String, meaning: String)] = [
        ("{n}", "ลำดับเลข"),
        ("{name}", "ชื่อเดิม"),
        ("{folder}", "ชื่อโฟลเดอร์"),
        ("{date}", "วันที่ถ่าย ปีเดือนวัน"),
        ("{time}", "เวลาถ่าย ชั่วโมงนาทีวินาที")
    ]
}

struct RenamePlanEntry: Identifiable {
    let source: URL
    let newName: String
    var conflict: String?

    var id: URL { source }
    var isUnchanged: Bool { source.lastPathComponent == newName }
}

enum BatchRenamer {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HHmmss"
        return f
    }()

    /// สร้างรายการชื่อใหม่ (ยังไม่เปลี่ยนจริง) พร้อมตรวจชื่อซ้ำ
    /// - Parameter dates: วันที่ถ่ายจาก EXIF (ถ้าไม่มีจะใช้วันที่แก้ไขไฟล์)
    static func plan(items: [ImageItem], template: RenameTemplate, dates: [URL: Date]) -> [RenamePlanEntry] {
        let digits = max(1, min(template.digits, 8))

        var entries: [RenamePlanEntry] = []
        var included = Set<URL>()
        func add(_ source: URL, _ newName: String) {
            guard included.insert(source).inserted else { return }
            entries.append(RenamePlanEntry(source: source, newName: newName))
        }

        for (offset, item) in items.enumerated() {
            let folderName = item.url.deletingLastPathComponent().lastPathComponent
            let base = (item.name as NSString).deletingPathExtension
            let date = dates[item.url] ?? item.modified
            let number = String(format: "%0\(digits)ld", template.startNumber + offset)

            var name = template.pattern
            name = name.replacingOccurrences(of: "{n}", with: number)
            name = name.replacingOccurrences(of: "{name}", with: base)
            name = name.replacingOccurrences(of: "{folder}", with: folderName)
            name = name.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: date))
            name = name.replacingOccurrences(of: "{time}", with: timeFormatter.string(from: date))
            name = sanitize(name)
            if name.isEmpty { name = base }

            // ไฟล์คู่ (RAW) ได้ชื่อเดียวกัน ต่างแค่นามสกุล และ sidecar .xmp เปลี่ยนตามด้วย
            for url in item.allURLs {
                var ext = url.pathExtension
                switch template.extensionCase {
                case .keep: break
                case .lower: ext = ext.lowercased()
                case .upper: ext = ext.uppercased()
                }
                add(url, ext.isEmpty ? name : "\(name).\(ext)")

                for sidecar in XMPStore.existingSidecars(for: url) {
                    // IMG_0001.xmp → ชื่อใหม่.xmp ; IMG_0001.CR3.xmp → ชื่อใหม่.CR3.xmp
                    let style = sidecar.deletingPathExtension().lastPathComponent == url.lastPathComponent
                        ? "\(name).\(url.pathExtension).xmp"
                        : "\(name).xmp"
                    add(sidecar, style)
                }
            }
        }

        // ตรวจชื่อซ้ำ (แยกตามโฟลเดอร์) และชนกับไฟล์อื่นที่ไม่ได้อยู่ในชุดนี้
        func key(_ folder: URL, _ name: String) -> String { folder.path + "/" + name.lowercased() }
        let sources = Set(entries.map { key($0.source.deletingLastPathComponent(), $0.source.lastPathComponent) })
        var seen: [String: Int] = [:]
        for entry in entries { seen[key(entry.source.deletingLastPathComponent(), entry.newName), default: 0] += 1 }
        let fm = FileManager.default
        for i in entries.indices {
            let folder = entries[i].source.deletingLastPathComponent()
            let k = key(folder, entries[i].newName)
            if (seen[k] ?? 0) > 1 {
                entries[i].conflict = "ชื่อซ้ำกันในชุดนี้"
            } else if !sources.contains(k),
                      fm.fileExists(atPath: folder.appendingPathComponent(entries[i].newName).path) {
                entries[i].conflict = "มีไฟล์ชื่อนี้อยู่แล้ว"
            }
        }
        return entries
    }

    /// เปลี่ยนชื่อจริงแบบ 2 จังหวะ (ผ่านชื่อชั่วคราว) เพื่อไม่ให้ชนกันเองเวลาสลับลำดับ
    /// - Returns: URL ใหม่ของไฟล์ที่เปลี่ยนสำเร็จ
    static func apply(_ entries: [RenamePlanEntry]) throws -> [URL] {
        let fm = FileManager.default
        let work = entries.filter { $0.conflict == nil && !$0.isUnchanged }
        var moved: [(source: URL, temp: URL, final: URL)] = []

        // จังหวะที่ 1: ย้ายไปชื่อชั่วคราว (ถ้าพลาด คืนชื่อเดิมทั้งหมด)
        do {
            for entry in work {
                let folder = entry.source.deletingLastPathComponent()
                let temp = folder.appendingPathComponent(".iris-rename-\(UUID().uuidString)")
                try fm.moveItem(at: entry.source, to: temp)
                moved.append((entry.source, temp, folder.appendingPathComponent(entry.newName)))
            }
        } catch {
            for m in moved { try? fm.moveItem(at: m.temp, to: m.source) }
            throw error
        }

        // จังหวะที่ 2: ตั้งชื่อใหม่ (ถ้าพลาด ไฟล์ที่ยังไม่ได้ตั้งชื่อจะได้ชื่อเดิมคืน)
        var results: [URL] = []
        for (i, m) in moved.enumerated() {
            do {
                try fm.moveItem(at: m.temp, to: m.final)
                results.append(m.final)
            } catch {
                for rest in moved[i...] { try? fm.moveItem(at: rest.temp, to: rest.source) }
                throw error
            }
        }
        return results
    }

    private static func sanitize(_ s: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\\0")
        return s.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
    }
}
