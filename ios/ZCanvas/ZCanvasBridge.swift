import Foundation

/// Thin Swift wrapper around the Zig C exports in `z_canvas.h`.
/// The Zig side owns a single RGBA8 framebuffer; this class reads from it
/// and forwards lifecycle/rendering/touch events.
final class ZCanvasBridge {
    static let shared = ZCanvasBridge()

    private let start = Date()

    private init() {
        zc_init()
    }

    /// Pointer to the first byte of the RGBA8 framebuffer, or `nil` if not allocated.
    var framebufferPtr: UnsafeMutablePointer<UInt8>? {
        let p = zc_get_framebuffer_ptr()
        return p == 0 ? nil : UnsafeMutablePointer<UInt8>(bitPattern: p)
    }

    var width: UInt32 { zc_get_width() }
    var height: UInt32 { zc_get_height() }

    func resize(width: UInt32, height: UInt32) {
        zc_resize(width, height)
    }

    func updateFrame(dpr: Float) {
        let elapsed = Float(Date().timeIntervalSince(start))
        let unixMs = Date().timeIntervalSince1970 * 1000
        zc_update_frame(elapsed, unixMs, dpr)
    }

    func triggerMeteorShower(at point: CGPoint) {
        zc_show_meteor_shower(Float(point.x), Float(point.y))
    }
}
