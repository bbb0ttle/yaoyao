import Foundation
import Metal

/// Thin Swift wrapper around the Zig C exports in `oayao.h`.
/// Zig renders directly into a shared MTLBuffer, eliminating the
/// per-frame CPU→GPU framebuffer copy.
final class OayaoBridge {
    static let shared = OayaoBridge()

    private let start = Date()
    private let device = MTLCreateSystemDefaultDevice()!

    /// MTLBuffer that Zig writes into. Owned by Swift, shared with Metal.
    private(set) var buffer: MTLBuffer?
    private(set) var width: UInt32 = 0
    private(set) var height: UInt32 = 0
    private(set) var bytesPerRow: UInt32 = 0

    private init() {}

    func resize(width: UInt32, height: UInt32) {
        guard width > 0, height > 0 else { return }
        let bpr = width * 4
        let length = Int(height * bpr)
        guard let newBuffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            return
        }
        self.buffer = newBuffer
        self.width = width
        self.height = height
        self.bytesPerRow = bpr

        let ptr = newBuffer.contents().assumingMemoryBound(to: UInt8.self)
        oy_resize_with_buffer(ptr, width, height, bpr)
    }

    /// Pointer to the first byte of the RGBA8 framebuffer in the shared MTLBuffer.
    var framebufferPtr: UnsafeMutablePointer<UInt8>? {
        guard let buf = buffer else { return nil }
        return buf.contents().assumingMemoryBound(to: UInt8.self)
    }

    func updateFrame(dpr: Float) {
        let elapsed = Float(Date().timeIntervalSince(start))
        let unixMs = Date().timeIntervalSince1970 * 1000
        oy_update_frame(elapsed, unixMs, dpr)
    }

    func triggerMeteorShower(at point: CGPoint) {
        oy_show_meteor_shower(Float(point.x), Float(point.y))
    }
}
