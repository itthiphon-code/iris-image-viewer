import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        ZStack {
            if model.isComparing {
                CompareView()
                    .transition(.opacity)
            } else if model.isViewing {
                ViewerView()
                    .transition(.opacity)
            } else {
                BrowserView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: model.isViewing)
        .animation(.easeInOut(duration: 0.16), value: model.isComparing)
        .onAppear { model.start() }
        .sheet(item: Binding(get: { model.activeSheet }, set: { model.activeSheet = $0 })) { kind in
            Group {
                switch kind {
                case .rename: BatchRenameSheet(items: model.sheetTargets)
                case .export: ExportSheet(items: model.sheetTargets)
                case .search: SearchSheet()
                case .importer: ImportSheet()
                case .contactSheet: ContactSheetSheet(items: model.sheetTargets)
                }
            }
            .environment(model)
            .environment(AppSettings.shared)
        }
        .alert(
            "แจ้งเตือน",
            isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
        ) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}

struct BrowserView: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 240, max: 380)
        } detail: {
            BrowserGridView()
                .inspector(isPresented: $model.showInspector) {
                    InspectorView(item: model.focusedItem)
                        .inspectorColumnWidth(min: 250, ideal: 300, max: 440)
                }
        }
        .navigationTitle(model.folderTitle)
        .navigationSubtitle(model.statusText)
        .searchable(text: $model.filterText, placement: .toolbar, prompt: "ค้นหาชื่อไฟล์")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.goBack() } label: {
                    Label("ย้อนกลับ", systemImage: "chevron.left")
                }
                .disabled(!model.canGoBack)
                .help("ย้อนกลับ (⌘[)")

                Button { model.goForward() } label: {
                    Label("ไปข้างหน้า", systemImage: "chevron.right")
                }
                .disabled(!model.canGoForward)
                .help("ไปข้างหน้า (⌘])")

                Button { model.goUp() } label: {
                    Label("โฟลเดอร์ระดับบน", systemImage: "arrow.up")
                }
                .disabled(!model.canGoUp)
                .help("โฟลเดอร์ระดับบน (⌘↑)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("คะแนนดาว", selection: $model.minRating) {
                        Text("ทุกรูป").tag(0)
                        ForEach(1...5, id: \.self) { n in
                            Text(String(repeating: "★", count: n) + (n < 5 ? " ขึ้นไป" : "")).tag(n)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Picker("ป้ายสี", selection: $model.labelFilter) {
                        Text("ทุกป้าย").tag(LabelFilter.any)
                        Text("ไม่มีป้าย").tag(LabelFilter.unlabeled)
                        ForEach(ColorLabel.allCases.filter { $0 != .none }) { label in
                            Text(label.title).tag(LabelFilter.label(label))
                        }
                    }
                    .pickerStyle(.inline)
                    if model.isFiltering {
                        Divider()
                        Button("ล้างตัวกรอง") {
                            model.minRating = 0
                            model.labelFilter = .any
                        }
                    }
                } label: {
                    Label("กรอง", systemImage: model.isFiltering
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .help("กรองตามคะแนนดาวและป้ายสี")

                Button { model.startCompare() } label: {
                    Label("เทียบภาพ", systemImage: "rectangle.split.2x1")
                }
                .disabled(!(2...4).contains(model.selection.count))
                .help("เทียบภาพ 2–4 รูปที่เลือก (C)")

                Menu {
                    Button("หมุนซ้าย 90°   (L)") { model.rotate(.left) }
                    Button("หมุนขวา 90°   (R)") { model.rotate(.right) }
                    Divider()
                    TransferMenuItems()
                    Divider()
                    Button(AppSettings.shared.editorName.map { "แก้ไขใน \($0)   (E)" } ?? "แก้ไขในแอปอื่น…   (E)") {
                        model.openInEditor()
                    }
                    Divider()
                    Button("เปลี่ยนชื่อหลายไฟล์…   (F2)") { model.presentRename() }
                    Button("แปลง/ย่อขนาดภาพ…   (⇧⌘E)") { model.presentExport() }
                    Button("สร้าง Contact Sheet (PDF)…   (⌘P)") { model.presentContactSheet() }
                } label: {
                    Label("เครื่องมือ", systemImage: "wand.and.stars")
                }
                .disabled(model.items.isEmpty)
                .help("หมุน เปลี่ยนชื่อ แปลงไฟล์")

                Button { model.presentSearch() } label: {
                    Label("ค้นหาขั้นสูง", systemImage: "text.magnifyingglass")
                }
                .help("ค้นหาตามกล้อง เลนส์ วันที่ ISO รวมโฟลเดอร์ย่อย (⌥⌘F)")

                Button { model.presentImport() } label: {
                    Label("นำเข้า", systemImage: "sdcard")
                }
                .help("นำเข้ารูปจากการ์ดกล้อง (⇧⌘I)")

                Menu {
                    Picker("เรียงตาม", selection: $model.sortKey) {
                        ForEach(SortKey.allCases) { key in
                            Text(key.title).tag(key)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("เรียงจากน้อยไปมาก", isOn: $model.sortAscending)
                } label: {
                    Label("เรียงลำดับ", systemImage: "arrow.up.arrow.down")
                }
                .help("เรียงลำดับ")

                Button { model.openViewerAtCursor() } label: {
                    Label("ดูภาพ", systemImage: "eye")
                }
                .disabled(model.items.isEmpty)
                .help("ดูภาพเต็ม (Return)")

                Button { model.startSlideshow() } label: {
                    Label("สไลด์โชว์", systemImage: "play.rectangle")
                }
                .disabled(model.items.isEmpty)
                .help("สไลด์โชว์ (⌥⌘P)")

                Button { model.showInspector.toggle() } label: {
                    Label("ข้อมูลภาพ", systemImage: "sidebar.right")
                }
                .help("แสดง/ซ่อนแผงข้อมูลภาพ (⌥⌘I)")
            }
        }
    }
}

/// เมนูคัดลอก/ย้ายไปโฟลเดอร์ (มีรายการโฟลเดอร์ที่ใช้ล่าสุด)
struct TransferMenuItems: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        let recents = AppSettings.shared.destinationURLs

        Menu("คัดลอกไปที่") {
            ForEach(recents, id: \.self) { url in
                Button(FileManager.default.displayName(atPath: url.path)) { model.transfer(move: false, to: url) }
            }
            if !recents.isEmpty { Divider() }
            Button("เลือกโฟลเดอร์…") { model.chooseDestination(move: false) }
        }
        Menu("ย้ายไปที่") {
            ForEach(recents, id: \.self) { url in
                Button(FileManager.default.displayName(atPath: url.path)) { model.transfer(move: true, to: url) }
            }
            if !recents.isEmpty { Divider() }
            Button("เลือกโฟลเดอร์…") { model.chooseDestination(move: true) }
        }
    }
}
