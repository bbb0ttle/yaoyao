import SwiftUI
import MetalKit

/// Renders the Zig framebuffer through Metal as a full-screen textured quad.
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
            ZCanvasBridge.shared.resize(width: UInt32(size.width), height: UInt32(size.height))
            lastSize = size
            texture = nil // Recreate on next draw
        }

        func draw(in view: MTKView) {
            let bridge = ZCanvasBridge.shared
            bridge.updateFrame(dpr: Float(view.contentScaleFactor))

            guard let ptr = bridge.framebufferPtr,
                  let pipelineState = pipelineState,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }

            let width = Int(bridge.width)
            let height = Int(bridge.height)
            guard width > 0, height > 0 else {
                encoder.endEncoding()
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
                commandBuffer.commit()
                return
            }

            // Lazily recreate the texture when the framebuffer size changes.
            if texture == nil || texture!.width != width || texture!.height != height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba8Unorm,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                descriptor.usage = .shaderRead
                descriptor.storageMode = .shared
                texture = device.makeTexture(descriptor: descriptor)
            }

            guard let texture = texture else {
                encoder.endEncoding()
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
                commandBuffer.commit()
                return
            }

            // Upload the Zig framebuffer into the Metal texture.
            let region = MTLRegionMake2D(0, 0, width, height)
            texture.replace(region: region, mipmapLevel: 0, withBytes: ptr, bytesPerRow: width * 4)

            // Draw a full-screen quad.
            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()

            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }
            commandBuffer.commit()
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let point = gesture.location(in: view)
            let scale = view.contentScaleFactor
            ZCanvasBridge.shared.triggerMeteorShower(at: CGPoint(x: point.x * scale, y: point.y * scale))
        }
    }
}
