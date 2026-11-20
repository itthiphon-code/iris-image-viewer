import AppKit
import Observation

/// ควบคุมการแสดงภาพเต็ม: โหลดภาพ, ซูม, พอดีหน้าต่าง, แพน, prefetch ภาพถัดไป
@MainActor
@Observable
final class ViewerController {
    /// อัตราซูม 1.0 = 100% (1 พิกเซลภาพ = 1 พิกเซลจอ)
    private(set) var zoom: CGFloat = 1
    private(set) var fitMode = true
    private(set) var isLoadingFull = false
    private(set) var pixelSize: CGSize = .zero

    /// ถูกเรียกเมื่อหมุนล้อเมาส์ขณะภาพพอดีจอ (+1 = ถัดไป, -1 = ก่อนหน้า)
    @ObservationIgnored var onNavigate: ((Int) -> Void)?

    @ObservationIgnored private weak var scrollView: ViewerScrollView?
    @ObservationIgnored private weak var imageView: NSImageView?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var gestureTargets: [GestureTarget] = []
    @ObservationIgnored private var currentURL: URL?
    @ObservationIgnored private var currentImage: NSImage?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var prefetching: Set<URL> = []
    @ObservationIgnored private var lastWheelNavigation = Date.distantPast
    private let fullCache: NSCache<NSURL, DecodedImage> = {
        let c = NSCache<NSURL, DecodedImage>()
        c.totalCostLimit = 900 * 1024 * 1024
        c.countLimit = 10
        return c
    }()

    private let minZoom: CGFloat = 0.02
    private let maxZoom: CGFloat = 32

    // MARK: - เชื่อมกับ NSScrollView

