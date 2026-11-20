import SwiftUI
import AppKit

struct SidebarView: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.sidebarSelection) {
            if !model.favorites.isEmpty {
                Section("รายการโปรด") {
                    ForEach(model.favorites) { FolderTreeRow(node: $0) }
                }
            }
            Section("ตำแหน่ง") {
                ForEach(model.locations) { FolderTreeRow(node: $0) }
            }
            Section("ไดรฟ์") {
                ForEach(model.volumes) { FolderTreeRow(node: $0) }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.sidebarSelection) { _, newValue in
            if let newValue { model.open(folder: newValue) }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                model.chooseFolder()
            } label: {
                Label("เปิดโฟลเดอร์…", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

struct FolderTreeRow: View {
    @Bindable var node: FolderNode
    @Environment(BrowserModel.self) private var model

    var body: some View {
        if node.hasSubfolders {
            DisclosureGroup(isExpanded: $node.isExpanded) {
                if let children = node.children {
                    ForEach(children) { FolderTreeRow(node: $0) }
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }
            } label: {
                label
            }
        } else {
            label
        }
    }

    private var label: some View {
        Label {
            Text(node.name).lineLimit(1).truncationMode(.middle)
        } icon: {
            Image(systemName: node.icon)
        }
        .tag(node.url as URL?)
        .contextMenu {
            Button(model.isFavorite(node.url) ? "เอาออกจากรายการโปรด" : "เพิ่มในรายการโปรด") {
                model.toggleFavorite(node.url)
            }
            Button("แสดงใน Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
            Button("รีเฟรชโฟลเดอร์ย่อย") {
                node.reload()
            }
        }
    }
}
