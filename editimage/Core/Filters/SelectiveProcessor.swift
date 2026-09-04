//
//  SelectiveProcessor.swift
//  editimage
//
//  Chỉnh sửa cục bộ: áp bộ chỉnh trong vùng mask (tròn / dải / cọ) rồi trộn mềm
//  lên ảnh gốc bằng CIBlendWithMask.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum SelectiveProcessor {
    static func apply(_ masks: [SelectiveMask], to image: CIImage) -> CIImage {
        guard !masks.isEmpty else { return image }
        let extent = image.extent
        guard extent.width > 0 else { return image }

        var result = image
        for mask in masks where !mask.adjust.isIdentity {
            let adjusted = applyLocal(mask.adjust, to: result)
            guard let maskImage = maskImage(for: mask.shape, extent: extent, inverted: mask.inverted) else { continue }
            let blend = CIFilter.blendWithMask()
            blend.inputImage = adjusted
            blend.backgroundImage = result
            blend.maskImage = maskImage
            result = (blend.outputImage ?? result).cropped(to: extent)
        }
        return result
    }

    // MARK: - Local adjust

    private static func applyLocal(_ a: LocalAdjust, to input: CIImage) -> CIImage {
        var image = input
        if a.exposure != 0 {
            let f = CIFilter.exposureAdjust(); f.inputImage = image; f.ev = Float(a.exposure)
            image = f.outputImage ?? image
        }
        if a.contrast != 1 || a.saturation != 1 {
            let f = CIFilter.colorControls()
            f.inputImage = image; f.contrast = Float(a.contrast); f.saturation = Float(a.saturation)
            image = f.outputImage ?? image
        }
        if a.temperature != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - CGFloat(a.temperature) * 2500, y: 0)
            image = f.outputImage ?? image
        }
        if a.sharpness != 0 {
            let f = CIFilter.sharpenLuminance(); f.inputImage = image; f.sharpness = Float(a.sharpness)
            image = f.outputImage ?? image
        }
        return image
    }

    // MARK: - Mask generation (trắng = vùng tác động)

    static func maskImage(for shape: MaskShape, extent: CGRect, inverted: Bool) -> CIImage? {
        let base: CIImage
        switch shape {
        case .radial(let center, let radius, let feather):
            let c = point(center, in: extent)
            let minDim = min(extent.width, extent.height)
            let outer = max(radius, 0.02) * minDim
            let inner = outer * (1 - min(max(feather, 0.05), 0.95))
            let g = CIFilter.radialGradient()
            g.center = c
            g.radius0 = Float(inner)
            g.radius1 = Float(outer)
            g.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            g.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            base = (g.outputImage ?? CIImage(color: .black)).cropped(to: extent)

        case .linear(let start, let end):
            let g = CIFilter.linearGradient()
            g.point0 = point(start, in: extent)
            g.point1 = point(end, in: extent)
            g.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            g.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            base = (g.outputImage ?? CIImage(color: .black)).cropped(to: extent)

        case .brush(let png):
            guard let ui = UIImage(data: png), let cg = ui.cgImage else { return nil }
            var ci = CIImage(cgImage: cg)
            let sx = extent.width / ci.extent.width
            let sy = extent.height / ci.extent.height
            ci = ci.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            base = ci.transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
        }

        guard inverted else { return base }
        return base.applyingFilter("CIColorInvert")
    }

    /// Toạ độ chuẩn hoá (gốc trên-trái) -> CGPoint (gốc dưới-trái của Core Image).
    private static func point(_ p: CGPoint, in extent: CGRect) -> CGPoint {
        CGPoint(x: extent.origin.x + p.x * extent.width,
                y: extent.origin.y + (1 - p.y) * extent.height)
    }
}
