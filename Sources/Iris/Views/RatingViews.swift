import SwiftUI

/// ดาวแบบกดได้ (กดดาวเดิมซ้ำ = ล้างคะแนน)
struct StarRatingEditor: View {
    let rating: Int
    var size: CGFloat = 15
    let onChange: (Int) -> Void

    @State private var hovered: Int?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { star in
                let filled = star <= (hovered ?? rating)
                Image(systemName: filled ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(filled ? Color.yellow : Color.secondary.opacity(0.6))
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hovered = star } else if hovered == star { hovered = nil }
                    }
                    .onTapGesture {
                        onChange(star == rating ? 0 : star)
                    }
                    .help("\(star) ดาว  (กดปุ่ม \(star))")
            }
        }
    }
}

/// ดาวขนาดเล็กสำหรับแสดงบนภาพย่อ
struct StarsBadge: View {
    let rating: Int
    var size: CGFloat = 9

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<rating, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.system(size: size, weight: .semibold))
            }
        }
        .foregroundStyle(Color.yellow)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.55), in: Capsule())
    }
}

/// จุดสีของป้าย
struct LabelDot: View {
    let label: ColorLabel
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(label.color)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
    }
}

/// ปุ่มเลือกป้ายสี
struct LabelPicker: View {
    let label: ColorLabel
    let onChange: (ColorLabel) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(ColorLabel.allCases.filter { $0 != .none }) { option in
                Button {
                    onChange(option)
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            if option == label {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(Circle().strokeBorder(Color.primary.opacity(option == label ? 0.5 : 0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(option.shortcutHint.map { "\(option.title)  (กดปุ่ม \($0))" } ?? option.title)
            }
            if label != .none {
                Button {
                    onChange(.none)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("เอาป้ายสีออก")
            }
        }
    }
}

/// ส่วน "การจัดระดับ" ในแผงข้อมูล
struct RatingSection: View {
    let item: ImageItem
    @Environment(BrowserModel.self) private var model

    var body: some View {
        InfoSection(title: "การจัดระดับ", systemImage: "star") {
            HStack {
                Text("คะแนน").foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                StarRatingEditor(rating: item.rating) { model.setRating($0, for: [item.url]) }
            }
            HStack {
                Text("ป้ายสี").foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                LabelPicker(label: item.label) { model.setLabel($0, for: [item.url]) }
            }
        }
        .font(.callout)
    }
}
