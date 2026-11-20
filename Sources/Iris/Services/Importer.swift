import Foundation
import UniformTypeIdentifiers

/// รูปแบบโฟลเดอร์ปลายทางตามวันที่ถ่าย
enum ImportPattern: String, CaseIterable, Identifiable {
    case yearDay, day, yearMonthDay, yearMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yearDay: return "2026/2026-11-17"
        case .day: return "2026-11-17"
        case .yearMonthDay: return "2026/11/17"
        case .yearMonth: return "2026/2026-11"
        }
    }

    /// ส่วนของพาธ (โฟลเดอร์ย่อยทีละชั้น)
    func components(for date: Date) -> [String] {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        let y = String(format: "%04d", c.year ?? 1970)
        let m = String(format: "%02d", c.month ?? 1)
        let d = String(format: "%02d", c.day ?? 1)
        switch self {
        case .yearDay: return [y, "\(y)-\(m)-\(d)"]
        case .day: return ["\(y)-\(m)-\(d)"]
        case .yearMonthDay: return [y, m, d]
        case .yearMonth: return [y, "\(y)-\(m)"]
        }
    }
}

struct ImportCandidate: Identifiable, Sendable {
    let url: URL
    let date: Date
    let size: Int64
    var id: URL { url }
}

/// กลุ่มไฟล์ตามวันที่ถ่าย (ใช้แสดงในหน้าต่างนำเข้า)
struct ImportDay: Identifiable {
    let day: Date
    var files: [ImportCandidate]
    var include = true

    var id: Date { day }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
}

enum Importer {
    enum Outcome: Sendable {
        case copied, skipped
    }

    /// ไล่หาไฟล์ภาพ (และวิดีโอถ้าเลือก) ทั้งหมดในต้นทาง อ่านวันที่ถ่ายจาก EXIF
    static func scan(source: URL, includeVideos: Bool, flag: CancelFlag,
                     progress: @escaping @Sendable (Int) -> Void) -> [ImportCandidate] {
        let keys: [URLResourceKey] = [.contentTypeKey, .fileSizeKey, .creationDateKey,
                                      .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: source, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [ImportCandidate] = []
        for case let url as URL in enumerator {
            if flag.isCancelled { break }
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.isRegularFile == true,
                  let type = v.contentType
            else { continue }
            let isImage = type.conforms(to: .image)
            let isVideo = includeVideos && (type.conforms(to: .movie) || type.conforms(to: .video))
            guard isImage || isVideo else { continue }

            let fallback = v.creationDate ?? v.contentModificationDate ?? Date()
            let date = isImage ? (MetadataReader.read(url).dateTaken ?? fallback) : fallback
            result.append(ImportCandidate(url: url, date: date, size: Int64(v.fileSize ?? 0)))
            if result.count % 25 == 0 { progress(result.count) }
        }
        progress(result.count)
        return result.sorted { $0.date < $1.date }
    }

    static func group(_ files: [ImportCandidate]) -> [ImportDay] {
        let calendar = Calendar(identifier: .gregorian)
        let grouped = Dictionary(grouping: files) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { ImportDay(day: $0, files: grouped[$0] ?? []) }
    }

    static func folder(for date: Date, root: URL, pattern: ImportPattern, event: String) -> URL {
        var url = root
        var parts = pattern.components(for: date)
        let trimmed = event.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, let last = parts.popLast() {
            parts.append("\(last) \(trimmed.replacingOccurrences(of: "/", with: "-"))")
        }
        for p in parts { url.appendPathComponent(p, isDirectory: true) }
        return url
    }

    /// คัดลอกไฟล์เดียว — ถ้ามีไฟล์ชื่อเดียวกันและขนาดเท่ากันอยู่แล้ว ถือว่านำเข้าแล้ว (ข้าม)
    static func copy(_ file: ImportCandidate, to folder: URL, skipDuplicates: Bool) throws -> Outcome {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var target = folder.appendingPathComponent(file.url.lastPathComponent)

        if fm.fileExists(atPath: target.path) {
            let existing = (try? fm.attributesOfItem(atPath: target.path)[.size] as? Int64) ?? -1
            if skipDuplicates && existing == file.size { return .skipped }
            let base = file.url.deletingPathExtension().lastPathComponent
            let ext = file.url.pathExtension
            var n = 2
            repeat {
                target = folder.appendingPathComponent(ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)")
                n += 1
            } while fm.fileExists(atPath: target.path)
        }
        try fm.copyItem(at: file.url, to: target)
        return .copied
    }
}
