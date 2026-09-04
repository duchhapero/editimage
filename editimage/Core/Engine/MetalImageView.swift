//
//  MetalImageView.swift
//  editimage
//
//  SwiftUI wrapper cho MTKView. Vẽ theo yêu cầu (on-demand) để tiết kiệm pin:
//  chỉ render lại khi ảnh thay đổi, không chạy vòng lặp 60fps liên tục.
//

import SwiftUI
import MetalKit

struct MetalImageView: UIViewRepresentable {
    /// Ảnh (đã qua edit graph) cần hiển thị.
    let image: CIImage?
    /// Engine render dùng chung.
    var engine: RenderEngine = .shared

    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: engine.device)
        view.delegate = context.coordinator
        view.framebufferOnly = false          // CIRenderDestination cần ghi vào texture
        view.colorPixelFormat = .bgra8Unorm
        view.enableSetNeedsDisplay = true      // vẽ theo yêu cầu
        view.isPaused = true                   // không auto-loop
        view.autoResizeDrawable = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.isOpaque = true
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.image = image
        uiView.setNeedsDisplay()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let engine: RenderEngine
        var image: CIImage?

        init(engine: RenderEngine) {
            self.engine = engine
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            view.setNeedsDisplay()
        }

        func draw(in view: MTKView) {
            engine.draw(image: image, in: view)
        }
    }
}
