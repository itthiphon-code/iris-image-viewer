import AppKit
import ImageIO

/// สร้างและแคชภาพย่อด้วย ImageIO (เร็ว รองรับ JPEG/HEIC/PNG/TIFF/RAW/WebP ฯลฯ)
final class ThumbnailLoader: @unchecked Sendable {
    static let shared = ThumbnailLoader()

    /// ขนาดภาพย่อ (พิกเซล) ที่ใช้แคช ปัดขึ้นเป็นขั้น ๆ เพื่อให้แคชถูกใช้ซ้ำ
    static let buckets = [256, 512, 768]

    private let cache = NSCache<NSString, NSImage>()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "iris.thumbnails"
        q.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        q.qualityOfService = .userInitiated
        return q
    }()

    private init() {
        cache.countLimit = 3000
    }

    static func bucket(forPoints points: CGFloat, scale: CGFloat = 2) -> Int {
        let needed = Int(points * scale)
        return buckets.first { $0 >= needed } ?? buckets.last!
    }

    func cached(_ url: URL, bucket: Int) -> NSImage? {
        cache.object(forKey: key(url, bucket))
    }

    /// ภาพย่อที่ใหญ่ที่สุดที่มีในแคชอยู่แล้ว (ใช้แสดงชั่วคราวระหว่างโหลดภาพเต็ม)
    func bestCached(_ url: URL) -> NSImage? {
        for b in Self.buckets.reversed() {
            if let img = cache.object(forKey: key(url, b)) { return img }
        }
        return nil
    }

    func thumbnail(for url: URL, bucket: Int) async -> NSImage? {
        let k = key(url, bucket)
        if let img = cache.object(forKey: k) { return img }

        let flag = CancelFlag()
        let image: NSImage? = await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<NSImage?, Never>) in
                queue.addOperation {
                    if flag.isCancelled {
                        cont.resume(returning: nil)
                        return
                    }
                    cont.resume(returning: Self.makeThumbnail(url: url, maxPixel: bucket))
                }
            }
        } onCancel: {
            flag.cancel()
        }

        if let image { cache.setObject(image, forKey: k) }
        return image
    }

    func removeAll(for url: URL) {
        for b in Self.buckets { cache.removeObject(forKey: key(url, b)) }
    }

    private func key(_ url: URL, _ bucket: Int) -> NSString {
        "\(url.path)#\(bucket)" as NSString
    }

    static func makeThumbnail(url: URL, maxPixel: Int) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// ธงยกเลิกงานที่ส่งข้ามเธรดได้
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}
