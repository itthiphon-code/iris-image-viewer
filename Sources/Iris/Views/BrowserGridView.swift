import SwiftUI
import AppKit

struct BrowserGridView: View {
    @Environment(BrowserModel.self) private var model

    private let spacing: CGFloat = 14
    private let padding: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            if model.searchCriteria != nil {
                SearchBanner()
            } else {
                PathBar()
            }
            Divider()
            ZStack {
                if model.items.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.openExternal(url)
                return true
            }
            Divider()
            StatusBar()
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isSearching {
            ProgressView("กำลังค้นหา… ตรวจแล้ว \(model.searchScanned) ไฟล์")
        } else if model.searchCriteria != nil {
            ContentUnavailableView("ไม่พบรูปตามเงื่อนไข", systemImage: "magnifyingglass",
                                   description: Text("ลองเปลี่ยนเงื่อนไข หรือเปิด “รวมโฟลเดอร์ย่อย”"))
        } else if model.isLoading {
            ProgressView("กำลังอ่านโฟลเดอร์…")
        } else if !model.filterText.isEmpty {
            ContentUnavailableView.search(text: model.filterText)
        } else {
            ContentUnavailableView(
                "ไม่มีรูปภาพในโฟลเดอร์นี้",
                systemImage: "photo.on.rectangle.angled",
                description: Text("เลือกโฟลเดอร์จากแถบด้านซ้าย หรือลากโฟลเดอร์มาวางที่นี่")
            )
        }
    }

    private var grid: some View {
        let size = CGFloat(model.thumbSize)
        let columns = [GridItem(.adaptive(minimum: size, maximum: size), spacing: spacing, alignment: .top)]

        return GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .center, spacing: spacing) {
                        ForEach(model.items) { item in
                            ThumbnailCell(
                                item: item,
                                size: size,
                                isSelected: model.selection.contains(item.id),
                                isCursor: model.cursor == item.id
                            )
                            .id(item.id)
                            .onTapGesture {
                                let flags = NSEvent.modifierFlags
                                if NSApp.currentEvent?.clickCount == 2 {
                                    model.open(item)
                                } else {
                                    model.click(item, command: flags.contains(.command), shift: flags.contains(.shift))
                                }
                            }
                            .onDrag {
                                NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
                            }
                            .contextMenu { itemMenu(for: item) }
                        }
                    }
                    .padding(padding)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        _ = NSApp.keyWindow?.makeFirstResponder(nil)
                        model.clearSelection()
                    }
                }
                .onChange(of: model.cursor) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(newValue) }
                }
                .onAppear {
                    if let cursor = model.cursor {
                        DispatchQueue.main.async { proxy.scrollTo(cursor, anchor: .center) }
                    }
                }
            }
            .onChange(of: geo.size.width, initial: true) { _, width in
                updateColumns(width: width, size: size)
            }
            .onChange(of: model.thumbSize) { _, newSize in
                updateColumns(width: geo.size.width, size: CGFloat(newSize))
            }
        }
    }

    private func updateColumns(width: CGFloat, size: CGFloat) {
        let usable = width - padding * 2 + spacing
        model.gridColumns = max(1, Int(usable / (size + spacing)))
    }

    @ViewBuilder
    private func itemMenu(for item: ImageItem) -> some View {
        let targets = model.selection.contains(item.id) ? model.selectedItems.map(\.url) : [item.url]

        Button("เปิดดู") { model.open(item) }
        Button("เปิดด้วยแอปเริ่มต้น") { NSWorkspace.shared.open(item.url) }
        Divider()
        Button(AppSettings.shared.editorName.map { "แก้ไขใน \($0)" } ?? "แก้ไขในแอปอื่น…") {
            if !model.selection.contains(item.id) { model.click(item, command: false, shift: false) }
            model.openInEditor()
        }
        TransferMenuItems()
        Divider()
        Button("แสดงใน Finder") { NSWorkspace.shared.activateFileViewerSelecting(targets) }
        Button("คัดลอกพาธไฟล์") { model.copyPaths(targets) }
        Divider()
        Button(targets.count > 1 ? "ย้าย \(targets.count) รูปไปถังขยะ" : "ย้ายไปถังขยะ", role: .destructive) {
            model.trash(targets)
        }
    }
}

// MARK: - แถบพาธ (breadcrumb)

struct PathBar: View {
    @Environment(BrowserModel.self) private var model

    private var crumbs: [URL] {
        guard var url = model.currentFolder?.standardizedFileURL else { return [] }
        var list: [URL] = []
        while true {
            list.insert(url, at: 0)
            if url.path == "/" || list.count > 40 { break }
            url = url.deletingLastPathComponent()
        }
        return list
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    let list = crumbs
                    ForEach(Array(list.enumerated()), id: \.offset) { index, url in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right")
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            model.open(folder: url)
                        } label: {
                            HStack(spacing: 4) {
                                if index == 0 { Image(systemName: "internaldrive") }
                                Text(FileManager.default.displayName(atPath: url.path))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(index == list.count - 1 ? .primary : .secondary)
                        .fontWeight(index == list.count - 1 ? .semibold : .regular)
                        .id(index)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 12)
            }
            .onChange(of: model.currentFolder) { _, _ in
                proxy.scrollTo(crumbs.count - 1, anchor: .trailing)
            }
        }
        .frame(height: 30)
        .background(.bar)
    }
}

// MARK: - แถบสถานะด้านล่าง

struct StatusBar: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 10) {
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            Text(model.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "photo")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Slider(value: $model.thumbSize, in: 80...360)
                .controlSize(.small)
                .frame(width: 150)
                .help("ขนาดภาพย่อ (⌘+ / ⌘−)")
            Image(systemName: "photo")
                .imageScale(.large)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
    }
}

// MARK: - แถบผลการค้นหา

struct SearchBanner: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass").foregroundStyle(Color.accentColor)
            Text("ค้นหาใน \(model.searchRootName): \(model.searchCriteria?.summary ?? "")")
                .lineLimit(1)
                .truncationMode(.tail)
            if model.isSearching {
                ProgressView().controlSize(.small)
                Text("\(model.searchScanned) ไฟล์").foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if model.isSearching {
                Button("หยุด") { model.stopSearch() }
                    .controlSize(.small)
            }
            Button("แก้เงื่อนไข") { model.presentSearch() }
                .controlSize(.small)
            Button("ปิดผลการค้นหา") { model.exitSearch() }
                .controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color.accentColor.opacity(0.08))
    }
}
