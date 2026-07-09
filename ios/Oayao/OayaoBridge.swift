import Foundation
import Metal

/// Thin Swift wrapper around the Zig C exports in `oayao.h`.
/// Zig renders directly into a shared MTLBuffer, eliminating the
/// per-frame CPU→GPU framebuffer copy.
///
/// Double-buffered to prevent GPU-CPU data races: Zig writes to one buffer
/// while the GPU blits from the other.
final class OayaoBridge {
    static let shared = OayaoBridge()

    private let start = Date()
    private let device = MTLCreateSystemDefaultDevice()!
    private let maxBuffers = 2

    private var buffers: [MTLBuffer] = []
    private(set) var width: UInt32 = 0
    private(set) var height: UInt32 = 0
    private(set) var bytesPerRow: UInt32 = 0
    private var frameIndex: Int = 0

    private init() {}

    /// The buffer that Zig should write to for the current frame.
    var currentBuffer: MTLBuffer? {
        guard !buffers.isEmpty else { return nil }
        return buffers[frameIndex % buffers.count]
    }

    /// Returns the buffer for the current frame and advances to the next.
    /// The returned buffer will not be touched by the GPU until the
    /// command buffer referencing it has completed.
    func nextBuffer() -> MTLBuffer? {
        guard !buffers.isEmpty else { return nil }
        let buf = buffers[frameIndex % buffers.count]
        frameIndex = (frameIndex + 1) % buffers.count
        return buf
    }

    func resize(width: UInt32, height: UInt32) {
        guard width > 0, height > 0 else { return }
        let bpr = width * 4
        let length = Int(height * bpr)
        self.width = width
        self.height = height
        self.bytesPerRow = bpr
        self.frameIndex = 0
        self.buffers.removeAll()

        for _ in 0..<maxBuffers {
            guard let buf = device.makeBuffer(length: length, options: .storageModeShared) else {
                return
            }
            buffers.append(buf)
        }

        // Point Zig at the first buffer.
        guard let first = buffers.first else { return }
        let ptr = first.contents().assumingMemoryBound(to: UInt8.self)
        oy_resize_with_buffer(ptr, width, height, bpr)
    }

    /// Points Zig's framebuffer at the given buffer for the next frame.
    func bindBuffer(_ buf: MTLBuffer) {
        let ptr = buf.contents().assumingMemoryBound(to: UInt8.self)
        oy_set_buffer(ptr)
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
