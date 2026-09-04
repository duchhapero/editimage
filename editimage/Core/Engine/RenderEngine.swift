//
//  RenderEngine.swift
//  editimage
//
//  Trái tim của app: 1 CIContext chạy trên Metal, render CIImage ra MTKView
//  (preview real-time) và ra bitmap (export). Color-managed, dùng chung toàn app.
//

import CoreImage
import Metal
import MetalKit
import UIKit

/// Engine render dùng chung. Giữ Metal device + CIContext, chịu trách nhiệm vẽ.
final class RenderEngine {
    static let shared = RenderEngine()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let ciContext: CIContext

    /// Không gian màu đầu ra cho preview trên màn hình (Display P3).
    private let displayColorSpace = CGColorSpace(name: CGColorSpace.displayP3)
        ?? CGColorSpaceCreateDeviceRGB()

    private init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal không khả dụng trên thiết bị này")
        }
        self.device = device
        self.commandQueue = queue

        // Working space tuyến tính (extended linear sRGB) để chỉnh sáng/tối đúng vật lý;
        // xuất ra Display P3. Bật downsample chất lượng cao.
        let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        self.ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: workingSpace,
            .cacheIntermediates: true,
            .highQualityDownsample: true,
        ])
    }

    /// Vẽ 1 CIImage vào drawable của MTKView, aspect-fit + nền đen.
    func draw(image: CIImage?, in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let drawableSize = view.drawableSize
        let destination = CIRenderDestination(
            width: Int(drawableSize.width),
            height: Int(drawableSize.height),
            pixelFormat: view.colorPixelFormat,
            commandBuffer: commandBuffer,
            mtlTextureProvider: { drawable.texture }
        )
        destination.colorSpace = displayColorSpace
        // Core Image gốc bottom-left, MTKView top-left -> lật để hiển thị đúng chiều.
        destination.isFlipped = true

        // Nền đen phủ kín drawable (tránh nhiễu khi ảnh không lấp đầy).
        let background = CIImage(color: .black)
            .cropped(to: CGRect(origin: .zero, size: drawableSize))

        let content: CIImage
        if let image {
            content = fitted(image, into: drawableSize).composited(over: background)
        } else {
            content = background
        }

        do {
            try ciContext.startTask(toRender: content, to: destination)
        } catch {
            print("⚠️ RenderEngine draw error: \(error)")
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Scale + center ảnh để vừa khít drawable (aspect-fit).
    private func fitted(_ image: CIImage, into size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = min(size.width / extent.width, size.height / extent.height)
        let scaledWidth = extent.width * scale
        let scaledHeight = extent.height * scale
        let tx = (size.width - scaledWidth) / 2 - extent.origin.x * scale
        let ty = (size.height - scaledHeight) / 2 - extent.origin.y * scale
        return image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: tx, y: ty))
    }

    /// Render CIImage ra UIImage (dùng cho thumbnail filter, chia sẻ...).
    func uiImage(from image: CIImage, maxDimension: CGFloat? = nil) -> UIImage? {
        var img = image
        if let maxDimension {
            img = downscaled(img, maxDimension: maxDimension)
        }
        let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard let cg = ciContext.createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: space) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    /// Giảm kích thước ảnh xuống trần cạnh dài (dùng cho preview / vùng ML).
    func downscaled(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let extent = image.extent
        let longest = max(extent.width, extent.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let filter = CIFilter(name: "CILanczosScaleTransform")!
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        return filter.outputImage ?? image
    }
}
