import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// หน้าต่างสร้าง contact sheet (PDF รวมภาพย่อ) สำหรับพิมพ์หรือส่งให้ลูกค้าเลือกภาพ
struct ContactSheetSheet: View {
    let items: [ImageItem]

    @Environment(BrowserModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var options = ContactSheetOptions()
    @State private var openWhenDone = true
    @State private var working = false
    @State private var done = 0
    @State private var errorText: String?
    @State private var flag = CancelFlag()

    private var perPage: Int {
        let page = options.pageSize
        let cols = CGFloat(options.columns)
        let cellWidth = (page.width - 64 - 10 * (cols - 1)) / cols
        let lines = (options.showFilename ? 1 : 0) + (options.showExposure ? 1 : 0)
        let cellHeight = cellWidth * 0.75 + (lines == 0 ? 0 : CGFloat(lines) * 10 + 4)
        let rows = max(1, Int((page.height - 64 - 56 + 10) / (cellHeight + 10)))
        return rows * options.columns
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "doc.richtext")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("สร้าง Contact Sheet (PDF)").font(.title3.weight(.semibold))
                    Text("\(items.count) ภาพ • \(perPage) ภาพต่อหน้า • \(Int(ceil(Double(items.count) / Double(max(perPage, 1))))) หน้า")
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                TextField("หัวเรื่อง", text: $options.title)
                Picker("ขนาดกระดาษ", selection: $options.paper) {
                    ForEach(ContactSheetOptions.Paper.allCases) { Text($0.title).tag($0) }
                }
                Picker("แนวกระดาษ", selection: $options.landscape) {
                    Text("แนวตั้ง").tag(false)
                    Text("แนวนอน").tag(true)
                }
                .pickerStyle(.segmented)
                Stepper("จำนวนคอลัมน์: \(options.columns)", value: $options.columns, in: 2...8)
                Toggle("แสดงชื่อไฟล์", isOn: $options.showFilename)
                Toggle("แสดงค่าการถ่าย (ทางยาวโฟกัส รูรับแสง ชัตเตอร์ ISO)", isOn: $options.showExposure)
                Toggle("พื้นหลังสีเข้ม", isOn: $options.darkBackground)
                Toggle("เปิดไฟล์ PDF เมื่อเสร็จ", isOn: $openWhenDone)
            }
            .formStyle(.grouped)
            .frame(height: 330)
            .disabled(working)

            if working {
                ProgressView(value: Double(done), total: Double(max(items.count, 1))) {
                    Text("กำลังสร้าง \(done) / \(items.count)…").font(.callout)
                }
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.callout)
            }

            HStack {
                Spacer()
                Button("ยกเลิก", role: .cancel) {
                    flag.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("บันทึก PDF…") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || items.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            if options.title.isEmpty { options.title = model.folderTitle }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(options.title.isEmpty ? "Contact Sheet" : options.title) - Contact Sheet.pdf"
        panel.directoryURL = items.first?.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let output = panel.url else { return }

        let entries = items.map { ContactSheetMaker.Entry(url: $0.url, name: $0.name) }
        let opts = options
        let open = openWhenDone
        let cancel = CancelFlag()
        flag = cancel
        working = true
        done = 0
        errorText = nil

        Task { @MainActor in
            let failure: String? = await Task.detached(priority: .userInitiated) {
                do {
                    try ContactSheetMaker.make(entries: entries, options: opts, to: output, flag: cancel) { count in
                        Task { @MainActor in done = count }
                    }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            working = false
            if let failure {
                errorText = failure
                return
            }
            if cancel.isCancelled { return }
            if open { NSWorkspace.shared.open(output) }
            dismiss()
        }
    }
}
