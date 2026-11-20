import SwiftUI
import AppKit

/// หน้าตั้งค่า (⌘,)
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("ทั่วไป", systemImage: "gearshape") }
            ViewerSettings()
                .tabItem { Label("การดูภาพ", systemImage: "photo") }
            ToolSettings()
                .tabItem { Label("เครื่องมือ", systemImage: "wand.and.stars") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("แสดงรูปใหม่อัตโนมัติเมื่อมีไฟล์เพิ่ม/ลบในโฟลเดอร์", isOn: $settings.autoRefresh)
                Toggle("รวมไฟล์ RAW กับ JPEG/HEIC ชื่อเดียวกันเป็นรายการเดียว", isOn: $settings.groupRawJpeg)
                Text("เมื่อรวมแล้ว ดาว ป้ายสี การย้าย คัดลอก ลบ และเปลี่ยนชื่อ จะทำกับทั้งสองไฟล์พร้อมกัน")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("ถามก่อนย้ายไปถังขยะ", isOn: $settings.confirmTrash)
            }
            Section("Lightroom / XMP") {
                Toggle("เขียนดาวและป้ายสีลง XMP sidecar ของไฟล์ RAW", isOn: $settings.writeXMPSidecar)
                Text("Iris อ่านดาว/ป้ายจาก XMP ที่ Lightroom หรือกล้องบันทึกไว้เสมอ ส่วนการเขียนจะสร้างไฟล์ .xmp ข้างไฟล์ RAW (ใน Lightroom ใช้คำสั่ง Metadata → Read Metadata from Files)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 390)
    }
}

private struct ViewerSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("สีพื้นหลัง", selection: $settings.viewerBackground) {
                    ForEach(ViewerBackground.allCases) { bg in
                        HStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(bg.color)
                                .frame(width: 16, height: 12)
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.secondary.opacity(0.4)))
                            Text(bg.title)
                        }
                        .tag(bg)
                    }
                }
                Toggle("ขยายภาพที่เล็กกว่าหน้าต่างให้เต็มจอ", isOn: $settings.enlargeSmallImages)
                Picker("ล้อเมาส์", selection: $settings.wheelAction) {
                    ForEach(WheelAction.allCases) { Text($0.title).tag($0) }
                }
                Text("trackpad ใช้สองนิ้วเลื่อน และจีบนิ้วเพื่อซูมได้เสมอ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("สไลด์โชว์") {
                HStack {
                    Slider(value: $settings.slideshowInterval, in: 1...15, step: 1)
                    Text("\(Int(settings.slideshowInterval)) วินาที")
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 330)
    }
}

private struct ToolSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section("แอปแก้ไขภาพ (กด E)") {
                HStack {
                    if let url = settings.editorURL {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(settings.editorName ?? url.lastPathComponent)
                    } else {
                        Text("ยังไม่ได้เลือก").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("เลือกแอป…") { BrowserModel.shared.chooseEditorApp() }
                    if settings.editorPath != nil {
                        Button("ล้าง") { settings.editorPath = nil }
                    }
                }
            }
            Section("โฟลเดอร์ปลายทางล่าสุด (คัดลอก/ย้าย)") {
                if settings.destinationURLs.isEmpty {
                    Text("ยังไม่มี — จะเพิ่มอัตโนมัติเมื่อคัดลอกหรือย้ายรูป")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.destinationURLs, id: \.self) { url in
                        HStack {
                            Image(systemName: "folder")
                            VStack(alignment: .leading) {
                                Text(FileManager.default.displayName(atPath: url.path))
                                Text(url.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            Spacer()
                            Button {
                                settings.recentDestinations.removeAll { $0 == url.path }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("เอาออก")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 360)
    }
}
