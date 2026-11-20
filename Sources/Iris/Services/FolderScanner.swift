import Foundation
import UniformTypeIdentifiers

struct SubfolderInfo {
    let url: URL
    let hasSubfolders: Bool
}

/// อ่านเนื้อหาโฟลเดอร์ (ทำงานบน background thread)
enum FolderScanner {
    private static let imageKeys: [URLResourceKey] = [
        .contentTypeKey, .fileSizeKey, .contentModificationDateKey,
        .creationDateKey, .isRegularFileKey
    ]

    /// รายการไฟล์ภาพทั้งหมดในโฟลเดอร์ (ไม่รวมโฟลเดอร์ย่อย)
    static func scanImages(in folder: URL) -> [ImageItem] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: imageKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [ImageItem] = []
        result.reserveCapacity(urls.count)
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(imageKeys)),
                  v.isRegularFile == true,
                  let type = v.contentType,
                  type.conforms(to: .image)
            else { continue }
            result.append(makeItem(url: url, values: v, type: type))
        }
        return result
    }

    /// รวม RAW กับ JPEG/HEIC ที่ชื่อเดียวกัน ให้ JPEG/HEIC เป็นตัวแสดง (โหลดเร็วกว่า) และเก็บ RAW เป็นไฟล์คู่
    static func groupRawPairs(_ items: [ImageItem]) -> [ImageItem] {
        var groups: [String: [Int]] = [:]
        for (i, item) in items.enumerated() {
            let base = (item.name as NSString).deletingPathExtension.lowercased()
            groups[base, default: []].append(i)
        }

        var result = items
        var dropped = Set<Int>()
        for (_, indices) in groups where indices.count > 1 {
            let raws = indices.filter { items[$0].isRaw }
            let primary = indices.first { i in
                let t = items[i].type
                return !items[i].isRaw && (t.conforms(to: .jpeg) || t.conforms(to: .heic) || t.conforms(to: .heif))
            }
            guard let p = primary, !raws.isEmpty else { continue }
            result[p].companions = raws.map { items[$0].url }
            // ถ้าตัวหลักยังไม่มีดาว/ป้าย ให้ใช้ของไฟล์ RAW
            if result[p].rating == 0 { result[p].rating = raws.map { items[$0].rating }.max() ?? 0 }
            if result[p].label == .none,
               let label = raws.map({ items[$0].label }).first(where: { $0 != .none }) {
                result[p].label = label
            }
            result[p].needsXMPCheck = result[p].needsXMPCheck && raws.allSatisfy { items[$0].needsXMPCheck }
            dropped.formUnion(raws)
        }
        return result.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
    }

    /// อ่านข้อมูลไฟล์เดียวใหม่ (หลังหมุนภาพ/เปลี่ยนชื่อ)
    static func item(at url: URL) -> ImageItem? {
        var url = url
        url.removeAllCachedResourceValues()
        guard let v = try? url.resourceValues(forKeys: Set(imageKeys)),
              v.isRegularFile == true,
              let type = v.contentType,
              type.conforms(to: .image)
        else { return nil }
        return makeItem(url: url, values: v, type: type)
    }

    private static func makeItem(url: URL, values v: URLResourceValues, type: UTType) -> ImageItem {
        let stored = TagStore.storedRating(of: url)
        let label = TagStore.label(of: url)
        return ImageItem(
            url: url,
            name: url.lastPathComponent,
            fileSize: Int64(v.fileSize ?? 0),
            modified: v.contentModificationDate ?? .distantPast,
            created: v.creationDate ?? .distantPast,
            type: type,
            rating: stored ?? 0,
            label: label,
            needsXMPCheck: stored == nil && label == .none
        )
    }

    /// โฟลเดอร์ย่อย (ไม่รวม package เช่น .app, .photoslibrary)
    static func subfolders(of folder: URL) -> [SubfolderInfo] {
        directories(in: folder).map { SubfolderInfo(url: $0, hasSubfolders: !directories(in: $0, limit: 1).isEmpty) }
    }

    private static func directories(in folder: URL, limit: Int = .max) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var dirs: [URL] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.isDirectory == true, v.isPackage != true
            else { continue }
            dirs.append(url)
            if dirs.count >= limit { break }
        }
        return dirs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
