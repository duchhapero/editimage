//
//  AIProcessor.swift
//  editimage
//
//  "Bake" một chuỗi AIOp lên CIImage. Dùng cho cả preview (độ phân giải thấp)
//  lẫn export (full-res). Chạy nền, có thể ném lỗi để UI hiển thị.
//

import CoreImage
import UIKit

enum AIProcessor {

    /// Áp lần lượt các AIOp lên ảnh nguồn.
    static func bake(_ ops: [AIOp], onto source: CIImage) throws -> CIImage {
        var image = source
        for op in ops {
            image = try apply(op, to: image)
        }
        return image
    }

    static func apply(_ op: AIOp, to image: CIImage) throws -> CIImage {
        switch op {
        case .removeBackground(let fill):
            return try AIService.removeBackground(from: image, fill: fill)

        case .bokeh(let intensity):
            return try AIService.bokeh(for: image, intensity: intensity)

        case .inpaint(let maskPNG):
            guard let mask = maskImage(from: maskPNG, targetExtent: image.extent) else {
                throw AIError.maskFailed
            }
            return try Inpainter.shared.inpaint(image: image, mask: mask)
        }
    }

    /// Chuyển mask PNG (toạ độ trên-trái, trắng = vùng tác động) sang CIImage khớp ảnh.
    private static func maskImage(from png: Data, targetExtent: CGRect) -> CIImage? {
        guard let ui = UIImage(data: png), let cg = ui.cgImage else { return nil }
        var ci = CIImage(cgImage: cg)
        // PNG được vẽ theo toạ độ ảnh full nên chỉ cần scale khớp extent.
        let sx = targetExtent.width / ci.extent.width
        let sy = targetExtent.height / ci.extent.height
        if abs(sx - 1) > 0.001 || abs(sy - 1) > 0.001 {
            ci = ci.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }
        return ci.transformed(by: CGAffineTransform(translationX: targetExtent.origin.x,
                                                    y: targetExtent.origin.y))
    }
}