    func attach(scrollView sv: ViewerScrollView, imageView iv: NSImageView) {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        gestureTargets.removeAll()

        scrollView = sv
        imageView = iv
        sv.minMagnification = minZoom
        sv.maxMagnification = maxZoom
        sv.postsFrameChangedNotifications = true
        sv.onMouseWheel = { [weak self] event in
            self?.handleWheel(event) ?? false
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: sv, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleResize() }
        })
        observers.append(center.addObserver(forName: NSScrollView.willStartLiveMagnifyNotification, object: sv, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitMode = false }
        })
        observers.append(center.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: sv, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let sv = self.scrollView else { return }
                self.zoom = sv.magnification
            }
        })

        // ดับเบิลคลิก: สลับ พอดีจอ ↔ 100% ตรงจุดที่คลิก
        let doubleClickTarget = GestureTarget { [weak self] g in self?.handleDoubleClick(g) }
        let doubleClick = NSClickGestureRecognizer(target: doubleClickTarget, action: #selector(GestureTarget.fire(_:)))
        doubleClick.numberOfClicksRequired = 2
        sv.addGestureRecognizer(doubleClick)

        // ลากเพื่อเลื่อนภาพเมื่อซูมเข้า
        let panTarget = GestureTarget { [weak self] g in self?.handlePan(g) }
        let pan = NSPanGestureRecognizer(target: panTarget, action: #selector(GestureTarget.fire(_:)))
        sv.addGestureRecognizer(pan)

        gestureTargets = [doubleClickTarget, panTarget]

        if let currentImage { display(currentImage, pixelSize: pixelSize) }
    }

    private var backingScale: CGFloat {
        scrollView?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    // MARK: - โหลดภาพ

    func show(url: URL) {
        guard url != currentURL else { return }
        currentURL = url
        loadTask?.cancel()
        fitMode = true

        if let cached = fullCache.object(forKey: url as NSURL) {
            isLoadingFull = false
            display(cached.image, pixelSize: cached.pixelSize)
            return
        }

        // แสดงภาพย่อจากแคชก่อน (ขยายให้เท่าขนาดจริง) ระหว่างรอภาพเต็ม
        if let thumb = ThumbnailLoader.shared.bestCached(url),
           let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let px = ImageDecoder.pixelSize(of: url) {
            display(NSImage(cgImage: cg, size: px), pixelSize: px)
        } else {
            imageView?.image = nil
            currentImage = nil
        }

        isLoadingFull = true
        loadTask = Task { [weak self] in
            let decoded = await Task.detached(priority: .userInitiated) {
                ImageDecoder.loadFull(url: url)
            }.value
            guard let self, !Task.isCancelled, self.currentURL == url else { return }
            self.isLoadingFull = false
            if let decoded {
                self.fullCache.setObject(decoded, forKey: url as NSURL, cost: decoded.memoryCost)
                self.display(decoded.image, pixelSize: decoded.pixelSize)
            }
        }
    }

    /// ถอดรหัสภาพข้างเคียงล่วงหน้า ให้กดถัดไปแล้วขึ้นทันที
    func prefetch(_ urls: [URL]) {
        for url in urls where fullCache.object(forKey: url as NSURL) == nil && !prefetching.contains(url) {
            prefetching.insert(url)
            Task { [weak self] in
                let decoded = await Task.detached(priority: .utility) {
                    ImageDecoder.loadFull(url: url)
                }.value
                guard let self else { return }
                self.prefetching.remove(url)
                if let decoded {
                    self.fullCache.setObject(decoded, forKey: url as NSURL, cost: decoded.memoryCost)
                }
            }
        }
    }

    func reset() {
        loadTask?.cancel()
        currentURL = nil
        currentImage = nil
        imageView?.image = nil
        isLoadingFull = false
    }

    func forget(_ url: URL) {
        fullCache.removeObject(forKey: url as NSURL)
        if currentURL == url { currentURL = nil }
    }

    private func display(_ image: NSImage, pixelSize px: CGSize) {
        currentImage = image
        pixelSize = px
        guard let iv = imageView else { return }
        let scale = backingScale
        let logical = NSSize(width: max(1, px.width / scale), height: max(1, px.height / scale))
        image.size = logical
        iv.image = image
        iv.frame = NSRect(origin: .zero, size: logical)
        if fitMode { fit() }
    }

    // MARK: - ซูม

    func fit() {
        fitMode = true
        guard let sv = scrollView, let doc = sv.documentView else { return }
        let avail = sv.contentSize
        guard avail.width > 1, avail.height > 1, doc.frame.width > 0, doc.frame.height > 0 else { return }
        let scale = min(avail.width / doc.frame.width, avail.height / doc.frame.height)
        // ค่าเริ่มต้นไม่ขยายภาพเล็กเกินขนาดจริง (เปลี่ยนได้ในการตั้งค่า)
        let target = max(minZoom, AppSettings.shared.enlargeSmallImages ? scale : min(scale, 1.0))
        sv.setMagnification(target, centeredAt: NSPoint(x: doc.frame.midX, y: doc.frame.midY))
        zoom = target
    }

    func actualSize() { setZoom(1) }

    /// สลับ พอดีหน้าต่าง ↔ 100%
    func toggleFitActual() {
        if fitMode && zoom < 0.999 { actualSize() } else { fit() }
    }
    func zoomIn() { setZoom(zoom * 1.25) }
    func zoomOut() { setZoom(zoom / 1.25) }

    func setZoom(_ value: CGFloat, at point: NSPoint? = nil) {
        guard let sv = scrollView else { return }
        fitMode = false
        let target = max(minZoom, min(value, maxZoom))
        let bounds = sv.contentView.bounds
        let center = point ?? NSPoint(x: bounds.midX, y: bounds.midY)
        sv.setMagnification(target, centeredAt: center)
        zoom = target
    }

    func refit() {
        if fitMode { fit() }
    }

    /// ซูมโดยให้จุดใต้เมาส์อยู่ที่เดิม
    func zoomAround(_ value: CGFloat, keeping point: NSPoint) {
        guard let sv = scrollView else { return }
        fitMode = false
        let target = max(minZoom, min(value, maxZoom))
        let clip = sv.contentView
        let old = sv.magnification
        let offset = NSPoint(x: (point.x - clip.bounds.origin.x) * old, y: (point.y - clip.bounds.origin.y) * old)
        sv.magnification = target
        let origin = NSPoint(x: point.x - offset.x / target, y: point.y - offset.y / target)
        let constrained = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size))
        clip.scroll(to: constrained.origin)
        sv.reflectScrolledClipView(clip)
        zoom = target
    }

    private func handleWheel(_ event: NSEvent) -> Bool {
        guard let sv = scrollView, event.scrollingDeltaY != 0 else { return false }
        switch AppSettings.shared.wheelAction {
        case .zoom:
            guard let doc = sv.documentView else { return false }
            let point = doc.convert(event.locationInWindow, from: nil)
            zoomAround(zoom * (event.scrollingDeltaY > 0 ? 1.15 : 1 / 1.15), keeping: point)
            return true
        case .navigate:
            guard sv.isFitted else { return false }
            let now = Date()
            if now.timeIntervalSince(lastWheelNavigation) > 0.12 {
                lastWheelNavigation = now
                onNavigate?(event.scrollingDeltaY > 0 ? -1 : 1)
            }
            return true
        }
    }

    private func handleResize() {
        if fitMode { fit() }
    }

    private func handleDoubleClick(_ g: NSGestureRecognizer) {
        guard let doc = scrollView?.documentView else { return }
        if fitMode && zoom < 0.999 {
            setZoom(1, at: g.location(in: doc))
        } else {
            fit()
        }
    }

    private func handlePan(_ g: NSGestureRecognizer) {
        guard let pan = g as? NSPanGestureRecognizer, let sv = scrollView else { return }
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

// MARK: - AppKit helpers

/// เป้าหมาย target-action สำหรับ gesture recognizer
@MainActor
final class GestureTarget: NSObject {
    private let action: (NSGestureRecognizer) -> Void

    init(_ action: @escaping (NSGestureRecognizer) -> Void) {
        self.action = action
    }

    @objc func fire(_ sender: NSGestureRecognizer) {
        action(sender)
    }
}

/// จัดภาพให้อยู่กลางเมื่อภาพเล็กกว่าหน้าต่าง
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if rect.width > doc.frame.width {
            rect.origin.x = (doc.frame.width - rect.width) / 2
        }
        if rect.height > doc.frame.height {
            rect.origin.y = (doc.frame.height - rect.height) / 2
        }
        return rect
    }
}

