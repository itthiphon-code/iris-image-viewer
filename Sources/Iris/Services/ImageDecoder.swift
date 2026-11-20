import AppKit
import ImageIO
import UniformTypeIdentifiers

/// ภาพที่ถอดรหัสเต็มความละเอียดแล้ว
final class DecodedImage {
    let image: NSImage
    let pixelSize: CGSize

    init(image: NSImage, pixelSize: CGSize) {
        self.image = image
        self.pixelSize = pixelSize
    }

    var memoryCost: Int { Int(pixelSize.width * pixelSize.height * 4) }
}

enum ImageDecoder {
    /// ขนาดภาพจริง (หลังหมุนตาม EXIF orientation) อ่านจาก header อย่างเดียว เร็วมาก
    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let w = props[kCGImagePropertyPixelWidth as String] as? Int,
              let h = props[kCGImagePropertyPixelHeight as String] as? Int
        else { return nil }
        let orientation = props[kCGImagePropertyOrientation as String] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    /// ถอดรหัสภาพเต็ม (จำกัดด้านยาวสุดไว้ที่ maxPixel เพื่อกันหน่วยความจำล้น)
    static func loadFull(url: URL, maxPixel: Int = 16_384) -> DecodedImage? {
        let type = UTType(filenameExtension: url.pathExtension)

        // GIF ใช้ NSImage ตรง ๆ เพื่อให้ NSImageView เล่นแอนิเมชันได้
        if type?.conforms(to: .gif) == true, let img = NSImage(contentsOf: url) {
            let px = pixelSize(of: url) ?? img.size
            return DecodedImage(image: img, pixelSize: px)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let size = pixelSize(of: url) ?? CGSize(width: 8192, height: 8192)
        let longest = min(Int(max(size.width, size.height)), maxPixel)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(longest, 1)
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let px = CGSize(width: cg.width, height: cg.height)
        return DecodedImage(image: NSImage(cgImage: cg, size: px), pixelSize: px)
    }
}
