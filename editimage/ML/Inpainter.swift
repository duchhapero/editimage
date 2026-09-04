//
//  Inpainter.swift
//  editimage
//
//  Xoá vật thể (inpainting). Ưu tiên model LaMa (Core ML) nếu được kèm trong bundle
//  ("LaMa.mlmodelc"); nếu chưa có, dùng fallback xấp xỉ bằng Core Image để demo vẫn chạy.
//
//  Cách thêm model thật (offline, ~200MB): convert LaMa sang Core ML rồi kéo file
//  LaMa.mlpackage vào target. Wrapper sẽ tự phát hiện và dùng.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreML
import Vision

final class Inpainter {
    static let shared = Inpainter()
    private init() {}

    /// Có model LaMa thật hay không.
    var hasNeuralModel: Bool { LaMaModel.shared.isAvailable }

    /// Xoá vùng được đánh dấu trắng trong `mask` khỏi `image`.
    func inpaint(image: CIImage, mask: CIImage) throws -> CIImage {
        if hasNeuralModel {
            do {
                return try LaMaModel.shared.inpaint(image: image, mask: mask)
            } catch {
                // Model lỗi/không khớp I/O -> vẫn cho ra kết quả bằng fallback.
                print("⚠️ LaMa inference lỗi, dùng fallback: \(error)")
                return approximateInpaint(image: image, mask: mask)
            }
        }
        return approximateInpaint(image: image, mask: mask)
    }

    // MARK: - Fallback xấp xỉ (Core Image, không cần model)

    /// Lấp vùng mask bằng nội dung xung quanh đã làm mờ mạnh + feather viền.
    /// Không hoàn hảo như LaMa nhưng đủ để demo "xoá vật thể" offline tức thì.
    private func approximateInpaint(image: CIImage, mask: CIImage) -> CIImage {
        let extent = image.extent

        // Làm mờ mạnh toàn ảnh để "trải" màu xung quanh vào vùng cần xoá.
        let smeared = image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(extent.width, extent.height) * 0.03])
            .cropped(to: extent)

        // Feather mask để ghép mềm viền.
        let softMask = mask
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 6])
            .cropped(to: extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = smeared      // nội dung lấp
        blend.backgroundImage = image   // giữ phần ngoài mask
        blend.maskImage = softMask
        return (blend.outputImage ?? image).cropped(to: extent)
    }
}
