import SwiftUI
import AppKit

/// หน้าต่างแปลงฟอร์แมต/ย่อขนาดภาพหลายไฟล์
struct ExportSheet: View {
    let items: [ImageItem]

    @Environment(\.dismiss) private var dismiss

    @State private var options = ExportOptions()
    @State private var resizePreset = 2560
    @State private var customEdge = 2000
    @State private var destination: URL?
    @State private var isExporting = false
    @State private var done = 0
    @State private var outputs: [URL] = []
    @State private var failures: [String] = []
    @State private var finished = false
    @State private var exportTask: Task<Void, Never>?

    /// 0 = ขนาดเดิม, -1 = กำหนดเอง
    private let presets: [(value: Int, title: String)] = [
        (0, "ขนาดเดิม"), (1280, "1280 px"), (1920, "1920 px (Full HD)"),
        (2560, "2560 px"), (3840, "3840 px (4K)"), (-1, "กำหนดเอง…")
    ]

    private var defaultDestination: URL? {
        items.first?.url.deletingLastPathComponent().appendingPathComponent("Export", isDirectory: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("แปลง/ย่อขนาดภาพ").font(.title3.weight(.semibold))
                    Text("\(items.count) ไฟล์ • ไฟล์ต้นฉบับไม่ถูกแก้ไข").foregroundStyle(.secondary)
                }
            }

            Form {
                Section("รูปแบบไฟล์") {
                    Picker("ฟอร์แมต", selection: $options.format) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if options.format.isLossy {
                        HStack {
                            Text("คุณภาพ")
                            Slider(value: $options.quality, in: 0.4...1.0, step: 0.05)
                            Text("\(Int((options.quality * 100).rounded()))%")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }

                Section("ขนาด") {
                    Picker("ด้านยาวสุด", selection: $resizePreset) {
                        ForEach(presets.indices, id: \.self) { i in
                            Text(presets[i].title).tag(presets[i].value)
                        }
                    }
                    if resizePreset == -1 {
                        HStack {
                            Text("กำหนดเอง")
                            TextField("", value: $customEdge, format: .number)
                                .frame(width: 90)
                            Text("px").foregroundStyle(.secondary)
                        }
                    }
                    Text("ภาพที่เล็กกว่าขนาดที่เลือกจะไม่ถูกขยาย")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("ข้อมูลภาพ") {
                    Toggle("เก็บข้อมูล EXIF (กล้อง เลนส์ วันที่ถ่าย)", isOn: $options.keepMetadata)
                    Toggle("ลบพิกัด GPS (แนะนำเมื่อจะโพสต์ออนไลน์)", isOn: $options.removeGPS)
                        .disabled(!options.keepMetadata)
                }

                Section("ปลายทาง") {
                    HStack {
                        Image(systemName: "folder")
                        Text((destination ?? defaultDestination)?.path ?? "-")
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("เลือก…") { chooseDestination() }
                    }
                    TextField("ต่อท้ายชื่อไฟล์ (ไม่บังคับ)", text: $options.suffix, prompt: Text("เช่น _web"))
                }
            }
            .formStyle(.grouped)
            .disabled(isExporting || finished)

            if isExporting || finished {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(done), total: Double(max(items.count, 1)))
                    Text(finished
                         ? "เสร็จแล้ว \(outputs.count) ไฟล์" + (failures.isEmpty ? "" : " • ไม่สำเร็จ \(failures.count) ไฟล์")
                         : "กำลังแปลง \(done) / \(items.count)…")
                        .font(.callout)
                        .foregroundStyle(failures.isEmpty ? Color.secondary : Color.orange)
                    if finished && !failures.isEmpty {
                        Text(failures.prefix(4).joined(separator: "\n"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                if finished, let first = outputs.first {
                    Button("แสดงใน Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(outputs.isEmpty ? [first] : outputs)
                    }
                }
                Spacer()
                if finished {
                    Button("ปิด") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("ยกเลิก", role: .cancel) {
                        exportTask?.cancel()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("แปลง \(items.count) ไฟล์") { start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isExporting)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "เลือก"
        panel.message = "เลือกโฟลเดอร์ปลายทาง"
        if panel.runModal() == .OK { destination = panel.url }
    }

    private func start() {
        guard let folder = destination ?? defaultDestination else { return }
        var opts = options
        switch resizePreset {
        case 0: opts.maxLongEdge = nil
        case -1: opts.maxLongEdge = max(64, customEdge)
        default: opts.maxLongEdge = resizePreset
        }
        let urls = items.map(\.url)
        let finalOptions = opts

        isExporting = true
        done = 0
        outputs = []
        failures = []

        exportTask = Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                failures = ["สร้างโฟลเดอร์ปลายทางไม่ได้: \(error.localizedDescription)"]
                isExporting = false
                finished = true
                return
            }
            for url in urls {
                if Task.isCancelled { break }
                let result: Result<URL, Error> = await Task.detached(priority: .userInitiated) {
                    Result { try ImageExporter.export(url, to: folder, options: finalOptions) }
                }.value
                switch result {
                case .success(let out): outputs.append(out)
                case .failure(let error): failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
                done += 1
            }
            isExporting = false
            finished = true
        }
    }
}
