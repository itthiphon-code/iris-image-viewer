import Foundation
import UniformTypeIdentifiers

/// เงื่อนไขค้นหาขั้นสูง
struct SearchCriteria: Equatable, Sendable {
    enum FormatFilter: String, CaseIterable, Identifiable, Sendable {
        case any, raw, jpeg, heic, png, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: return "ทุกชนิด"
            case .raw: return "RAW"
            case .jpeg: return "JPEG"
            case .heic: return "HEIC"
            case .png: return "PNG"
            case .other: return "อื่น ๆ"
            }
        }
    }

    var includeSubfolders = true
    var name = ""
    var camera = ""
    var lens = ""
    var useDateRange = false
    var dateFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var dateTo = Date()
    var useISO = false
    var isoMin = 100
    var isoMax = 6400
    var minRating = 0
    var label: ColorLabel? = nil
    var format: FormatFilter = .any

    /// ต้องเปิดอ่าน EXIF หรือไม่ (ช้ากว่าเงื่อนไขอื่น)
    var needsEXIF: Bool {
        !camera.trimmingCharacters(in: .whitespaces).isEmpty
            || !lens.trimmingCharacters(in: .whitespaces).isEmpty
            || useDateRange || useISO
    }

    var summary: String {
        var parts: [String] = []
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { parts.append("ชื่อ “\(n)”") }
        let c = camera.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty { parts.append("กล้อง “\(c)”") }
        let l = lens.trimmingCharacters(in: .whitespaces)
        if !l.isEmpty { parts.append("เลนส์ “\(l)”") }
        if useDateRange {
            parts.append("\(dateFrom.formatted(date: .abbreviated, time: .omitted))–\(dateTo.formatted(date: .abbreviated, time: .omitted))")
        }
        if useISO { parts.append("ISO \(isoMin)–\(isoMax)") }
        if minRating > 0 { parts.append("★\(minRating)+") }
        if let label { parts.append("ป้าย\(label.title)") }
        if format != .any { parts.append(format.title) }
        return parts.isEmpty ? "ทุกรูป" : parts.joined(separator: ", ")
    }
}

enum MetadataSearch {
    /// ค้นหาภาพในโฟลเดอร์ (และโฟลเดอร์ย่อย) ตามเงื่อนไข
    static func run(root: URL, criteria c: SearchCriteria, groupPairs: Bool, flag: CancelFlag,
                    progress: @escaping @Sendable (Int, Int) -> Void) -> [ImageItem] {
        let folders = c.includeSubfolders ? allFolders(under: root, flag: flag) : [root]
        let nameQuery = c.name.trimmingCharacters(in: .whitespaces)
        let cameraQuery = c.camera.trimmingCharacters(in: .whitespaces)
        let lensQuery = c.lens.trimmingCharacters(in: .whitespaces)
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: min(c.dateFrom, c.dateTo))
        let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(c.dateFrom, c.dateTo))) ?? c.dateTo

        var results: [ImageItem] = []
        var scanned = 0
        for folder in folders {
            if flag.isCancelled { break }
            let scannedItems = FolderScanner.scanImages(in: folder)
            let list = groupPairs ? FolderScanner.groupRawPairs(scannedItems) : scannedItems
            for item in list {
                if flag.isCancelled { break }
                scanned += 1
                if scanned % 50 == 0 { progress(scanned, results.count) }

                if !nameQuery.isEmpty && !item.name.localizedCaseInsensitiveContains(nameQuery) { continue }
                if c.minRating > 0 && item.rating < c.minRating { continue }
                if let wanted = c.label, item.label != wanted { continue }
                if !matches(item, c.format) { continue }

                if c.needsEXIF {
                    let m = MetadataReader.read(item.url)
                    if !cameraQuery.isEmpty {
                        let cam = [m.cameraMake, m.cameraModel].compactMap { $0 }.joined(separator: " ")
                        if !cam.localizedCaseInsensitiveContains(cameraQuery) { continue }
                    }
                    if !lensQuery.isEmpty && !(m.lens ?? "").localizedCaseInsensitiveContains(lensQuery) { continue }
                    if c.useDateRange {
                        let date = m.dateTaken ?? item.created
                        if date < from || date >= to { continue }
                    }
                    if c.useISO {
                        guard let iso = m.iso, iso >= min(c.isoMin, c.isoMax), iso <= max(c.isoMin, c.isoMax) else { continue }
                    }
                }
                results.append(item)
            }
        }
        progress(scanned, results.count)
        return results
    }

    private static func matches(_ item: ImageItem, _ format: SearchCriteria.FormatFilter) -> Bool {
        let t = item.type
        switch format {
        case .any: return true
        case .raw: return item.isRaw || !item.companions.isEmpty
        case .jpeg: return t.conforms(to: .jpeg)
        case .heic: return t.conforms(to: .heic) || t.conforms(to: .heif)
        case .png: return t.conforms(to: .png)
        case .other:
            return !(item.isRaw || t.conforms(to: .jpeg) || t.conforms(to: .heic)
                     || t.conforms(to: .heif) || t.conforms(to: .png))
        }
    }

    private static func allFolders(under root: URL, flag: CancelFlag) -> [URL] {
        var folders = [root]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return folders }
        for case let url as URL in enumerator {
            if flag.isCancelled { break }
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.isDirectory == true, v.isPackage != true else { continue }
            folders.append(url)
        }
        return folders
    }
}
