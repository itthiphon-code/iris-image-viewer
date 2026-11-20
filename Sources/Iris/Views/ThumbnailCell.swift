import SwiftUI
import AppKit

struct ThumbnailCell: View {
    let item: ImageItem
    let size: CGFloat
    let isSelected: Bool
    let isCursor: Bool

    @State private var image: NSImage?
    @State private var hovering = false

    private var bucket: Int { ThumbnailLoader.bucket(forPoints: size) }

    init(item: ImageItem, size: CGFloat, isSelected: Bool, isCursor: Bool) {
        self.item = item
        self.size = size
        self.isSelected = isSelected
        self.isCursor = isCursor
        // ถ้ามีในแคชอยู่แล้วให้แสดงทันที ไม่ต้องกะพริบ
        let b = ThumbnailLoader.bucket(forPoints: size)
        _image = State(initialValue: ThumbnailLoader.shared.cached(item.url, bucket: b)
            ?? ThumbnailLoader.shared.bestCached(item.url))
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundFill)

                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: size * 0.22, weight: .light))
                            .foregroundStyle(.quaternary)
                    }
                }
                .padding(size * 0.07)
                .frame(width: size, height: size)

                if size >= 120 {
                    Text(item.badgeText)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(7)
                        .opacity(hovering || isSelected || item.isRaw || !item.companions.isEmpty ? 1 : 0)
                }
            }
            .frame(width: size, height: size)
            .overlay(alignment: .bottomLeading) {
                if item.rating > 0 {
                    StarsBadge(rating: item.rating, size: size >= 140 ? 9 : 7)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                if item.label != .none {
                    Capsule()
                        .fill(item.label.color)
                        .frame(width: size * 0.32, height: 4)
                        .padding(.bottom, 2)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : (isCursor ? Color.accentColor.opacity(0.4) : .clear),
                                  lineWidth: isSelected ? 2.5 : 1.5)
            }

            HStack(spacing: 4) {
                if item.label != .none { LabelDot(label: item.label, size: 8) }
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
                .font(.system(size: 11.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: size)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("\(item.name)\n\(Format.bytes(item.fileSize)) • \(Format.date(item.modified))")
        .task(id: "\(item.url.path)#\(bucket)#\(item.modified.timeIntervalSince1970)") {
            if let cached = ThumbnailLoader.shared.cached(item.url, bucket: bucket) {
                image = cached
                return
            }
            if let loaded = await ThumbnailLoader.shared.thumbnail(for: item.url, bucket: bucket) {
                image = loaded
            }
        }
    }

    private var backgroundFill: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if hovering { return Color.primary.opacity(0.07) }
        return Color.primary.opacity(0.025)
    }

    private var badgeColor: Color {
        if item.isRaw || !item.companions.isEmpty { return .orange }
        switch item.ext {
        case "HEIC", "HEIF": return .purple
        case "PNG": return .teal
        case "GIF": return .pink
        case "TIF", "TIFF": return .indigo
        case "WEBP": return .green
        default: return .gray
        }
    }
}
