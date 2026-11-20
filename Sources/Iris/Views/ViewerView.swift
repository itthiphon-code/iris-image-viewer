import SwiftUI
import AppKit

/// โหมดดูภาพเต็ม (เหมือน View mode ของ ACDSee)
struct ViewerView: View {
    @Environment(BrowserModel.self) private var model
    @State private var hoverLeft = false
    @State private var hoverRight = false

    var body: some View {
        let viewer = model.viewer

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack {
                    ZoomableImageView(controller: viewer)

                    edgeButtons

                    VStack {
                        HStack {
                            if viewer.isLoadingFull {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini)
                                    Text("กำลังโหลดภาพเต็ม…")
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                                .transition(.opacity)
                            }
                            Spacer()
                            if model.isSlideshow {
                                Label("สไลด์โชว์", systemImage: "play.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                        Spacer()
                        if let item = model.currentViewerItem, item.rating > 0 || item.label != .none {
                            HStack(spacing: 8) {
                                if item.label != .none { LabelDot(label: item.label, size: 11) }
                                if item.rating > 0 {
                                    HStack(spacing: 2) {
                                        ForEach(0..<item.rating, id: \.self) { _ in
                                            Image(systemName: "star.fill")
                                        }
                                    }
                                    .foregroundStyle(Color.yellow)
                                }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.2), value: viewer.isLoadingFull)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.showViewerInfo {
                    Divider()
                    InspectorView(item: model.currentViewerItem)
                        .frame(width: 300)
                        .background(.regularMaterial)
                        .transition(.move(edge: .trailing))
                }
            }

            if model.showFilmstrip {
                Divider()
                FilmstripView()
                    .frame(height: 92)
                    .transition(.move(edge: .bottom))
            }
        }
        .background(AppSettings.shared.viewerBackground.color)
        .animation(.easeInOut(duration: 0.2), value: model.showViewerInfo)
        .animation(.easeInOut(duration: 0.2), value: model.showFilmstrip)
        .environment(\.colorScheme, .dark)
        .navigationTitle(model.currentViewerItem?.name ?? "")
        .navigationSubtitle(subtitle)
        .toolbar { toolbarContent }
    }

    private var subtitle: String {
        var parts = [model.viewerPositionText]
        let px = model.viewer.pixelSize
        if px.width > 0 { parts.append("\(Int(px.width)) × \(Int(px.height))") }
        return parts.joined(separator: "  •  ")
    }

    private var zoomText: String {
        "\(Int((model.viewer.zoom * 100).rounded()))%"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        let viewer = model.viewer

        ToolbarItem(placement: .navigation) {
            Button { model.closeViewer() } label: {
                Label("กลับไปหน้ารวมภาพ", systemImage: "square.grid.2x2")
            }
            .help("กลับไปหน้ารวมภาพ (Esc)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.showPrevious() } label: {
                Label("ภาพก่อนหน้า", systemImage: "chevron.left")
            }
            .disabled(model.viewerIndex == 0)
            .help("ภาพก่อนหน้า (←)")

            Button { model.showNext() } label: {
                Label("ภาพถัดไป", systemImage: "chevron.right")
            }
            .disabled(model.viewerIndex >= model.items.count - 1)
            .help("ภาพถัดไป (→ / Space)")

            Button { viewer.zoomOut() } label: {
                Label("ย่อ", systemImage: "minus.magnifyingglass")
            }
            .help("ย่อ (−)")

            Menu {
                Button("พอดีหน้าต่าง   ⌘9") { viewer.fit() }
                Divider()
                Button("25%") { viewer.setZoom(0.25) }
                Button("50%") { viewer.setZoom(0.5) }
                Button("100% (ขนาดจริง)   ⌘0") { viewer.actualSize() }
                Button("200%") { viewer.setZoom(2) }
                Button("400%") { viewer.setZoom(4) }
            } label: {
                Text(zoomText).monospacedDigit().frame(minWidth: 44)
            }
            .help("อัตราซูม")

            Button { viewer.zoomIn() } label: {
                Label("ขยาย", systemImage: "plus.magnifyingglass")
            }
            .help("ขยาย (+)")

            Button { viewer.fit() } label: {
                Label("พอดีหน้าต่าง", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("พอดีหน้าต่าง (⌘9) — กด Z หรือดับเบิลคลิกที่ภาพเพื่อสลับกับ 100%")

            Button { model.rotate(.left) } label: {
                Label("หมุนซ้าย", systemImage: "rotate.left")
            }
            .help("หมุนซ้าย 90° แบบไม่เสียคุณภาพ (L)")

            Button { model.rotate(.right) } label: {
                Label("หมุนขวา", systemImage: "rotate.right")
            }
            .help("หมุนขวา 90° แบบไม่เสียคุณภาพ (R)")

            Button { model.toggleSlideshow() } label: {
                Label(model.isSlideshow ? "หยุดสไลด์โชว์" : "สไลด์โชว์",
                      systemImage: model.isSlideshow ? "pause.fill" : "play.fill")
            }
            .help("สไลด์โชว์ (S)")

            Button { model.showFilmstrip.toggle() } label: {
                Label("แถบภาพย่อ", systemImage: "film")
            }
            .help("แสดง/ซ่อนแถบภาพย่อ (T)")

            Button { model.showViewerInfo.toggle() } label: {
                Label("ข้อมูลภาพ", systemImage: "info.circle")
            }
            .help("ข้อมูลภาพ (I)")

            Button { model.trashSelectionOrCurrent() } label: {
                Label("ย้ายไปถังขยะ", systemImage: "trash")
            }
            .help("ย้ายไปถังขยะ (⌘⌫)")

            Button { model.openInEditor() } label: {
                Label("แก้ไขในแอปอื่น", systemImage: "slider.horizontal.3")
            }
            .help(AppSettings.shared.editorName.map { "แก้ไขใน \($0) (E)" } ?? "แก้ไขในแอปอื่น (E)")
        }
    }

    private var edgeButtons: some View {
        HStack(spacing: 0) {
            edgeButton(systemImage: "chevron.left", hovering: $hoverLeft, enabled: model.viewerIndex > 0) {
                model.showPrevious()
            }
            Spacer(minLength: 0)
            edgeButton(systemImage: "chevron.right", hovering: $hoverRight,
                       enabled: model.viewerIndex < model.items.count - 1) {
                model.showNext()
            }
        }
    }

    private func edgeButton(systemImage: String, hovering: Binding<Bool>, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.black.opacity(0.5), in: Circle())
                .opacity(hovering.wrappedValue && enabled ? 1 : 0)
                .frame(width: 84)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering.wrappedValue = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering.wrappedValue)
    }
}

// MARK: - แถบภาพย่อด้านล่าง

struct FilmstripView: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(model.items.indices, id: \.self) { index in
                        FilmstripThumb(item: model.items[index], isCurrent: index == model.viewerIndex)
                            .id(index)
                            .onTapGesture { model.show(index: index) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: model.viewerIndex, initial: true) { _, newValue in
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
        .background(Color.black.opacity(0.55))
    }
}

struct FilmstripThumb: View {
    let item: ImageItem
    let isCurrent: Bool
    @State private var image: NSImage?

    init(item: ImageItem, isCurrent: Bool) {
        self.item = item
        self.isCurrent = isCurrent
        _image = State(initialValue: ThumbnailLoader.shared.bestCached(item.url))
    }

    var body: some View {
        ZStack {
            Color.white.opacity(0.06)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 92, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(isCurrent ? Color.accentColor : Color.white.opacity(0.08), lineWidth: isCurrent ? 2.5 : 1)
        }
        .opacity(isCurrent ? 1 : 0.72)
        .contentShape(Rectangle())
        .task(id: "\(item.url.path)#\(item.modified.timeIntervalSince1970)") {
            if let loaded = await ThumbnailLoader.shared.thumbnail(for: item.url, bucket: 256) {
                image = loaded
            }
        }
    }
}

// MARK: - NSScrollView สำหรับซูม/แพนภาพ

struct ZoomableImageView: NSViewRepresentable {
    let controller: ViewerController

    func makeNSView(context: Context) -> ViewerScrollView {
        let (scrollView, imageView) = ViewerScrollView.makeImageScrollView()
        controller.attach(scrollView: scrollView, imageView: imageView)
        return scrollView
    }

    func updateNSView(_ nsView: ViewerScrollView, context: Context) {}
}
