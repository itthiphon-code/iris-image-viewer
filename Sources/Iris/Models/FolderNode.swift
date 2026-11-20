import Foundation
import Observation

/// โหนดในแผนผังโฟลเดอร์ด้านซ้าย (โหลดโฟลเดอร์ย่อยเมื่อกางเท่านั้น)
@MainActor
@Observable
final class FolderNode: Identifiable {
    let url: URL
    let name: String
    let icon: String
    var children: [FolderNode]?
    var hasSubfolders: Bool
    var isExpanded = false {
        didSet {
            if isExpanded && children == nil { loadChildren() }
        }
    }

    nonisolated var id: URL { url }

    init(url: URL, name: String? = nil, icon: String = "folder", hasSubfolders: Bool = true) {
        self.url = url
        self.name = name ?? FileManager.default.displayName(atPath: url.path)
        self.icon = icon
        self.hasSubfolders = hasSubfolders
    }

    func loadChildren() {
        let target = url
        Task {
            let subs = await Task.detached(priority: .userInitiated) {
                FolderScanner.subfolders(of: target)
            }.value
            self.children = subs.map { FolderNode(url: $0.url, hasSubfolders: $0.hasSubfolders) }
            if subs.isEmpty { self.hasSubfolders = false }
        }
    }

    func reload() {
        children = nil
        if isExpanded { loadChildren() }
    }
}
