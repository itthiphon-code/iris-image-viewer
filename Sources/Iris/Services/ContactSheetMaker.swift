import AppKit
import ImageIO

struct ContactSheetOptions: Equatable, Sendable {
    enum Paper: String, CaseIterable, Identifiable, Sendable {
        case a4, letter
        var id: String { rawValue }
        var title: String { self == .a4 ? "A4" : "Letter" }
        var size: CGSize { self == .a4 ? CGSize(width: 595.28, height: 841.89) : CGSize(width: 612, height: 792) }
    }

    var title = ""
    var columns = 4
    var paper: Paper = .a4
    var landscape = false
    var showFilename = true
    var showExposure = true
    var darkBackground = false

    var pageSize: CGSize {
        let s = paper.size
        return landscape ? CGSize(width: s.height, height: s.width) : s
    }
}

/// สร้าง PDF รวมภาพย่อ (contact sheet) แบ่งหน้าอัตโนมัติ
enum ContactSheetMaker {
    struct Entry: Sendable {
        let url: URL
        let name: String
    }

    enum MakeError: LocalizedError {
        case cannotCreate
        var errorDescription: String? { "สร้างไฟล์ PDF ไม่ได้" }
    }

    static func make(entries: [Entry], options o: ContactSheetOptions, to output: URL, flag: CancelFlag,
                     progress: @escaping @Sendable (Int) -> Void) throws {
        let page = o.pageSize
        let margin: CGFloat = 32
        let gap: CGFloat = 10
        let header: CGFloat = 38
        let footer: CGFloat = 18
        let columns = max(1, min(o.columns, 10))

        let cellWidth = (page.width - margin * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let imageHeight = cellWidth * 0.75
        let captionLines = (o.showFilename ? 1 : 0) + (o.showExposure ? 1 : 0)
        let captionHeight: CGFloat = captionLines == 0 ? 0 : CGFloat(captionLines) * 10 + 4
        let cellHeight = imageHeight + captionHeight
        let usable = page.height - margin * 2 - header - footer
        let rows = max(1, Int((usable + gap) / (cellHeight + gap)))
        let perPage = rows * columns
        let pageCount = max(1, Int(ceil(Double(entries.count) / Double(perPage))))
        let maxPixel = Int(min(1600, cellWidth * 3))

        var mediaBox = CGRect(origin: .zero, size: page)
        let info: [CFString: Any] = [kCGPDFContextCreator: "Iris", kCGPDFContextTitle: o.title]
        guard let ctx = CGContext(output as CFURL, mediaBox: &mediaBox, info as CFDictionary) else {
            throw MakeError.cannotCreate
        }

        let textColor = o.darkBackground ? NSColor.white : NSColor.black
        let subtleColor = o.darkBackground ? NSColor(white: 0.7, alpha: 1) : NSColor(white: 0.4, alpha: 1)
        let middle = NSMutableParagraphStyle()
        middle.lineBreakMode = .byTruncatingMiddle
        middle.alignment = .center

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: textColor
        ]
        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5), .foregroundColor: subtleColor
        ]
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7.5, weight: .medium), .foregroundColor: textColor, .paragraphStyle: middle
        ]
        let exifAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 6.5, weight: .regular),
            .foregroundColor: subtleColor, .paragraphStyle: middle
        ]
        let dateText = Date().formatted(date: .long, time: .omitted)

        var done = 0
        for p in 0..<pageCount {
            if flag.isCancelled { break }
            ctx.beginPDFPage(nil)
            let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics

            if o.darkBackground {
                ctx.setFillColor(NSColor(white: 0.1, alpha: 1).cgColor)
                ctx.fill(mediaBox)
            }

            // หัวกระดาษ
            NSAttributedString(string: o.title, attributes: titleAttrs)
                .draw(at: CGPoint(x: margin, y: page.height - margin - 16))
            let infoText = "\(entries.count) ภาพ  •  \(dateText)"
            let info = NSAttributedString(string: infoText, attributes: infoAttrs)
            info.draw(at: CGPoint(x: page.width - margin - info.size().width, y: page.height - margin - 14))
            ctx.setStrokeColor(subtleColor.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: margin, y: page.height - margin - header + 10))
            ctx.addLine(to: CGPoint(x: page.width - margin, y: page.height - margin - header + 10))
            ctx.strokePath()

            // ภาพ
            let start = p * perPage
            let end = min(start + perPage, entries.count)
            for i in start..<end {
                if flag.isCancelled { break }
                let entry = entries[i]
                let slot = i - start
                let row = slot / columns
                let col = slot % columns
                let x = margin + CGFloat(col) * (cellWidth + gap)
                let top = page.height - margin - header - CGFloat(row) * (cellHeight + gap)
                let imageBox = CGRect(x: x, y: top - imageHeight, width: cellWidth, height: imageHeight)

                ctx.setFillColor((o.darkBackground ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.95, alpha: 1)).cgColor)
                ctx.fill(imageBox)

                if let image = thumbnail(entry.url, maxPixel: maxPixel) {
                    let fit = aspectFit(CGSize(width: image.width, height: image.height), in: imageBox.insetBy(dx: 3, dy: 3))
                    ctx.interpolationQuality = .high
                    ctx.draw(image, in: fit)
                }

                var captionTop = imageBox.minY - 2
                if o.showFilename {
                    NSAttributedString(string: entry.name, attributes: nameAttrs)
                        .draw(in: CGRect(x: x, y: captionTop - 10, width: cellWidth, height: 10))
                    captionTop -= 10
                }
                if o.showExposure {
                    let line = exposureLine(entry.url)
                    if !line.isEmpty {
                        NSAttributedString(string: line, attributes: exifAttrs)
                            .draw(in: CGRect(x: x, y: captionTop - 10, width: cellWidth, height: 10))
                    }
                }
                done += 1
                progress(done)
            }

            // ท้ายกระดาษ
            let footerText = NSAttributedString(string: "หน้า \(p + 1) / \(pageCount)", attributes: infoAttrs)
            footerText.draw(at: CGPoint(x: (page.width - footerText.size().width) / 2, y: margin - 12))

            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    private static func thumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func aspectFit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    private static func exposureLine(_ url: URL) -> String {
        let m = MetadataReader.read(url)
        var parts: [String] = []
        if let f = m.focalLength { parts.append(Format.focal(f, eq35: nil)) }
        if let n = m.fNumber { parts.append(Format.aperture(n)) }
        if let t = m.exposureTime { parts.append(Format.exposure(t)) }
        if let iso = m.iso { parts.append("ISO \(iso)") }
        return parts.joined(separator: "  ")
    }
}
