//
//  AIService.swift
//  editimage
//
//  Các tác vụ ML on-device dựa trên Vision (chạy offline, không cần model kèm app):
//   - Tách chủ thể (subject lifting, class-agnostic) — iOS 17+.
//   - Segmentation người cho bokeh.
//

import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum AIError: LocalizedError {
    case noSubject
    case maskFailed
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .noSubject:       return "Không phát hiện được chủ thể trong ảnh."
        case .maskFailed:      return "Không tạo được mặt nạ."
        case .modelUnavailable: return "Chưa có model AI xoá vật thể (LaMa)."
        }
    }
}

enum AIService {

    // MARK: - Subject lifting (tách chủ thể)

    /// Trả mặt nạ chủ thể (trắng = chủ thể) ở đúng độ phân giải ảnh nguồn.
    static func foregroundMask(for image: CIImage) throws -> CIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw AIError.noSubject
        }
        let buffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        return CIImage(cvPixelBuffer: buffer)
    }

    /// Tách nền: giữ chủ thể, thay nền theo `fill`.
    static func removeBackground(from image: CIImage, fill: BackgroundFill) throws -> CIImage {
        let mask = try foregroundMask(for: image)
        let background: CIImage
        switch fill {
        case .transparent:
            background = CIImage(color: .clear).cropped(to: image.extent)
        case .color(let hex):
            let ci = CIColor(color: UIColor(hex: hex) ?? .white)
            background = CIImage(color: ci).cropped(to: image.extent)
        }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = background
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: image.extent)
    }

    // MARK: - Bokeh (xoá phông chân dung)

    /// Làm mờ hậu cảnh, giữ nét người. intensity 0...1 -> bán kính blur.
    static func bokeh(for image: CIImage, intensity: Double) throws -> CIImage {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try handler.perform([request])
        guard let buffer = request.results?.first?.pixelBuffer else { throw AIError.noSubject }

        var mask = CIImage(cvPixelBuffer: buffer)
        // Scale mask (thường nhỏ hơn) khớp ảnh gốc.
        let sx = image.extent.width / mask.extent.width
        let sy = image.extent.height / mask.extent.height
        mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .cropped(to: image.extent)

        let radius = 4 + intensity * 26
        let blurred = image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: image.extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = image          // nét (người)
        blend.backgroundImage = blurred   // mờ (hậu cảnh)
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: image.extent)
    }
}
