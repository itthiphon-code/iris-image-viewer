import AppKit
import Observation

/// ช่องภาพหนึ่งช่องในโหมดเทียบภาพ
@MainActor
final class ComparePane {
    weak var scrollView: ViewerScrollView?
    weak var imageView: NSImageView?
    var url: URL?
    var pixelSize: CGSize = .zero
    var observers: [NSObjectProtocol] = []
    var targets: [GestureTarget] = []
    var loadTask: Task<Void, Never>?

    func tearDown() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        targets.removeAll()
        loadTask?.cancel()
    }
}

/// ควบคุมโหมดเทียบภาพ 2–4 ภาพ: ซูม/เลื่อนพร้อมกัน (linked) และช่องที่กำลังเลือก (active)
@MainActor
@Observable
final class CompareController {
    var activeIndex = 0
    var isLinked = true {
        didSet { if isLinked { sync(from: activeIndex) } }
    }
    private(set) var zoom: CGFloat = 1
    private(set) var fitMode = true

    @ObservationIgnored private var panes: [Int: ComparePane] = [:]
    @ObservationIgnored private var isSyncing = false

    private let minZoom: CGFloat = 0.02
    private let maxZoom: CGFloat = 32

    // MARK: - เชื่อมต่อ

    func attach(index: Int, scrollView sv: ViewerScrollView, imageView iv: NSImageView) {
        let pane = panes[index] ?? ComparePane()
        pane.tearDown()
        pane.scrollView = sv
        pane.imageView = iv
        pane.url = nil
        panes[index] = pane

        sv.minMagnification = minZoom
        sv.maxMagnification = maxZoom
        sv.postsFrameChangedNotifications = true
        sv.contentView.postsBoundsChangedNotifications = true

        let center = NotificationCenter.default
        pane.observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: sv.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.paneDidScroll(index) }
        })
        pane.observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: sv, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.paneDidResize(index) }
        })
        pane.observers.append(center.addObserver(forName: NSScrollView.willStartLiveMagnifyNotification, object: sv, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fitMode = false
                self?.activeIndex = index
            }
        })
        pane.observers.append(center.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: sv, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateZoomLabel() }
        })

        let click = GestureTarget { [weak self] _ in self?.activeIndex = index }
        let clickRecognizer = NSClickGestureRecognizer(target: click, action: #selector(GestureTarget.fire(_:)))
        sv.addGestureRecognizer(clickRecognizer)

        let doubleClick = GestureTarget { [weak self] g in
            guard let self, let doc = self.panes[index]?.scrollView?.documentView else { return }
            self.activeIndex = index
            self.toggleFitActual(at: g.location(in: doc))
        }
        let doubleRecognizer = NSClickGestureRecognizer(target: doubleClick, action: #selector(GestureTarget.fire(_:)))
        doubleRecognizer.numberOfClicksRequired = 2
        sv.addGestureRecognizer(doubleRecognizer)

        let pan = GestureTarget { [weak self] g in self?.handlePan(g, index: index) }
        sv.addGestureRecognizer(NSPanGestureRecognizer(target: pan, action: #selector(GestureTarget.fire(_:))))

        pane.targets = [click, doubleClick, pan]
    }

    func detachAll() {
        panes.values.forEach { $0.tearDown() }
        panes.removeAll()
        fitMode = true
        zoom = 1
        activeIndex = 0
    }

    // MARK: - โหลดภาพ

    func load(index: Int, url: URL) {
        guard let pane = panes[index], pane.url != url else { return }
        pane.url = url
        pane.loadTask?.cancel()

        if let thumb = ThumbnailLoader.shared.bestCached(url),
           let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let px = ImageDecoder.pixelSize(of: url) {
            display(NSImage(cgImage: cg, size: px), pixelSize: px, in: pane)
        } else {
            pane.imageView?.image = nil
        }

        pane.loadTask = Task { [weak self, weak pane] in
            let decoded = await Task.detached(priority: .userInitiated) {
                ImageDecoder.loadFull(url: url)
            }.value
            guard let self, let pane, !Task.isCancelled, pane.url == url, let decoded else { return }
            self.display(decoded.image, pixelSize: decoded.pixelSize, in: pane)
        }
    }

    /// โหลดใหม่หลังไฟล์ถูกแก้ (เช่น หมุนภาพ)
    func reload(_ url: URL) {
        for (index, pane) in panes where pane.url == url {
            pane.url = nil
            load(index: index, url: url)
        }
    }

    private func display(_ image: NSImage, pixelSize px: CGSize, in pane: ComparePane) {
        guard let iv = pane.imageView, let sv = pane.scrollView else { return }
        pane.pixelSize = px
        let scale = sv.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let logical = NSSize(width: max(1, px.width / scale), height: max(1, px.height / scale))
        image.size = logical
        let sizeChanged = iv.frame.size != logical
        iv.image = image
        guard sizeChanged else { return }
        iv.frame = NSRect(origin: .zero, size: logical)

        isSyncing = true
        fitPane(pane)
        isSyncing = false
        if !fitMode, let index = panes.first(where: { $0.value === pane })?.key, index != activeIndex {
            sync(from: activeIndex)
        }
        updateZoomLabel()
    }

    // MARK: - ซูม

    private func fitScale(_ pane: ComparePane) -> CGFloat? {
        guard let sv = pane.scrollView, let doc = sv.documentView,
              doc.frame.width > 0, doc.frame.height > 0,
              sv.contentSize.width > 1, sv.contentSize.height > 1
        else { return nil }
        let scale = min(sv.contentSize.width / doc.frame.width, sv.contentSize.height / doc.frame.height)
        return max(minZoom, AppSettings.shared.enlargeSmallImages ? scale : min(scale, 1))
    }

    private func fitPane(_ pane: ComparePane) {
        guard let sv = pane.scrollView, let doc = sv.documentView, let scale = fitScale(pane) else { return }
        sv.setMagnification(scale, centeredAt: NSPoint(x: doc.frame.midX, y: doc.frame.midY))
    }

    func fitAll() {
        fitMode = true
        isSyncing = true
        panes.values.forEach { fitPane($0) }
        isSyncing = false
        updateZoomLabel()
    }

    func actualSize(at point: NSPoint? = nil) { setZoom(1, at: point) }
    func zoomIn() { setZoom(zoom * 1.25) }
    func zoomOut() { setZoom(zoom / 1.25) }

    func toggleFitActual(at point: NSPoint? = nil) {
        if fitMode { actualSize(at: point) } else { fitAll() }
    }

    func setZoom(_ value: CGFloat, at point: NSPoint? = nil) {
        guard let sv = panes[activeIndex]?.scrollView else { return }
        fitMode = false
        let target = max(minZoom, min(value, maxZoom))
        let bounds = sv.contentView.bounds
        isSyncing = true
        sv.setMagnification(target, centeredAt: point ?? NSPoint(x: bounds.midX, y: bounds.midY))
        isSyncing = false
        sync(from: activeIndex)
        updateZoomLabel()
    }

    private func updateZoomLabel() {
        if let sv = panes[activeIndex]?.scrollView { zoom = sv.magnification }
    }

    // MARK: - ซิงก์ระหว่างช่อง

    private func paneDidScroll(_ index: Int) {
        guard !isSyncing else { return }
        if index == activeIndex { updateZoomLabel() }
        if isLinked { sync(from: index) }
    }

    private func paneDidResize(_ index: Int) {
        guard let pane = panes[index] else { return }
        if fitMode {
            isSyncing = true
            fitPane(pane)
            isSyncing = false
        } else if index == activeIndex {
            sync(from: index)
        }
    }

    /// ให้ทุกช่องเห็นส่วนเดียวกันของภาพ (ตำแหน่งสัมพัทธ์เท่ากัน ซูมปรับตามความกว้างภาพ)
    private func sync(from index: Int) {
        guard isLinked, !isSyncing,
              let source = panes[index]?.scrollView,
              let sourceDoc = source.documentView,
              sourceDoc.frame.width > 0, sourceDoc.frame.height > 0
        else { return }

        isSyncing = true
        defer { isSyncing = false }

        let visible = source.contentView.bounds
        let rel = NSPoint(x: visible.midX / sourceDoc.frame.width, y: visible.midY / sourceDoc.frame.height)

        for (i, pane) in panes where i != index {
            guard let sv = pane.scrollView, let doc = sv.documentView, doc.frame.width > 0 else { continue }
            let magnification = source.magnification * sourceDoc.frame.width / doc.frame.width
            sv.magnification = max(minZoom, min(magnification, maxZoom))
            let clip = sv.contentView
            let origin = NSPoint(
                x: rel.x * doc.frame.width - clip.bounds.width / 2,
                y: rel.y * doc.frame.height - clip.bounds.height / 2
            )
            let constrained = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size))
            clip.scroll(to: constrained.origin)
            sv.reflectScrolledClipView(clip)
        }
    }

    private func handlePan(_ g: NSGestureRecognizer, index: Int) {
        guard let pan = g as? NSPanGestureRecognizer, let sv = panes[index]?.scrollView else { return }
        if pan.state == .began { activeIndex = index }
        let t = pan.translation(in: sv)
        let clip = sv.contentView
        var origin = clip.bounds.origin
        origin.x -= t.x / sv.magnification
        origin.y -= t.y / sv.magnification
        let constrained = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size))
        clip.scroll(to: constrained.origin)
        sv.reflectScrolledClipView(clip)
        pan.setTranslation(.zero, in: sv)
    }
}
