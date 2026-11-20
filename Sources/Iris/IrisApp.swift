import SwiftUI
import AppKit

@main
struct IrisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Iris", id: "main") {
            ContentView()
                .environment(BrowserModel.shared)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1320, height: 840)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { IrisCommands(model: BrowserModel.shared) }

        Settings {
            SettingsView()
                .environment(AppSettings.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // จำเป็นเมื่อรันจาก Swift Package (ไม่มี .app bundle) ให้มีไอคอนใน Dock และรับคีย์บอร์ดได้
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// เปิดไฟล์/โฟลเดอร์จาก Finder ("Open With" หรือลากไปวางที่ไอคอนใน Dock)
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        BrowserModel.shared.openExternal(url)
    }
}

struct IrisCommands: Commands {
    let model: BrowserModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("เปิดโฟลเดอร์…") { model.chooseFolder() }
                .keyboardShortcut("o")
            Button("นำเข้าจากการ์ดกล้อง…") { model.presentImport() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Button("ค้นหาขั้นสูง…") { model.presentSearch() }
                .keyboardShortcut("f", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .printItem) {
            Button("สร้าง Contact Sheet (PDF)…") { model.presentContactSheet() }
                .keyboardShortcut("p")
        }

        CommandMenu("ไป") {
            Button("ย้อนกลับ") { model.goBack() }
                .keyboardShortcut("[")
            Button("ไปข้างหน้า") { model.goForward() }
                .keyboardShortcut("]")
            Button("โฟลเดอร์ระดับบน") { model.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Divider()
            Button("รีเฟรช") { model.refresh() }
                .keyboardShortcut("r")
        }

        CommandMenu("ภาพ") {
            Button("เปิดดูภาพ   (Return / Space)") { model.openViewerAtCursor() }
            Button("เทียบภาพที่เลือก   (C)") { model.startCompare() }
            Button("สไลด์โชว์") { model.toggleSlideshow() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Divider()
            Menu("คะแนนดาว") {
                Button("ไม่มีดาว   (0)") { model.setRating(0) }
                ForEach(1...5, id: \.self) { n in
                    Button("\(String(repeating: "★", count: n))   (\(n))") { model.setRating(n) }
                }
            }
            Menu("ป้ายสี") {
                ForEach(ColorLabel.allCases) { label in
                    Button(label.shortcutHint.map { "\(label.title)   (\($0))" } ?? label.title) {
                        model.setLabel(label)
                    }
                }
            }
            Divider()
            Button("หมุนซ้าย 90°   (L)") { model.rotate(.left) }
            Button("หมุนขวา 90°   (R)") { model.rotate(.right) }
            Divider()
            Button("แก้ไขในแอปอื่น   (E)") { model.openInEditor() }
            Button("คัดลอกไปที่…") { model.chooseDestination(move: false) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("ย้ายไปที่…") { model.chooseDestination(move: true) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("เปลี่ยนชื่อหลายไฟล์…   (F2)") { model.presentRename() }
            Button("แปลง/ย่อขนาดภาพ…") { model.presentExport() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("แสดงใน Finder") { model.revealSelection() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("คัดลอกพาธไฟล์") { model.copyPaths() }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Divider()
            Button("ย้ายไปถังขยะ   (⌘⌫)") { model.trashSelectionOrCurrent() }
        }

        CommandGroup(after: .sidebar) {
            Button("แสดง/ซ่อนแผงข้อมูลภาพ") { model.toggleInfoPanel() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Button("ขยาย") { model.zoomInCommand() }
                .keyboardShortcut("=")
            Button("ย่อ") { model.zoomOutCommand() }
                .keyboardShortcut("-")
            Button("พอดีหน้าต่าง") { model.fitCommand() }
                .keyboardShortcut("9")
            Button("ขนาดจริง (100%)") { model.actualSizeCommand() }
                .keyboardShortcut("0")
            Divider()
        }
    }
}