/// NSScrollView ที่ส่งเหตุการณ์ล้อเมาส์ (ไม่ใช่ trackpad) ให้ controller ตัดสินใจก่อน
final class ViewerScrollView: NSScrollView {
    /// คืนค่า true ถ้าจัดการล้อเมาส์แล้ว
    var onMouseWheel: ((NSEvent) -> Bool)?

    override func scrollWheel(with event: NSEvent) {
        if !event.hasPreciseScrollingDeltas, let handler = onMouseWheel, handler(event) { return }
        super.scrollWheel(with: event)
    }

    /// ภาพทั้งภาพอยู่ในหน้าต่าง (ไม่มีส่วนให้เลื่อน)
    var isFitted: Bool {
        guard let doc = documentView else { return true }
        let w = doc.frame.width * magnification
        let h = doc.frame.height * magnification
        return w <= contentSize.width + 1 && h <= contentSize.height + 1
    }
}

extension ViewerScrollView {
    /// สร้าง scroll view + image view ที่ตั้งค่าพร้อมสำหรับดูภาพ (ใช้ทั้งโหมดดูภาพและเทียบภาพ)
    static func makeImageScrollView() -> (ViewerScrollView, NSImageView) {
        let scrollView = ViewerScrollView()
        let clip = CenteringClipView()
        clip.drawsBackground = false
        scrollView.contentView = clip
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.allowsMagnification = true
        scrollView.borderType = .noBorder

        let imageView = NSImageView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageFrameStyle = .none
        imageView.animates = true
        imageView.isEditable = false
        imageView.allowsCutCopyPaste = false
        scrollView.documentView = imageView
        return (scrollView, imageView)
    }
}
