import SwiftUI
import AppKit

/// โหมดเทียบภาพ 2–4 ภาพ ซูม/เลื่อนพร้อมกัน เหมาะกับการคัดภาพที่คมที่สุดจากชุดถ่ายต่อเนื่อง
struct CompareView: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        let items = model.compareItems
        let compare = model.compare

        Group {
            if items.count == 4 {
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    GridRow {
                        ComparePaneView(index: 0, item: items[0])
                        ComparePaneView(index: 1, item: items[1])
                    }
                    GridRow {
                        ComparePaneView(index: 2, item: items[2])
                        ComparePaneView(index: 3, item: items[3])
                    }
                }
            } else {
                HStack(spacing: 2) {
                    ForEach(items.indices, id: \.self) { i in
                        ComparePaneView(index: i, item: items[i])
                    }
                }
            }
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .navigationTitle("เทียบภาพ \(items.count) รูป")
        .navigationSubtitle(items.indices.contains(compare.activeIndex) ? items[compare.activeIndex].name : "")
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        let compare = model.compare

        ToolbarItem(placement: .navigation) {
            Button { model.exitCompare() } label: {
                Label("กลับไปหน้ารวมภาพ", systemImage: "square.grid.2x2")
            }
            .help("กลับไปหน้ารวมภาพ (Esc)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: Binding(get: { compare.isLinked }, set: { compare.isLinked = $0 })) {
                Label("ซูม/เลื่อนพร้อมกัน", systemImage: "link")
            }
            .toggleStyle(.button)
            .help("ซูมและเลื่อนทุกภาพพร้อมกัน")

            Button { compare.zoomOut() } label: {
                Label("ย่อ", systemImage: "minus.magnifyingglass")
            }
            .help("ย่อ (−)")

            Text("\(Int((compare.zoom * 100).rounded()))%")
                .monospacedDigit()
                .frame(minWidth: 44)

            Button { compare.zoomIn() } label: {
                Label("ขยาย", systemImage: "plus.magnifyingglass")
            }
            .help("ขยาย (+)")

            Button { compare.fitAll() } label: {
                Label("พอดีหน้าต่าง", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("พอดีหน้าต่างทุกภาพ")

            Button { compare.actualSize() } label: {
                Label("100%", systemImage: "1.magnifyingglass")
            }
            .help("ขนาดจริง 100% — กด Z หรือดับเบิลคลิกตรงจุดที่อยากดู")

            Button { model.trashSelectionOrCurrent() } label: {
                Label("ย้ายภาพที่เลือกไปถังขยะ", systemImage: "trash")
            }
            .help("ย้ายภาพที่เลือก (กรอบสีฟ้า) ไปถังขยะ (⌘⌫)")
        }
    }
}

struct ComparePaneView: View {
    let index: Int
    let item: ImageItem
    @Environment(BrowserModel.self) private var model

    var body: some View {
        let isActive = model.compare.activeIndex == index

        ZStack(alignment: .bottomLeading) {
            CompareImageView(controller: model.compare, index: index, url: item.url)

            HStack(spacing: 6) {
                if item.label != .none { LabelDot(label: item.label, size: 9) }
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.rating > 0 {
                    HStack(spacing: 1) {
                        ForEach(0..<item.rating, id: \.self) { _ in Image(systemName: "star.fill") }
                    }
                    .foregroundStyle(Color.yellow)
                    .font(.system(size: 9))
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppSettings.shared.viewerBackground.color)
        .overlay {
            Rectangle()
                .strokeBorder(isActive ? Color.accentColor : Color.clear, lineWidth: 3)
                .allowsHitTesting(false)
        }
        .clipped()
    }
}

struct CompareImageView: NSViewRepresentable {
    let controller: CompareController
    let index: Int
    let url: URL

    func makeNSView(context: Context) -> ViewerScrollView {
        let (scrollView, imageView) = ViewerScrollView.makeImageScrollView()
        controller.attach(index: index, scrollView: scrollView, imageView: imageView)
        controller.load(index: index, url: url)
        return scrollView
    }

    func updateNSView(_ nsView: ViewerScrollView, context: Context) {
        controller.load(index: index, url: url)
    }
}
