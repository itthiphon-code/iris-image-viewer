import SwiftUI
import AppKit

/// นำเข้ารูปจากการ์ดกล้อง/โฟลเดอร์ แยกโฟลเดอร์ตามวันที่ถ่าย
struct ImportSheet: View {
    @Environment(BrowserModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var source: URL?
    @State private var removableVolumes: [URL] = []
    @State private var days: [ImportDay] = []
    @State private var scanning = false
    @State private var scannedCount = 0
    @State private var event = ""
    @State private var includeVideos = false
    @State private var skipDuplicates = true
    @State private var ejectAfter = false
    @State private var importing = false
    @State private var copiedCount = 0
    @State private var skippedCount = 0
    @State private var processed = 0
    @State private var failures: [String] = []
    @State private var finished = false
    @State private var firstFolder: URL?
    @State private var scanFlag = CancelFlag()
    @State private var importTask: Task<Void, Never>?

    private var selectedFiles: [ImportCandidate] {
        days.filter(\.include).flatMap(\.files)
    }

    private var destinationRoot: URL {
        URL(fileURLWithPath: settings.importDestination, isDirectory: true)
    }

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sdcard")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("นำเข้ารูปภาพ").font(.title3.weight(.semibold))
                    Text("คัดลอกจากการ์ดกล้องหรือโฟลเดอร์ แยกโฟลเดอร์ตามวันที่ถ่าย").foregroundStyle(.secondary)
                }
            }

            Form {
                Section("ต้นทาง") {
                    HStack {
                        Menu {
                            ForEach(removableVolumes, id: \.self) { volume in
                                Button {
                                    pick(volume)
                                } label: {
                                    Label(FileManager.default.displayName(atPath: volume.path), systemImage: "sdcard")
                                }
                            }
                            if !removableVolumes.isEmpty { Divider() }
                            Button("เลือกโฟลเดอร์…") { chooseSource() }
                        } label: {
                            Label(source.map { FileManager.default.displayName(atPath: $0.path) } ?? "เลือกการ์ดหรือโฟลเดอร์",
                                  systemImage: "sdcard")
                        }
                        .fixedSize()
                        Spacer()
                        if scanning {
                            ProgressView().controlSize(.small)
                            Text("พบ \(scannedCount) ไฟล์…").foregroundStyle(.secondary)
                        }
                    }
                    Toggle("รวมไฟล์วิดีโอด้วย", isOn: $includeVideos)
                        .onChange(of: includeVideos) { _, _ in if let source { pick(source) } }
                }

                Section("ปลายทาง") {
                    HStack {
                        Image(systemName: "folder")
                        Text(settings.importDestination)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("เปลี่ยน…") { chooseDestination() }
                    }
                    Picker("แยกโฟลเดอร์", selection: $settings.importPattern) {
                        ForEach(ImportPattern.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("ชื่อกิจกรรม (ไม่บังคับ)", text: $event, prompt: Text("เช่น งานรับปริญญา"))
                    Toggle("ข้ามไฟล์ที่เคยนำเข้าแล้ว (ชื่อและขนาดเท่ากัน)", isOn: $skipDuplicates)
                    if let source, removableVolumes.contains(source) {
                        Toggle("ดีดการ์ดออกเมื่อเสร็จ", isOn: $ejectAfter)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 330)
            .disabled(importing)

            if !days.isEmpty {
                List {
                    ForEach($days) { $day in
                        Toggle(isOn: $day.include) {
                            HStack {
                                Text(day.day.formatted(date: .complete, time: .omitted))
                                Spacer()
                                Text("\(day.files.count) ไฟล์ • \(Format.bytes(day.totalSize))")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .help(Importer.folder(for: day.day, root: destinationRoot,
                                              pattern: settings.importPattern, event: event).path)
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
                .disabled(importing)
            }

            if importing || finished {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(processed), total: Double(max(selectedFiles.count, 1)))
                    Text(finished
                         ? "เสร็จแล้ว: คัดลอก \(copiedCount) ไฟล์, ข้าม \(skippedCount) ไฟล์ที่มีอยู่แล้ว"
                            + (failures.isEmpty ? "" : ", ไม่สำเร็จ \(failures.count) ไฟล์")
                         : "กำลังคัดลอก \(processed) / \(selectedFiles.count)…")
                        .font(.callout)
                        .foregroundStyle(failures.isEmpty ? Color.secondary : Color.orange)
                }
            }

            HStack {
                if !days.isEmpty && !finished {
                    Text("เลือก \(selectedFiles.count) ไฟล์ (\(Format.bytes(selectedFiles.reduce(0) { $0 + $1.size })))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if finished {
                    if let firstFolder {
                        Button("เปิดโฟลเดอร์ที่นำเข้า") {
                            model.open(folder: firstFolder)
                            dismiss()
                        }
                    }
                    Button("ปิด") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("ยกเลิก", role: .cancel) {
                        scanFlag.cancel()
                        importTask?.cancel()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("นำเข้า \(selectedFiles.count) ไฟล์") { startImport() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedFiles.isEmpty || scanning || importing)
                }
            }
        }
        .padding(20)
        .frame(width: 600)
        .onAppear {
            removableVolumes = Self.findRemovableVolumes()
            if source == nil, let card = removableVolumes.first(where: Self.hasDCIM) ?? removableVolumes.first {
                pick(card)
            }
        }
    }

    // MARK: - ต้นทาง

    private static func findRemovableVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsEjectableKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                            options: [.skipHiddenVolumes]) ?? []
        return volumes.filter { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            return v?.volumeIsRemovable == true || v?.volumeIsEjectable == true
        }
    }

    private static func hasDCIM(_ volume: URL) -> Bool {
        FileManager.default.fileExists(atPath: volume.appendingPathComponent("DCIM").path)
    }

    private func chooseSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "เลือก"
        panel.message = "เลือกการ์ดกล้องหรือโฟลเดอร์ที่มีรูป"
        if panel.runModal() == .OK, let url = panel.url { pick(url) }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destinationRoot
        panel.prompt = "เลือก"
        panel.message = "เลือกโฟลเดอร์หลักสำหรับเก็บรูปที่นำเข้า"
        if panel.runModal() == .OK, let url = panel.url { settings.importDestination = url.path }
    }

    private func pick(_ url: URL) {
        scanFlag.cancel()
        source = url
        days = []
        scannedCount = 0
        scanning = true
        finished = false

        let flag = CancelFlag()
        scanFlag = flag
        // ถ้าเป็นการ์ดกล้อง สแกนเฉพาะโฟลเดอร์ DCIM
        let root = Self.hasDCIM(url) ? url.appendingPathComponent("DCIM") : url
        let videos = includeVideos

        Task { @MainActor in
            let found = await Task.detached(priority: .userInitiated) {
                Importer.scan(source: root, includeVideos: videos, flag: flag) { count in
                    Task { @MainActor in scannedCount = count }
                }
            }.value
            guard !flag.isCancelled else { return }
            days = Importer.group(found)
            scanning = false
        }
    }

    // MARK: - นำเข้า

    private func startImport() {
        let plan: [(ImportCandidate, URL)] = days.filter(\.include).flatMap { day in
            let folder = Importer.folder(for: day.day, root: destinationRoot,
                                         pattern: settings.importPattern, event: event)
            return day.files.map { ($0, folder) }
        }
        guard !plan.isEmpty else { return }
        firstFolder = plan.first?.1
        let skip = skipDuplicates
        let eject = ejectAfter ? source : nil

        importing = true
        processed = 0
        copiedCount = 0
        skippedCount = 0
        failures = []

        importTask = Task { @MainActor in
            for (file, folder) in plan {
                if Task.isCancelled { break }
                let result: Result<Importer.Outcome, Error> = await Task.detached(priority: .userInitiated) {
                    Result { try Importer.copy(file, to: folder, skipDuplicates: skip) }
                }.value
                switch result {
                case .success(.copied): copiedCount += 1
                case .success(.skipped): skippedCount += 1
                case .failure(let error): failures.append("\(file.url.lastPathComponent): \(error.localizedDescription)")
                }
                processed += 1
            }
            importing = false
            finished = true
            if let eject, failures.isEmpty {
                try? NSWorkspace.shared.unmountAndEjectDevice(at: eject)
            }
        }
    }
}
