import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers

/// สถานะหลักของแอป: โฟลเดอร์ปัจจุบัน, รายการภาพ, การเลือก, โหมดดูภาพ
@MainActor
@Observable
final class BrowserModel {
    static let shared = BrowserModel()

    // MARK: โฟลเดอร์และรายการภาพ
    private(set) var currentFolder: URL?
    private(set) var items: [ImageItem] = []
    private(set) var isLoading = false
    private(set) var allItems: [ImageItem] = []
    @ObservationIgnored private var indexByID: [URL: Int] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var pendingViewURL: URL?
    @ObservationIgnored private var xmpTask: Task<Void, Never>?

    var filterText = "" { didSet { rebuild() } }
    var sortKey: SortKey = .name {
        didSet { UserDefaults.standard.set(sortKey.rawValue, forKey: Keys.sortKey); rebuild() }
    }
    var sortAscending = true {
        didSet { UserDefaults.standard.set(sortAscending, forKey: Keys.sortAscending); rebuild() }
    }
    /// แสดงเฉพาะรูปที่มีดาวอย่างน้อยเท่านี้ (0 = ทั้งหมด)
    var minRating = 0 { didSet { rebuild() } }
    var labelFilter: LabelFilter = .any { didSet { rebuild() } }
    var isFiltering: Bool { minRating > 0 || labelFilter != .any }

    // MARK: หน้าต่างย่อย (sheet) และข้อความแจ้งเตือน
    var activeSheet: SheetKind?
    private(set) var sheetTargets: [ImageItem] = []
    var alertMessage: String?
    @ObservationIgnored private var pendingSelectionPaths: Set<String>?

    // MARK: การเลือก
    var selection: Set<URL> = []
    var cursor: URL?
    @ObservationIgnored private var anchor: URL?
    /// จำนวนคอลัมน์ของตารางภาพย่อ (ใช้กับปุ่มลูกศรขึ้น/ลง)
    @ObservationIgnored var gridColumns = 1

    // MARK: หน้าตา
    var thumbSize: Double = 170 {
        didSet { UserDefaults.standard.set(thumbSize, forKey: Keys.thumbSize) }
    }
    var showInspector = true
    var sidebarVisibility: NavigationSplitViewVisibility = .all
    var sidebarSelection: URL?

    // MARK: แผนผังโฟลเดอร์
    private(set) var favorites: [FolderNode] = []
    private(set) var locations: [FolderNode] = []
    private(set) var volumes: [FolderNode] = []

    // MARK: ประวัติการเดินทาง
    @ObservationIgnored private var backStack: [URL] = []
    @ObservationIgnored private var forwardStack: [URL] = []
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    // MARK: โหมดดูภาพ
    private(set) var isViewing = false
    private(set) var viewerIndex = 0
    var showFilmstrip = true
    var showViewerInfo = false
    private(set) var isSlideshow = false
    @ObservationIgnored private var slideshowTask: Task<Void, Never>?

    let viewer = ViewerController()
    let compare = CompareController()
    private let watcher = FolderWatcher()

    // MARK: โหมดเทียบภาพ
    private(set) var compareURLs: [URL] = []
    var isComparing: Bool { !compareURLs.isEmpty }
    var compareItems: [ImageItem] {
        compareURLs.compactMap { url in allItems.first { $0.url == url } }
    }

    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var started = false

