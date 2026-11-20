import Foundation
import ImageIO

/// หมุนภาพแบบไม่เสียคุณภาพ: เปลี่ยนแค่ค่า EXIF Orientation ไม่ถอดรหัส/บีบอัดภาพใหม่
enum ImageRotator {
    enum Direction {
        case left, right
    }

    enum RotateError: LocalizedError {
        case unreadable
        case unsupported(String)
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: return "อ่านไฟล์ไม่ได้"
            case .unsupported(let ext): return "ไฟล์ชนิด \(ext) หมุนแบบไม่เสียคุณภาพไม่ได้"
            case .writeFailed: return "บันทึกไฟล์ไม่สำเร็จ"
            }
        }
    }

    // ตาราง EXIF orientation เมื่อหมุนตามเข็ม/ทวนเข็ม 90°
    private static let clockwise: [Int: Int] = [1: 6, 2: 7, 3: 8, 4: 5, 5: 2, 6: 3, 7: 4, 8: 1]
    private static let counterClockwise: [Int: Int] = [1: 8, 2: 5, 3: 6, 4: 7, 5: 4, 6: 1, 7: 2, 8: 3]

    static func rotate(_ url: URL, _ direction: Direction) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source)
        else { throw RotateError.unreadable }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let current = props?[kCGImagePropertyOrientation as String] as? Int ?? 1
        let table = direction == .right ? clockwise : counterClockwise
        let next = table[current] ?? 1

        let folder = url.deletingLastPathComponent()
        let temp = folder.appendingPathComponent(".iris-rotate-\(UUID().uuidString).\(url.pathExtension)")
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil) else {
            throw RotateError.unsupported(url.pathExtension.uppercased())
        }

        let options: [CFString: Any] = [kCGImageDestinationOrientation: next]
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) else {
            try? FileManager.default.removeItem(at: temp)
            throw RotateError.unsupported(url.pathExtension.uppercased())
        }

        let saved = TagStore.snapshot(of: url)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw RotateError.writeFailed
        }
        TagStore.restore(saved, to: url)
    }
}
