import CoreGraphics

/// ฮิสโตแกรม RGB (ค่าแต่ละช่อง normalize เป็น 0...1)
struct Histogram {
    var red: [Float]
    var green: [Float]
    var blue: [Float]

    static func compute(from image: CGImage) -> Histogram? {
        let side = 256
        let bytesPerRow = side * 4
        var r = [Float](repeating: 0, count: 256)
        var g = [Float](repeating: 0, count: 256)
        var b = [Float](repeating: 0, count: 256)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)

        let ok: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return nil }

        var i = 0
        while i < pixels.count {
            r[Int(pixels[i])] += 1
            g[Int(pixels[i + 1])] += 1
            b[Int(pixels[i + 2])] += 1
            i += 4
        }

        // ใช้ค่าสูงสุดช่วงกลาง (ตัดปลายสุด 0/255 ที่มักพุ่งสูง) เป็นตัวหาร เพื่อให้กราฟอ่านง่าย
        let peak = max(r[1...254].max() ?? 1, g[1...254].max() ?? 1, b[1...254].max() ?? 1, 1)
        func norm(_ a: [Float]) -> [Float] { a.map { min($0 / peak, 1) } }
        return Histogram(red: norm(r), green: norm(g), blue: norm(b))
    }
}