    private enum Keys {
        static let lastFolder = "lastFolder"
        static let favorites = "favorites"
        static let thumbSize = "thumbSize"
        static let sortKey = "sortKey"
        static let sortAscending = "sortAscending"
    }

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: Keys.thumbSize) != nil { thumbSize = d.double(forKey: Keys.thumbSize) }
        if let raw = d.string(forKey: Keys.sortKey), let k = SortKey(rawValue: raw) { sortKey = k }
        if d.object(forKey: Keys.sortAscending) != nil { sortAscending = d.bool(forKey: Keys.sortAscending) }

        watcher.onChange = { [weak self] in self?.reloadFromWatcher() }
        viewer.onNavigate = { [weak self] step in
            guard let self else { return }
            step > 0 ? self.showNext() : self.showPrevious()
        }
    }

    // MARK: - เริ่มต้น

    func start() {
        guard !started else { return }
        started = true
        installKeyMonitor()
        buildSidebar()

        // ถ้าถูกเปิดจาก Finder พร้อมไฟล์ จะมีโฟลเดอร์อยู่แล้ว ไม่ต้องเปิดโฟลเดอร์เดิม
        guard currentFolder == nil else { return }
        let fm = FileManager.default
        if let path = UserDefaults.standard.string(forKey: Keys.lastFolder),
           fm.fileExists(atPath: path) {
            open(folder: URL(fileURLWithPath: path, isDirectory: true), recordHistory: false)
        } else if let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask).first {
            open(folder: pictures, recordHistory: false)
        }
    }

    private func buildSidebar() {
        let fm = FileManager.default
        func dir(_ d: FileManager.SearchPathDirectory) -> URL? { fm.urls(for: d, in: .userDomainMask).first }

        var locs: [FolderNode] = []
        if let u = dir(.picturesDirectory) { locs.append(FolderNode(url: u, icon: "photo.on.rectangle")) }
        if let u = dir(.desktopDirectory) { locs.append(FolderNode(url: u, icon: "menubar.dock.rectangle")) }
        if let u = dir(.downloadsDirectory) { locs.append(FolderNode(url: u, icon: "arrow.down.circle")) }
        if let u = dir(.documentDirectory) { locs.append(FolderNode(url: u, icon: "doc")) }
        locs.append(FolderNode(url: fm.homeDirectoryForCurrentUser, icon: "house"))
        locations = locs

        reloadVolumes()

        let paths = UserDefaults.standard.stringArray(forKey: Keys.favorites) ?? []
        favorites = paths
            .filter { fm.fileExists(atPath: $0) }
            .map { FolderNode(url: URL(fileURLWithPath: $0, isDirectory: true), icon: "star") }
    }

    func reloadVolumes() {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsInternalKey],
            options: [.skipHiddenVolumes]
        ) ?? []
        volumes = urls.map { url in
            let isInternal = (try? url.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) ?? true
            return FolderNode(url: url, icon: isInternal == true ? "internaldrive" : "externaldrive")
        }
    }

    // MARK: - รายการโปรด

    func isFavorite(_ url: URL) -> Bool { favorites.contains { $0.url == url } }

    func toggleFavorite(_ url: URL) {
        if isFavorite(url) {
            favorites.removeAll { $0.url == url }
        } else {
            favorites.append(FolderNode(url: url, icon: "star"))
        }
        UserDefaults.standard.set(favorites.map(\.url.path), forKey: Keys.favorites)
    }

    // MARK: - นำทางโฟลเดอร์

    func open(folder url: URL, recordHistory: Bool = true) {
        let folder = url.standardizedFileURL
        guard folder.path != currentFolder?.path || searchCriteria != nil else { return }
        endSearchState()
        if isViewing { closeViewer() }
        if recordHistory, let current = currentFolder {
            backStack.append(current)
            forwardStack.removeAll()
        }
        updateHistoryFlags()
        if isComparing { exitCompare() }
        currentFolder = folder
        updateWatcher()
        sidebarSelection = folder
        UserDefaults.standard.set(folder.path, forKey: Keys.lastFolder)
        load(folder, keepSelection: false)
    }

    func refresh() {
        if let criteria = searchCriteria { runSearch(criteria); return }
        guard let folder = currentFolder else { return }
        load(folder, keepSelection: true)
        (favorites + locations + volumes).forEach { $0.reload() }
    }

    private func load(_ folder: URL, keepSelection: Bool) {
        loadTask?.cancel()
        isLoading = true
        if !keepSelection {
            selection = []
            cursor = nil
            anchor = nil
            allItems = []
            rebuild()
        }
        loadTask = Task { [weak self] in
            let group = AppSettings.shared.groupRawJpeg
            let found = await Task.detached(priority: .userInitiated) {
                let scanned = FolderScanner.scanImages(in: folder)
                return group ? FolderScanner.groupRawPairs(scanned) : scanned
            }.value
            guard let self, !Task.isCancelled, self.currentFolder?.path == folder.path else { return }
            self.allItems = found
            self.rebuild()
            self.isLoading = false
            self.enrichFromXMP()

            if let paths = self.pendingSelectionPaths {
                self.pendingSelectionPaths = nil
                let ids = self.items.filter { paths.contains($0.url.path) }.map(\.id)
                self.selection = Set(ids)
                self.cursor = ids.first ?? self.items.first?.id
                self.anchor = self.cursor
            } else if keepSelection {
                self.selection = self.selection.filter { self.indexByID[$0] != nil }
                if let c = self.cursor, self.indexByID[c] == nil { self.cursor = self.items.first?.id }
            } else if let first = self.items.first {
                self.cursor = first.id
                self.anchor = first.id
                self.selection = [first.id]
            }

            if let pending = self.pendingViewURL {
                self.pendingViewURL = nil
                if let item = self.items.first(where: { $0.url == pending }) { self.open(item) }
            }
        }
    }

    // MARK: - ติดตามโฟลเดอร์

    func updateWatcher() {
        if AppSettings.shared.autoRefresh && searchCriteria == nil {
            watcher.watch(currentFolder)
        } else {
            watcher.stop()
        }
    }

    private func reloadFromWatcher() {
        guard let folder = currentFolder, activeSheet == nil, searchCriteria == nil else { return }
        load(folder, keepSelection: true)
    }

    // MARK: - ค้นหาขั้นสูง

    /// มีค่า = กำลังแสดงผลการค้นหา (แทนเนื้อหาโฟลเดอร์)
    private(set) var searchCriteria: SearchCriteria?
    private(set) var lastSearch: SearchCriteria?
    private(set) var isSearching = false
    private(set) var searchScanned = 0
    @ObservationIgnored private var searchFlag: CancelFlag?

    var searchRootName: String {
        currentFolder.map { FileManager.default.displayName(atPath: $0.path) } ?? "-"
    }

    func presentSearch() {
        if isViewing { closeViewer() }
        if isComparing { exitCompare() }
        guard currentFolder != nil else { NSSound.beep(); return }
        activeSheet = .search
    }

    func runSearch(_ criteria: SearchCriteria) {
        guard let root = currentFolder else { return }
        if isViewing { closeViewer() }
        loadTask?.cancel()
        xmpTask?.cancel()
        searchFlag?.cancel()
        watcher.stop()

        searchCriteria = criteria
        lastSearch = criteria
        isSearching = true
        isLoading = false
        searchScanned = 0
        allItems = []
        selection = []
        cursor = nil
        anchor = nil
        rebuild()

        let flag = CancelFlag()
        searchFlag = flag
        let group = AppSettings.shared.groupRawJpeg
        Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                MetadataSearch.run(root: root, criteria: criteria, groupPairs: group, flag: flag) { scanned, _ in
                    Task { @MainActor in
                        if BrowserModel.shared.searchFlag === flag { BrowserModel.shared.searchScanned = scanned }
                    }
                }
            }.value
            guard let self, self.searchFlag === flag, self.searchCriteria != nil else { return }
            self.isSearching = false
            self.allItems = found
            self.rebuild()
            if let first = self.items.first {
                self.cursor = first.id
                self.anchor = first.id
                self.selection = [first.id]
            }
            self.enrichFromXMP()
        }
    }

    /// หยุดค้นหา (เก็บผลที่เจอแล้วไว้)
    func stopSearch() {
        searchFlag?.cancel()
    }

    /// ออกจากผลการค้นหา กลับไปที่โฟลเดอร์
    func exitSearch() {
        guard searchCriteria != nil else { return }
        endSearchState()
        if let folder = currentFolder { load(folder, keepSelection: false) }
        updateWatcher()
    }

    private func endSearchState() {
        searchFlag?.cancel()
        searchFlag = nil
        searchCriteria = nil
        isSearching = false
    }

    // MARK: - นำเข้า / Contact sheet

    func presentImport() {
        if isViewing { closeViewer() }
        if isComparing { exitCompare() }
        activeSheet = .importer
    }

    func presentContactSheet() {
        if isViewing { closeViewer() }
        if isComparing { exitCompare() }
        let chosen = selectedItems.count >= 2 ? selectedItems : items
        guard !chosen.isEmpty else { NSSound.beep(); return }
        sheetTargets = chosen
        activeSheet = .contactSheet
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let current = currentFolder { forwardStack.append(current) }
        open(folder: previous, recordHistory: false)
        updateHistoryFlags()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = currentFolder { backStack.append(current) }
        open(folder: next, recordHistory: false)
        updateHistoryFlags()
    }

    var canGoUp: Bool { currentFolder.map { $0.path != "/" } ?? false }

    func goUp() {
        guard let current = currentFolder, current.path != "/" else { return }
        let parent = current.deletingLastPathComponent()
        open(folder: parent)
    }

    private func updateHistoryFlags() {
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "เปิด"
        panel.message = "เลือกโฟลเดอร์รูปภาพ"
        if panel.runModal() == .OK, let url = panel.url { open(folder: url) }
    }

    /// เปิดจากภายนอก (Finder / Dock / ลากมาวาง)
    func openExternal(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            open(folder: url)
        } else {
            let folder = url.deletingLastPathComponent().standardizedFileURL
            if folder.path == currentFolder?.path, let item = items.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                open(item)
            } else {
                pendingViewURL = url.standardizedFileURL
                open(folder: folder)
            }
        }
    }

    // MARK: - เรียงและกรอง

    private func rebuild() {
        let viewingID = isViewing ? currentViewerItem?.id : nil
        var list = allItems
        let q = filterText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(q) }
        }
        if minRating > 0 {
            list = list.filter { $0.rating >= minRating }
        }
        switch labelFilter {
        case .any: break
        case .unlabeled: list = list.filter { $0.label == .none }
        case .label(let wanted): list = list.filter { $0.label == wanted }
        }
        let key = sortKey
        let asc = sortAscending
        list.sort { a, b in
            let ordered: Bool
            switch key {
            case .name:
                ordered = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .modified:
                ordered = a.modified == b.modified
                    ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                    : a.modified < b.modified
            case .created:
                ordered = a.created == b.created
                    ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                    : a.created < b.created
            case .size:
                ordered = a.fileSize == b.fileSize
                    ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                    : a.fileSize < b.fileSize
            case .type:
                ordered = a.ext == b.ext
                    ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                    : a.ext < b.ext
            case .rating:
                ordered = a.rating == b.rating
                    ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                    : a.rating < b.rating
            }
            return asc ? ordered : !ordered
        }
        items = list
        var index: [URL: Int] = [:]
        index.reserveCapacity(list.count)
        for (i, item) in list.enumerated() { index[item.id] = i }
        indexByID = index

        // อยู่ในโหมดดูภาพ: ให้ยังอยู่ที่ภาพเดิม หรือขยับไปภาพถัดไปถ้าภาพเดิมถูกกรองออก
        if let viewingID {
            if let i = index[viewingID] {
                viewerIndex = i
            } else if !list.isEmpty {
                show(index: min(viewerIndex, list.count - 1))
            }
        }
    }

    // MARK: - การเลือก

    var focusedItem: ImageItem? {
        guard let cursor, let i = indexByID[cursor] else { return nil }
        return items[i]
    }

    func isSelected(_ item: ImageItem) -> Bool { selection.contains(item.id) }

    func click(_ item: ImageItem, command: Bool, shift: Bool) {
        // ให้คีย์ลูกศรกลับมาควบคุมตารางภาพ (ไม่ใช่แถบด้านซ้าย/ช่องค้นหา)
        _ = NSApp.keyWindow?.makeFirstResponder(nil)
        if command {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            cursor = item.id
            anchor = item.id
        } else if shift, let anchor, let a = indexByID[anchor], let b = indexByID[item.id] {
            selection = Set(items[min(a, b)...max(a, b)].map(\.id))
            cursor = item.id
        } else {
            selection = [item.id]
            cursor = item.id
            anchor = item.id
        }
    }

    func selectAll() {
        selection = Set(items.map(\.id))
    }

    func clearSelection() {
        selection = []
    }

    func moveCursor(by delta: Int, extend: Bool) {
        guard !items.isEmpty else { return }
        let current = cursor.flatMap { indexByID[$0] } ?? -1
        let next = max(0, min(items.count - 1, current + delta))
        moveCursor(to: next, extend: extend)
    }

    func moveCursor(to index: Int, extend: Bool) {
        guard items.indices.contains(index) else { return }
        let id = items[index].id
        if extend, let anchor, let a = indexByID[anchor] {
            selection = Set(items[min(a, index)...max(a, index)].map(\.id))
        } else {
            selection = [id]
            anchor = id
        }
        cursor = id
    }

    var selectedItems: [ImageItem] {
        items.filter { selection.contains($0.id) }
    }

    var statusText: String {
        var parts: [String] = []
        if allItems.count != items.count {
            parts.append("แสดง \(items.count) จาก \(allItems.count) รูป")
        } else {
            parts.append("\(items.count) รูป")
        }
        let selected = selectedItems
        if !selected.isEmpty {
            let total = selected.reduce(Int64(0)) { $0 + $1.fileSize }
            parts.append("เลือก \(selected.count) รูป (\(Format.bytes(total)))")
        }
        return parts.joined(separator: "  •  ")
    }

    var folderTitle: String {
        if searchCriteria != nil { return "ผลการค้นหา" }
        guard let f = currentFolder else { return "Iris" }
        return FileManager.default.displayName(atPath: f.path)
    }

    // MARK: - คำสั่งกับไฟล์

    func revealSelection() {
        let urls = isViewing ? [currentViewerItem?.url].compactMap { $0 } : selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyPaths(_ urls: [URL]? = nil) {
        let list = urls ?? (isViewing ? [currentViewerItem?.url].compactMap { $0 } : selectedItems.map(\.url))
        guard !list.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(list.map(\.path).joined(separator: "\n"), forType: .string)
    }

    func trashSelectionOrCurrent() {
        trash(actionTargets)
    }

    /// ย้ายไปถังขยะ (รวมไฟล์คู่ RAW ด้วย) — urls คือไฟล์หลักของรายการ
    func trash(_ primaries: [URL]) {
        guard !primaries.isEmpty else { return }
        if AppSettings.shared.confirmTrash {
            let alert = NSAlert()
            alert.messageText = primaries.count == 1
                ? "ย้าย \(primaries[0].lastPathComponent) ไปถังขยะ?"
                : "ย้าย \(primaries.count) รูปไปถังขยะ?"
            alert.informativeText = "กู้คืนได้จากถังขยะของ Finder"
            alert.addButton(withTitle: "ย้ายไปถังขยะ")
            alert.addButton(withTitle: "ยกเลิก")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let urls = expanded(primaries, sidecars: true)
        let oldIndex = cursor.flatMap { indexByID[$0] } ?? 0
        var removed = Set<URL>()
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                removed.insert(url)
                ThumbnailLoader.shared.removeAll(for: url)
                viewer.forget(url)
            } catch {
                NSSound.beep()
            }
        }
        guard !removed.isEmpty else { return }

        allItems.removeAll { removed.contains($0.url) }
        rebuild()
        selection.subtract(removed)

        if isComparing {
            compareURLs.removeAll { removed.contains($0) }
            if compareURLs.count < 2 { exitCompare() } else { compare.activeIndex = min(compare.activeIndex, compareURLs.count - 1) }
            return
        }

        if items.isEmpty {
            cursor = nil
            if isViewing { closeViewer() }
            return
        }
        if isViewing {
            show(index: min(viewerIndex, items.count - 1))
        } else {
            let i = min(oldIndex, items.count - 1)
            cursor = items[i].id
            anchor = items[i].id
            if selection.isEmpty { selection = [items[i].id] }
        }
    }

    // MARK: - คะแนนดาว / ป้ายสี / หมุนภาพ

    /// ไฟล์ที่คำสั่งจะทำงานด้วย: ภาพที่กำลังดู หรือรูปที่เลือกไว้
    private var actionTargets: [URL] {
        if isComparing {
            return compareURLs.indices.contains(compare.activeIndex) ? [compareURLs[compare.activeIndex]] : []
        }
        if isViewing { return currentViewerItem.map { [$0.url] } ?? [] }
        let selected = selectedItems.map(\.url)
        if !selected.isEmpty { return selected }
        return focusedItem.map { [$0.url] } ?? []
    }

    /// เพิ่มไฟล์คู่ (RAW) เข้าไปในรายการไฟล์หลัก
    /// - Parameter sidecars: รวมไฟล์ .xmp ด้วย (ใช้ตอนทิ้ง/ย้าย/คัดลอก)
    func expanded(_ primaries: [URL], sidecars: Bool = false) -> [URL] {
        let wanted = Set(primaries)
        var companions: [URL: [URL]] = [:]
        for item in allItems where wanted.contains(item.url) && !item.companions.isEmpty {
            companions[item.url] = item.companions
        }
        var seen = Set<URL>()
        var result: [URL] = []
        for primary in primaries {
            var files = [primary] + (companions[primary] ?? [])
            if sidecars { files += files.flatMap { XMPStore.existingSidecars(for: $0) } }
            for f in files where seen.insert(f).inserted { result.append(f) }
        }
        return result
    }

    /// เขียน XMP sidecar ให้ไฟล์ RAW (ตามการตั้งค่า) เพื่อให้ Lightroom เห็นดาว/ป้ายเดียวกัน
    private func syncSidecars(for primaries: Set<URL>) {
        guard AppSettings.shared.writeXMPSidecar else { return }
        for item in allItems where primaries.contains(item.url) {
            for file in item.allURLs where UTType(filenameExtension: file.pathExtension)?.conforms(to: .rawImage) == true {
                XMPStore.writeSidecar(for: file, rating: item.rating, label: item.label)
            }
        }
    }

    /// อ่านดาว/ป้ายจาก XMP (Lightroom/กล้อง) ให้รูปที่ยังไม่เคยให้คะแนนใน Iris — ทำในพื้นหลัง
    private func enrichFromXMP() {
        xmpTask?.cancel()
        let pending = allItems.filter(\.needsXMPCheck).map { ($0.url, $0.companions) }
        guard !pending.isEmpty else { return }
        let flag = CancelFlag()
        xmpTask = Task { [weak self] in
            let found: [URL: XMPStore.Values] = await withTaskCancellationHandler {
                await Task.detached(priority: .utility) {
                    var map: [URL: XMPStore.Values] = [:]
                    for (url, companions) in pending {
                        if flag.isCancelled { break }
                        var values = XMPStore.read(url)
                        if values.isEmpty {
                            for companion in companions {
                                values = XMPStore.read(companion)
                                if !values.isEmpty { break }
                            }
                        }
                        if !values.isEmpty { map[url] = values }
                    }
                    return map
                }.value
            } onCancel: {
                flag.cancel()
            }
            guard let self, !Task.isCancelled, !found.isEmpty else { return }
            for i in self.allItems.indices {
                guard self.allItems[i].needsXMPCheck, let v = found[self.allItems[i].url] else { continue }
                if let r = v.rating { self.allItems[i].rating = r }
                if let l = v.label { self.allItems[i].label = l }
            }
            self.rebuild()
        }
    }

    func setRating(_ rating: Int, for urls: [URL]? = nil) {
        let targets = urls ?? actionTargets
        guard !targets.isEmpty else { return }
        var failed = false
        for url in expanded(targets) where !TagStore.setRating(rating, for: url) { failed = true }
        let set = Set(targets)
        for i in allItems.indices where set.contains(allItems[i].url) {
            allItems[i].rating = rating
            allItems[i].needsXMPCheck = false
        }
        syncSidecars(for: set)
        if failed { NSSound.beep() }
        afterMetadataChange()
    }

    /// กดป้ายสีเดิมซ้ำ = เอาป้ายออก
    func setLabel(_ label: ColorLabel, for urls: [URL]? = nil) {
        let targets = urls ?? actionTargets
        guard !targets.isEmpty else { return }
        let set = Set(targets)
        let current = allItems.filter { set.contains($0.url) }
        let newLabel: ColorLabel = (label != .none && current.allSatisfy { $0.label == label }) ? .none : label
        var failed = false
        for url in expanded(targets) where !TagStore.setLabel(newLabel, for: url) { failed = true }
        for i in allItems.indices where set.contains(allItems[i].url) {
            allItems[i].label = newLabel
            // บันทึกดาวปัจจุบันไว้ด้วย เพื่อให้ Iris เป็นตัวหลัก ไม่กลับไปอ่านค่าเก่าจาก XMP
            for file in allItems[i].allURLs where TagStore.storedRating(of: file) == nil {
                TagStore.setRating(allItems[i].rating, for: file)
            }
            allItems[i].needsXMPCheck = false
        }
        syncSidecars(for: set)
        if failed { NSSound.beep() }
        afterMetadataChange()
    }

    private func afterMetadataChange() {
        rebuild()
        selection = selection.filter { indexByID[$0] != nil }
        if isViewing && items.isEmpty { closeViewer() }
    }

    func rotate(_ direction: ImageRotator.Direction) {
        let targets = actionTargets
        guard !targets.isEmpty else { return }
        Task { [weak self] in
            let failures: [String] = await Task.detached(priority: .userInitiated) {
                var errors: [String] = []
                for url in targets {
                    do {
                        try ImageRotator.rotate(url, direction)
                    } catch {
                        errors.append("\(url.lastPathComponent) — \(error.localizedDescription)")
                    }
                }
                return errors
            }.value
            guard let self else { return }
            self.refreshItems(targets)
            if !failures.isEmpty {
                self.alertMessage = "หมุนภาพไม่สำเร็จ \(failures.count) ไฟล์\n\n" + failures.prefix(8).joined(separator: "\n")
            }
        }
    }

    /// อ่านข้อมูลไฟล์ใหม่หลังไฟล์ถูกแก้ (ล้างแคชภาพย่อ/ภาพเต็มด้วย)
    func refreshItems(_ urls: [URL]) {
        for url in urls {
            ThumbnailLoader.shared.removeAll(for: url)
            viewer.forget(url)
            if let i = allItems.firstIndex(where: { $0.url == url }), var fresh = FolderScanner.item(at: url) {
                let old = allItems[i]
                fresh.companions = old.companions
                fresh.rating = old.rating
                fresh.label = old.label
                allItems[i] = fresh
            }
        }
        rebuild()
        if isViewing, let current = currentViewerItem, urls.contains(current.url) {
            viewer.show(url: current.url)
        }
        if isComparing {
            for url in urls { compare.reload(url) }
        }
    }

    // MARK: - คัดลอก / ย้าย / เปิดในแอปอื่น

    func chooseDestination(move: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = move ? "ย้ายมาที่นี่" : "คัดลอกมาที่นี่"
        panel.message = move ? "เลือกโฟลเดอร์ที่จะย้ายรูปไป" : "เลือกโฟลเดอร์ที่จะคัดลอกรูปไป"
        if panel.runModal() == .OK, let url = panel.url { transfer(move: move, to: url) }
    }

    /// คัดลอกหรือย้ายรูปที่เลือก (รวมไฟล์คู่) ไปยังโฟลเดอร์ปลายทาง
    func transfer(move: Bool, to destination: URL) {
        let primaries = actionTargets
        guard !primaries.isEmpty else { NSSound.beep(); return }
        if destination.standardizedFileURL.path == currentFolder?.path {
            alertMessage = "โฟลเดอร์ปลายทางเป็นโฟลเดอร์เดียวกับที่เปิดอยู่"
            return
        }
        AppSettings.shared.rememberDestination(destination)
        let files = expanded(primaries, sidecars: true)

        Task { [weak self] in
            let failures: [String] = await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                var errors: [String] = []
                for url in files {
                    let target = Self.uniqueDestination(for: url, in: destination)
                    do {
                        if move {
                            try fm.moveItem(at: url, to: target)
                        } else {
                            try fm.copyItem(at: url, to: target)
                        }
                    } catch {
                        errors.append("\(url.lastPathComponent) — \(error.localizedDescription)")
                    }
                }
                return errors
            }.value
            guard let self else { return }
            if move {
                let gone = Set(primaries.filter { !FileManager.default.fileExists(atPath: $0.path) })
                if self.isViewing, let current = self.currentViewerItem, gone.contains(current.url), self.items.count <= 1 {
                    self.closeViewer()
                }
                self.allItems.removeAll { gone.contains($0.url) }
                self.rebuild()
                self.selection.subtract(gone)
                if self.isComparing {
                    self.compareURLs.removeAll { gone.contains($0) }
                    if self.compareURLs.count < 2 { self.exitCompare() }
                }
            }
            if !failures.isEmpty {
                self.alertMessage = (move ? "ย้าย" : "คัดลอก") + "ไม่สำเร็จ \(failures.count) ไฟล์\n\n"
                    + failures.prefix(8).joined(separator: "\n")
            }
        }
    }

    nonisolated private static func uniqueDestination(for url: URL, in folder: URL) -> URL {
        let fm = FileManager.default
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = folder.appendingPathComponent(url.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"
            candidate = folder.appendingPathComponent(name)
            n += 1
        }
        return candidate
    }

    /// เปิดรูปในแอปแก้ไขภาพที่ตั้งไว้ (เช่น Lumen) — ถ้ายังไม่ได้ตั้ง จะให้เลือกแอปก่อน
    func openInEditor() {
        let urls = actionTargets
        guard !urls.isEmpty else { NSSound.beep(); return }
        guard let app = AppSettings.shared.editorURL ?? chooseEditorApp() else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        BrowserModel.shared.alertMessage = "เปิดแอปไม่สำเร็จ: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    @discardableResult
    func chooseEditorApp() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "เลือก"
        panel.message = "เลือกแอปที่ใช้แก้ไขภาพ (เช่น Lumen, Photoshop, Pixelmator)"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        AppSettings.shared.editorPath = url.path
        return url
    }

    // MARK: - โหมดเทียบภาพ

    func startCompare() {
        guard !isViewing else { NSSound.beep(); return }
        let chosen = selectedItems.prefix(4).map(\.url)
        guard chosen.count >= 2 else {
            alertMessage = "เลือก 2–4 รูปก่อน (⌘-คลิก หรือ ⇧-คลิก) แล้วกด C เพื่อเทียบภาพ"
            return
        }
        compare.activeIndex = 0
        compareURLs = chosen
    }

    func exitCompare() {
        guard isComparing else { return }
        let active = compareURLs.indices.contains(compare.activeIndex) ? compareURLs[compare.activeIndex] : nil
        compareURLs = []
        compare.detachAll()
        if let active, indexByID[active] != nil {
            cursor = active
            anchor = active
            selection = [active]
        }
    }

    // MARK: - เปลี่ยนชื่อ / แปลงไฟล์ (sheet)

    func presentRename() { presentSheet(.rename) }
    func presentExport() { presentSheet(.export) }

    private func presentSheet(_ kind: SheetKind) {
        var targets: [ImageItem]
        if isComparing {
            exitCompare()
            targets = selectedItems
        } else if isViewing {
            targets = currentViewerItem.map { [$0] } ?? []
            closeViewer()
        } else {
            targets = selectedItems
            if targets.isEmpty, let f = focusedItem { targets = [f] }
        }
        guard !targets.isEmpty else { NSSound.beep(); return }
        sheetTargets = targets
        activeSheet = kind
    }

    func finishRename(renamed: [URL]) {
        activeSheet = nil
        for item in sheetTargets {
            ThumbnailLoader.shared.removeAll(for: item.url)
            viewer.forget(item.url)
        }
        pendingSelectionPaths = Set(renamed.map(\.path))
        if let criteria = searchCriteria {
            runSearch(criteria)
        } else if let folder = currentFolder {
            load(folder, keepSelection: true)
        }
    }

    // MARK: - โหมดดูภาพ

    var currentViewerItem: ImageItem? {
        items.indices.contains(viewerIndex) ? items[viewerIndex] : nil
    }

    var viewerPositionText: String {
        items.isEmpty ? "" : "\(viewerIndex + 1) / \(items.count)"
    }

    func open(_ item: ImageItem) {
        guard let i = indexByID[item.id] else { return }
        isViewing = true
        show(index: i)
    }

    func openViewerAtCursor() {
        if let item = focusedItem ?? items.first { open(item) }
    }

    func show(index: Int) {
        guard items.indices.contains(index) else { return }
        viewerIndex = index
        let item = items[index]
        viewer.show(url: item.url)

        var neighbors: [URL] = []
        if index + 1 < items.count { neighbors.append(items[index + 1].url) }
        if index > 0 { neighbors.append(items[index - 1].url) }
        viewer.prefetch(neighbors)
    }

    func showNext(wrap: Bool = false) {
        guard !items.isEmpty else { return }
        if viewerIndex + 1 < items.count {
            show(index: viewerIndex + 1)
        } else if wrap {
            show(index: 0)
        } else {
            NSSound.beep()
        }
    }

    func showPrevious() {
        guard viewerIndex > 0 else { NSSound.beep(); return }
        show(index: viewerIndex - 1)
    }

    func closeViewer() {
        stopSlideshow()
        if let item = currentViewerItem {
            cursor = item.id
            anchor = item.id
            selection = [item.id]
        }
        isViewing = false
        viewer.reset()
    }

    // MARK: - สไลด์โชว์

    func toggleSlideshow() {
        isSlideshow ? stopSlideshow() : startSlideshow()
    }

    func startSlideshow() {
        guard !items.isEmpty else { return }
        if !isViewing { openViewerAtCursor() }
        isSlideshow = true
        slideshowTask?.cancel()
        slideshowTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = AppSettings.shared.slideshowInterval
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                self.showNext(wrap: true)
            }
        }
    }

    func stopSlideshow() {
        slideshowTask?.cancel()
        slideshowTask = nil
        isSlideshow = false
    }

    // MARK: - คำสั่งจากเมนู

    func toggleInfoPanel() {
        if isViewing { showViewerInfo.toggle() } else { showInspector.toggle() }
    }

    func zoomInCommand() {
        if isViewing { viewer.zoomIn() } else { thumbSize = min(thumbSize + 30, 360) }
    }

    func zoomOutCommand() {
        if isViewing { viewer.zoomOut() } else { thumbSize = max(thumbSize - 30, 80) }
    }

    func fitCommand() { if isViewing { viewer.fit() } }
    func actualSizeCommand() { if isViewing { viewer.actualSize() } }

    // MARK: - คีย์บอร์ด

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handleKey(event) }
            return handled ? nil : event
        }
    }

    private var isTextInputActive: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView { return textView.isEditable }
        return responder is NSTextField
    }

    /// รหัสปุ่มตามตำแหน่งบนคีย์บอร์ด (ใช้ได้ทั้งแป้นภาษาไทยและอังกฤษ)
    private enum KeyCode {
        static let space: UInt16 = 49, returnKey: UInt16 = 36, enter: UInt16 = 76, escape: UInt16 = 53
        static let delete: UInt16 = 51, forwardDelete: UInt16 = 117
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
        static let home: UInt16 = 115, end: UInt16 = 119, pageUp: UInt16 = 116, pageDown: UInt16 = 121
        static let f2: UInt16 = 120
        static let a: UInt16 = 0, s: UInt16 = 1, f: UInt16 = 3, z: UInt16 = 6
        static let r: UInt16 = 15, t: UInt16 = 17, i: UInt16 = 34, l: UInt16 = 37
        static let c: UInt16 = 8, e: UInt16 = 14, tab: UInt16 = 48
        static let equal: UInt16 = 24, minus: UInt16 = 27, keypadPlus: UInt16 = 69, keypadMinus: UInt16 = 78

        /// ปุ่มตัวเลขแถวบน และแป้นตัวเลข
        static func digit(_ code: UInt16) -> Int? {
            switch code {
            case 29, 82: return 0
            case 18, 83: return 1
            case 19, 84: return 2
            case 20, 85: return 3
            case 21, 86: return 4
            case 23, 87: return 5
            case 22, 88: return 6
            case 26, 89: return 7
            case 28, 91: return 8
            case 25, 92: return 9
            default: return nil
            }
        }
    }

    /// ทำงานกับคีย์บอร์ดเฉพาะเมื่อหน้าต่างหลักโฟกัสอยู่ (ไม่ใช่ตอนเปิด sheet/หน้าต่างเลือกไฟล์)
    private var isMainWindowFocused: Bool {
        guard NSApp.modalWindow == nil, activeSheet == nil,
              let window = NSApp.keyWindow,
              !window.isSheet, window.attachedSheet == nil, !(window is NSPanel)
        else { return false }
        return true
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard isMainWindowFocused, !isTextInputActive else { return false }
        // ถ้ากำลังโฟกัสแถบโฟลเดอร์ด้านซ้าย ให้ลูกศรเลื่อนในแถบนั้นตามปกติ
        if !isViewing, NSApp.keyWindow?.firstResponder is NSTableView { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.control) || mods.contains(.option) { return false }
        let command = mods.contains(.command)
        let shift = mods.contains(.shift)
        let code = event.keyCode

        if command {
            switch code {
            case KeyCode.delete:
                trashSelectionOrCurrent(); return true
            case KeyCode.down where !isViewing:
                openViewerAtCursor(); return true
            case KeyCode.a where !isViewing:
                selectAll(); return true
            default:
                return false
            }
        }

        // ใช้ได้ทั้งสองโหมด
        if let d = KeyCode.digit(code), !shift {
            switch d {
            case 0...5: setRating(d)
            case 6: setLabel(.red)
            case 7: setLabel(.yellow)
            case 8: setLabel(.green)
            default: setLabel(.blue)
            }
            return true
        }
        switch code {
        case KeyCode.r: rotate(.right); return true
        case KeyCode.l: rotate(.left); return true
        case KeyCode.f2: presentRename(); return true
        default: break
        }

        if isComparing { return handleCompareKey(code, shift: shift) }
        return isViewing ? handleViewerKey(code, shift: shift) : handleBrowserKey(code, shift: shift)
    }

    private func handleBrowserKey(_ code: UInt16, shift: Bool) -> Bool {
        let pageStep = max(1, gridColumns) * 4
        switch code {
        case KeyCode.left: moveCursor(by: -1, extend: shift)
        case KeyCode.right: moveCursor(by: 1, extend: shift)
        case KeyCode.up: moveCursor(by: -max(1, gridColumns), extend: shift)
        case KeyCode.down: moveCursor(by: max(1, gridColumns), extend: shift)
        case KeyCode.pageUp: moveCursor(by: -pageStep, extend: shift)
        case KeyCode.pageDown: moveCursor(by: pageStep, extend: shift)
        case KeyCode.home: moveCursor(to: 0, extend: shift)
        case KeyCode.end: moveCursor(to: items.count - 1, extend: shift)
        case KeyCode.returnKey, KeyCode.enter, KeyCode.space: openViewerAtCursor()
        case KeyCode.c: startCompare()
        case KeyCode.e: openInEditor()
        default: return false
        }
        return true
    }

    private func handleCompareKey(_ code: UInt16, shift: Bool) -> Bool {
        let count = compareURLs.count
        switch code {
        case KeyCode.escape, KeyCode.returnKey, KeyCode.enter, KeyCode.c: exitCompare()
        case KeyCode.left: compare.activeIndex = (compare.activeIndex - 1 + count) % count
        case KeyCode.right, KeyCode.tab: compare.activeIndex = (compare.activeIndex + 1) % count
        case KeyCode.equal, KeyCode.keypadPlus: compare.zoomIn()
        case KeyCode.minus, KeyCode.keypadMinus: compare.zoomOut()
        case KeyCode.z: compare.toggleFitActual()
        case KeyCode.e: openInEditor()
        default: return false
        }
        return true
    }

    private func handleViewerKey(_ code: UInt16, shift: Bool) -> Bool {
        switch code {
        case KeyCode.left, KeyCode.pageUp, KeyCode.delete: showPrevious()
        case KeyCode.right, KeyCode.pageDown: showNext()
        case KeyCode.space: shift ? showPrevious() : showNext()
        case KeyCode.home: show(index: 0)
        case KeyCode.end: show(index: items.count - 1)
        case KeyCode.escape, KeyCode.returnKey, KeyCode.enter: closeViewer()
        case KeyCode.equal, KeyCode.keypadPlus: viewer.zoomIn()
        case KeyCode.minus, KeyCode.keypadMinus: viewer.zoomOut()
        case KeyCode.z: viewer.toggleFitActual()
        case KeyCode.i: showViewerInfo.toggle()
        case KeyCode.t: showFilmstrip.toggle()
        case KeyCode.s: toggleSlideshow()
        case KeyCode.f: NSApp.keyWindow?.toggleFullScreen(nil)
        case KeyCode.e: openInEditor()
        default: return false
        }
        return true
    }
}

enum SheetKind: String, Identifiable {
    case rename, export, search, importer, contactSheet
    var id: String { rawValue }
}
