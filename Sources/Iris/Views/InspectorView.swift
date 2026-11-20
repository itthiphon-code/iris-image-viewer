import SwiftUI
import AppKit

/// แผงข้อมูลภาพ: พรีวิว, ฮิสโตแกรม, ข้อมูลไฟล์, EXIF กล้อง, สี, GPS
struct InspectorView: View {
    let item: ImageItem?

    @State private var preview: NSImage?
    @State private var meta: ImageMetadata?
    @State private var histogram: Histogram?

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        previewSection
                        HistogramView(histogram: histogram)
                            .frame(height: 74)
                        RatingSection(item: item)
                        fileSection(item)
                        if let meta, meta.hasCameraInfo { cameraSection(meta) }
                        if let meta { colorSection(meta) }
                        if let meta, let lat = meta.latitude, let lon = meta.longitude { gpsSection(lat, lon) }
                    }
                    .padding(16)
                }
                .task(id: "\(item.url.path)#\(item.modified.timeIntervalSince1970)") { await load(item) }
            } else {
                ContentUnavailableView("ไม่ได้เลือกรูป", systemImage: "photo",
                                       description: Text("คลิกรูปเพื่อดูรายละเอียด"))
            }
        }
    }

    // MARK: - Sections

    private var previewSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.85))
            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(height: 190)
    }

    private func fileSection(_ item: ImageItem) -> some View {
        InfoSection(title: "ไฟล์", systemImage: "doc") {
            InfoRow("ชื่อ", item.name)
            InfoRow("ชนิด", item.type.localizedDescription ?? item.ext)
            if let w = meta?.pixelWidth, let h = meta?.pixelHeight {
                let mp = meta?.megapixels.map { String(format: "  (%.1f MP)", $0) } ?? ""
                InfoRow("ขนาดภาพ", "\(w) × \(h)\(mp)")
            }
            InfoRow("ขนาดไฟล์", Format.bytes(item.fileSize))
            if !item.companions.isEmpty {
                InfoRow("ไฟล์คู่", item.companions.map(\.lastPathComponent).joined(separator: ", "))
            }
            InfoRow("แก้ไขล่าสุด", Format.date(item.modified))
            InfoRow("สร้างเมื่อ", Format.date(item.created))
            InfoRow("ตำแหน่ง", item.url.deletingLastPathComponent().path)
        }
    }

    private func cameraSection(_ m: ImageMetadata) -> some View {
        InfoSection(title: "กล้อง", systemImage: "camera") {
            if m.cameraMake != nil || m.cameraModel != nil {
                InfoRow("กล้อง", cameraName(m))
            }
            if let lens = m.lens { InfoRow("เลนส์", lens) }
            if let date = m.dateTaken { InfoRow("วันที่ถ่าย", Format.date(date)) }

            HStack(spacing: 6) {
                if let f = m.focalLength { ExposureChip(Format.focal(f, eq35: nil)) }
                if let n = m.fNumber { ExposureChip(Format.aperture(n)) }
                if let t = m.exposureTime { ExposureChip(Format.exposure(t)) }
                if let iso = m.iso { ExposureChip("ISO \(iso)") }
            }
            .padding(.vertical, 2)

            if let f = m.focalLength, let eq = m.focalLength35, eq > 0, Double(eq) != f.rounded() {
                InfoRow("เทียบฟูลเฟรม", "\(eq) mm")
            }
            if let ev = m.exposureBias, ev != 0 { InfoRow("ชดเชยแสง", String(format: "%+.1f EV", ev)) }
            if let flash = m.flashFired { InfoRow("แฟลช", flash ? "ยิง" : "ไม่ยิง") }
            if let sw = m.software { InfoRow("ซอฟต์แวร์", sw) }
        }
    }

    private func colorSection(_ m: ImageMetadata) -> some View {
        InfoSection(title: "สี", systemImage: "paintpalette") {
            if let p = m.profileName { InfoRow("โปรไฟล์สี", p) }
            if let c = m.colorModel { InfoRow("โมเดลสี", c) }
            if let d = m.bitDepth { InfoRow("ความลึกสี", "\(d) บิต/ช่อง") }
            if let dpi = m.dpi { InfoRow("ความละเอียด", "\(dpi) dpi") }
        }
    }

    private func gpsSection(_ lat: Double, _ lon: Double) -> some View {
        InfoSection(title: "ตำแหน่งที่ถ่าย", systemImage: "location") {
            InfoRow("พิกัด", Format.coordinate(lat, lon))
            Button {
                if let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lon)&q=Photo") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("เปิดในแผนที่", systemImage: "map")
            }
            .controlSize(.small)
        }
    }

    private func cameraName(_ m: ImageMetadata) -> String {
        let make = m.cameraMake ?? ""
        let model = m.cameraModel ?? ""
        if !make.isEmpty, model.lowercased().hasPrefix(make.lowercased().components(separatedBy: " ").first ?? "") {
            return model
        }
        return [make, model].filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Loading

    @MainActor
    private func load(_ item: ImageItem) async {
        preview = ThumbnailLoader.shared.bestCached(item.url)
        meta = nil
        histogram = nil

        let url = item.url
        let loadedMeta = await Task.detached(priority: .userInitiated) { MetadataReader.read(url) }.value
        guard !Task.isCancelled else { return }
        meta = loadedMeta

        guard let thumb = await ThumbnailLoader.shared.thumbnail(for: url, bucket: 512),
              !Task.isCancelled else { return }
        preview = thumb
        if let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let h = await Task.detached(priority: .utility) { Histogram.compute(from: cg) }.value
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { histogram = h }
        }
    }
}

// MARK: - Components

struct InfoSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}

struct ExposureChip: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct HistogramView: View {
    let histogram: Histogram?

    var body: some View {
        Canvas { context, size in
            guard let h = histogram else { return }
            context.blendMode = .plusLighter
            let channels: [([Float], Color)] = [
                (h.red, Color(red: 1, green: 0.25, blue: 0.25)),
                (h.green, Color(red: 0.25, green: 0.9, blue: 0.35)),
                (h.blue, Color(red: 0.3, green: 0.5, blue: 1))
            ]
            for (values, color) in channels {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for i in 0..<values.count {
                    let x = CGFloat(i) / CGFloat(values.count - 1) * size.width
                    let y = size.height * (1 - CGFloat(values[i]) * 0.95)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(color.opacity(0.6)))
            }
        }
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if histogram == nil {
                Text("ฮิสโตแกรม").font(.caption2).foregroundStyle(.white.opacity(0.3))
            }
        }
    }
}
