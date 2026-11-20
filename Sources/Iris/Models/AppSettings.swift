import SwiftUI
import Observation

enum ViewerBackground: String, CaseIterable, Identifiable {
    case dark, black, gray, light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "เทาเข้ม"
        case .black: return "ดำสนิท"
        case .gray: return "เทากลาง (18%)"
        case .light: return "ขาว"
        }
    }

    var color: Color {
        switch self {
        case .dark: return Color(white: 0.075)
        case .black: return .black
        case .gray: return Color(white: 0.46)
        case .light: return Color(white: 0.96)
        }
    }
}

enum WheelAction: String, CaseIterable, Identifiable {
    case navigate, zoom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .navigate: return "เปลี่ยนภาพ (แบบ ACDSee)"
        case .zoom: return "ซูมเข้า/ออก"
        }
    }
}

/// การตั้งค่าของแอป (บันทึกใน UserDefaults) — เปิดด้วย ⌘,
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let autoRefresh = "set.autoRefresh"
        static let groupRawJpeg = "set.groupRawJpeg"
        static let confirmTrash = "set.confirmTrash"
        static let enlargeSmall = "set.enlargeSmall"
        static let background = "set.viewerBackground"
        static let wheel = "set.wheelAction"
        static let slideshow = "set.slideshowInterval"
        static let editor = "set.editorPath"
        static let destinations = "set.recentDestinations"
        static let xmp = "set.writeXMPSidecar"
        static let importDestination = "set.importDestination"
        static let importPattern = "set.importPattern"
    }

    /// ติดตามโฟลเดอร์ แล้วแสดงรูปใหม่อัตโนมัติ
    var autoRefresh: Bool {
        didSet {
            UserDefaults.standard.set(autoRefresh, forKey: Key.autoRefresh)
            BrowserModel.shared.updateWatcher()
        }
    }

    /// รวมไฟล์ RAW กับ JPEG/HEIC ชื่อเดียวกันเป็นรายการเดียว
    var groupRawJpeg: Bool {
        didSet {
            UserDefaults.standard.set(groupRawJpeg, forKey: Key.groupRawJpeg)
            BrowserModel.shared.refresh()
        }
    }

    var confirmTrash: Bool {
        didSet { UserDefaults.standard.set(confirmTrash, forKey: Key.confirmTrash) }
    }

    /// ขยายภาพที่เล็กกว่าหน้าต่างให้เต็มจอ
    var enlargeSmallImages: Bool {
        didSet {
            UserDefaults.standard.set(enlargeSmallImages, forKey: Key.enlargeSmall)
            BrowserModel.shared.viewer.refit()
        }
    }

    var viewerBackground: ViewerBackground {
        didSet { UserDefaults.standard.set(viewerBackground.rawValue, forKey: Key.background) }
    }

    var wheelAction: WheelAction {
        didSet { UserDefaults.standard.set(wheelAction.rawValue, forKey: Key.wheel) }
    }

    var slideshowInterval: Double {
        didSet { UserDefaults.standard.set(slideshowInterval, forKey: Key.slideshow) }
    }

    /// แอปภายนอกสำหรับแก้ไขภาพ (เช่น Lumen, Photoshop)
    var editorPath: String? {
        didSet { UserDefaults.standard.set(editorPath, forKey: Key.editor) }
    }

    /// โฟลเดอร์ปลายทางที่ใช้คัดลอก/ย้ายล่าสุด
    var recentDestinations: [String] {
        didSet { UserDefaults.standard.set(recentDestinations, forKey: Key.destinations) }
    }

    /// เขียน XMP sidecar ให้ไฟล์ RAW เมื่อให้ดาว/ป้ายสี
    var writeXMPSidecar: Bool {
        didSet { UserDefaults.standard.set(writeXMPSidecar, forKey: Key.xmp) }
    }

    /// โฟลเดอร์หลักสำหรับนำเข้ารูปจากการ์ด
    var importDestination: String {
        didSet { UserDefaults.standard.set(importDestination, forKey: Key.importDestination) }
    }

    var importPattern: ImportPattern {
        didSet { UserDefaults.standard.set(importPattern.rawValue, forKey: Key.importPattern) }
    }

    var editorURL: URL? {
        guard let editorPath, FileManager.default.fileExists(atPath: editorPath) else { return nil }
        return URL(fileURLWithPath: editorPath)
    }

    var editorName: String? {
        guard let url = editorURL else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var destinationURLs: [URL] {
        recentDestinations
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func rememberDestination(_ url: URL) {
        var list = recentDestinations.filter { $0 != url.path }
        list.insert(url.path, at: 0)
        recentDestinations = Array(list.prefix(8))
    }

    private init() {
        let d = UserDefaults.standard
        autoRefresh = d.object(forKey: Key.autoRefresh) as? Bool ?? true
        groupRawJpeg = d.object(forKey: Key.groupRawJpeg) as? Bool ?? true
        confirmTrash = d.object(forKey: Key.confirmTrash) as? Bool ?? false
        enlargeSmallImages = d.object(forKey: Key.enlargeSmall) as? Bool ?? false
        viewerBackground = ViewerBackground(rawValue: d.string(forKey: Key.background) ?? "") ?? .dark
        wheelAction = WheelAction(rawValue: d.string(forKey: Key.wheel) ?? "") ?? .navigate
        let interval = d.double(forKey: Key.slideshow)
        slideshowInterval = interval > 0 ? interval : 3
        editorPath = d.string(forKey: Key.editor)
        recentDestinations = d.stringArray(forKey: Key.destinations) ?? []
        writeXMPSidecar = d.object(forKey: Key.xmp) as? Bool ?? true
        importDestination = d.string(forKey: Key.importDestination)
            ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory()
        importPattern = ImportPattern(rawValue: d.string(forKey: Key.importPattern) ?? "") ?? .yearDay
    }
}
