import SwiftUI

/// หน้าต่างเปลี่ยนชื่อหลายไฟล์ พร้อมตัวอย่างชื่อใหม่ก่อนกดยืนยัน
struct BatchRenameSheet: View {
    let items: [ImageItem]

    @Environment(BrowserModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var template = RenameTemplate()
    @State private var dates: [URL: Date] = [:]
    @State private var loadingDates = true
    @State private var isApplying = false
    @State private var errorText: String?

    private var plan: [RenamePlanEntry] {
        BatchRenamer.plan(items: items, template: template, dates: dates)
    }

    var body: some View {
        let entries = plan
        let conflicts = entries.filter { $0.conflict != nil }.count
        let changes = entries.filter { $0.conflict == nil && !$0.isUnchanged }.count

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "character.cursor.ibeam")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("เปลี่ยนชื่อหลายไฟล์").font(.title3.weight(.semibold))
                    Text(entries.count == items.count ? "\(items.count) ไฟล์" : "\(items.count) รายการ (รวมไฟล์คู่ RAW เป็น \(entries.count) ไฟล์)").foregroundStyle(.secondary)
                }
            }

            Form {
                TextField("รูปแบบชื่อ", text: $template.pattern)
                    .font(.system(.body, design: .monospaced))
                HStack(spacing: 6) {
                    Text("แทรก:").foregroundStyle(.secondary)
                    ForEach(RenameTemplate.tokens.indices, id: \.self) { i in
                        let token = RenameTemplate.tokens[i]
                        Button(token.token) { template.pattern += token.token }
                            .controlSize(.small)
                            .help(token.meaning)
                    }
                }
                Stepper(value: $template.startNumber, in: 0...99_999) {
                    HStack {
                        Text("เริ่มนับที่")
                        TextField("", value: $template.startNumber, format: .number)
                            .frame(width: 70)
                    }
                }
                Picker("จำนวนหลักของเลข", selection: $template.digits) {
                    ForEach(1...6, id: \.self) { d in
                        Text(String(repeating: "0", count: d - 1) + "1").tag(d)
                    }
                }
                Picker("นามสกุลไฟล์", selection: $template.extensionCase) {
                    ForEach(RenameTemplate.ExtensionCase.allCases) { Text($0.title).tag($0) }
                }
            }
            .formStyle(.grouped)
            .frame(height: 230)

            HStack {
                Text("ตัวอย่าง").font(.headline)
                if loadingDates {
                    ProgressView().controlSize(.small)
                    Text("กำลังอ่านวันที่ถ่าย…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if conflicts > 0 {
                    Label("\(conflicts) ไฟล์ชื่อชนกัน (จะข้ามไป)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }

            Table(entries) {
                TableColumn("ชื่อเดิม") { entry in
                    Text(entry.source.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TableColumn("ชื่อใหม่") { entry in
                    HStack(spacing: 4) {
                        if let conflict = entry.conflict {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help(conflict)
                        }
                        Text(entry.newName)
                            .foregroundStyle(entry.conflict == nil ? Color.primary : Color.orange)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .frame(minHeight: 200)

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.callout)
            }

            HStack {
                Spacer()
                Button("ยกเลิก", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(changes > 0 ? "เปลี่ยนชื่อ \(changes) ไฟล์" : "เปลี่ยนชื่อ") {
                    apply(entries)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(changes == 0 || isApplying || loadingDates)
            }
        }
        .padding(20)
        .frame(width: 640, height: 640)
        .task { await loadDates() }
    }

    @MainActor
    private func loadDates() async {
        let urls = items.map(\.url)
        let result = await Task.detached(priority: .userInitiated) {
            var map: [URL: Date] = [:]
            for url in urls {
                if let date = MetadataReader.read(url).dateTaken { map[url] = date }
            }
            return map
        }.value
        dates = result
        loadingDates = false
    }

    private func apply(_ entries: [RenamePlanEntry]) {
        isApplying = true
        do {
            let renamed = try BatchRenamer.apply(entries)
            model.finishRename(renamed: renamed)
            dismiss()
        } catch {
            errorText = "เปลี่ยนชื่อไม่สำเร็จ: \(error.localizedDescription)"
            isApplying = false
        }
    }
}
