import SwiftUI
import MetalKit
import QuartzCore

/// Renders the Zig framebuffer through Metal as a full-screen textured quad.
/// Zig writes directly into a shared MTLBuffer; a GPU blit encoder copies
/// buffer → texture, eliminating the per-frame CPU memcpy.
struct CanvasView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let device = MTLCreateSystemDefaultDevice()!
        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.autoResizeDrawable = true
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 60
        mtkView.colorPixelFormat = .rgba8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        let coordinator = context.coordinator
        coordinator.mtkView = mtkView
        mtkView.delegate = coordinator

        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        mtkView.addGestureRecognizer(tap)

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        weak var mtkView: MTKView?

        private let device: MTLDevice
        private let commandQueue: MTLCommandQueue
        private var pipelineState: MTLRenderPipelineState?
        private var texture: MTLTexture?
        private var lastSize: CGSize = .zero

        // Temporary performance instrumentation.
        private var perfFrameCount = 0
        private var perfAccumUpdate: Double = 0
        private var perfAccumBlit: Double = 0
        private var perfAccumTotal: Double = 0
        private let perfLogInterval = 60

        override init() {
            self.device = MTLCreateSystemDefaultDevice()!
            self.commandQueue = device.makeCommandQueue()!
            super.init()
            buildPipelineState()
        }

        private func buildPipelineState() {
            guard let library = device.makeDefaultLibrary() else { return }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertexShader")
            descriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")
            descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                print("Failed to create pipeline state: \(error)")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            guard size.width > 0, size.height > 0 else { return }
            OayaoBridge.shared.resize(width: UInt32(size.width), height: UInt32(size.height))
            lastSize = size
            texture = nil
        }

        func draw(in view: MTKView) {
            let t0 = CACurrentMediaTime()
            let bridge = OayaoBridge.shared
            bridge.updateFrame(dpr: Float(view.contentScaleFactor))
            let t1 = CACurrentMediaTime()

            guard let buffer = bridge.buffer,
                  let pipelineState = pipelineState,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }

            let width = Int(bridge.width)
            let height = Int(bridge.height)
            guard width > 0, height > 0 else { return }

            // Lazy-create the GPU-private blit-target texture.
            if texture == nil || texture!.width != width || texture!.height != height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba8Unorm,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                descriptor.storageMode = .private
                descriptor.usage = [.shaderRead, .shaderWrite]
                texture = device.makeTexture(descriptor: descriptor)
            }

            guard let texture = texture else { return }

            // GPU blit: shared buffer → private texture (DMA, no CPU memcpy).
            if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                blitEncoder.copy(
                    from: buffer,
                    sourceOffset: 0,
                    sourceBytesPerRow: Int(bridge.bytesPerRow),
                    sourceBytesPerImage: Int(bridge.height * bridge.bytesPerRow),
                    sourceSize: MTLSize(width: width, height: height, depth: 1),
                    to: texture,
                    destinationSlice: 0,
                    destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                )
                blitEncoder.endEncoding()
            }
            let t2 = CACurrentMediaTime()

            // Draw a full-screen quad.
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()

            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }
            commandBuffer.commit()
            let t3 = CACurrentMediaTime()

            perfFrameCount += 1
            perfAccumUpdate += t1 - t0
            perfAccumBlit += t2 - t1
            perfAccumTotal += t3 - t0
            if perfFrameCount >= perfLogInterval {
                let n = Double(perfFrameCount)
                NSLog(String(format: "[DEBUG-perf] avg over %d frames: update=%.2f ms, blit=%.2f ms, total CPU=%.2f ms",
                             perfFrameCount, perfAccumUpdate / n * 1000, perfAccumBlit / n * 1000, perfAccumTotal / n * 1000))
                perfFrameCount = 0
                perfAccumUpdate = 0
                perfAccumBlit = 0
                perfAccumTotal = 0
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let point = gesture.location(in: view)
            let scale = view.contentScaleFactor
            OayaoBridge.shared.triggerMeteorShower(at: CGPoint(x: point.x * scale, y: point.y * scale))
        }
    }
}
