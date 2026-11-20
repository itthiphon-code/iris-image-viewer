import Foundation

/// เฝ้าดูโฟลเดอร์ เมื่อมีไฟล์เพิ่ม/ลบ/เปลี่ยนชื่อ จะเรียก onChange (หน่วงเวลาเล็กน้อยเพื่อรวมหลายเหตุการณ์)
@MainActor
final class FolderWatcher {
    var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private(set) var watchedPath: String?

    func watch(_ url: URL?) {
        guard url?.path != watchedPath || source == nil else { return }
        stop()
        guard let url else { return }

        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .link],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.schedule() }
        }
        src.setCancelHandler {
            close(fd)
        }
        src.resume()
        source = src
        watchedPath = url.path
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        watchedPath = nil
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
}
