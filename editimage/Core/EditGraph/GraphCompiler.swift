//
//  GraphCompiler.swift
//  editimage
//
//  Compile EditGraph -> chuỗi CIFilter áp lên CIImage nguồn (đã qua AI bake nếu có).
//  Thứ tự: geometry -> tone -> color -> chi tiết -> LUT -> effect -> text.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum GraphCompiler {

    /// Áp toàn bộ graph. Trả ảnh kết quả (lazy CIImage, chưa render GPU).
    /// `includeOverlays`: preview để false (ảnh chồng & chữ vẽ bằng overlay SwiftUI
    /// WYSIWYG), export/thumbnail để true (bake vào ảnh).
    static func apply(_ graph: EditGraph, to source: CIImage?, includeOverlays: Bool = true) -> CIImage? {
        guard let source else { return nil }
        var image = source

        image = applyGeometry(graph.geometry, to: image)
        image = RetouchProcessor.apply(graph.retouch, to: image)
        image = applyAdjustments(graph.adjustments, to: image)
        image = CurveProcessor.apply(graph.curves, to: image)
        image = HSLProcessor.apply(graph.hsl, to: image)
        image = LUTEngine.apply(presetID: graph.lutID, intensity: graph.lutIntensity, to: image)
        image = SelectiveProcessor.apply(graph.masks, to: image)
        image = applyEffects(graph.adjustments, to: image)
        if includeOverlays {
            image = applyImageLayers(graph.imageLayers, to: image)
            image = applyText(graph.textLayers, to: image)
        }

        return image
    }

    // MARK: - Image layers (ảnh chồng)

    static func applyImageLayers(_ layers: [ImageLayer], to input: CIImage) -> CIImage {
        guard !layers.isEmpty else { return input }
        let extent = input.extent
        guard extent.width > 0, extent.height > 0 else { return input }

        var result = input
        for layer in layers {
            guard let overlay = makeOverlay(layer, baseExtent: extent) else { continue }
            result = composite(overlay, over: result, blend: layer.blend, extent: extent)
        }
        return result.cropped(to: extent)
    }

    private static func makeOverlay(_ layer: ImageLayer, baseExtent ext: CGRect) -> CIImage? {
        guard var img = CIImage(data: layer.imageData, options: [.applyOrientationProperty: true]),
              img.extent.width > 0 else { return nil }

        // Scale theo bề rộng ảnh nền.
        let targetWidth = max(layer.scale, 0.01) * ext.width
        let s = targetWidth / img.extent.width
        img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))

        // Xoay quanh tâm.
        if abs(layer.rotation) > 0.01 {
            let e = img.extent
            let toCenter = CGAffineTransform(translationX: -e.midX, y: -e.midY)
            let rotate = CGAffineTransform(rotationAngle: -CGFloat(layer.rotation) * .pi / 180)
            let back = CGAffineTransform(translationX: e.midX, y: e.midY)
            img = img.transformed(by: toCenter.concatenating(rotate).concatenating(back))
        }

        // Độ mờ.
        if layer.opacity < 0.999 {
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(layer.opacity)),
            ])
        }

        // Đưa tâm lớp tới vị trí đích (gốc trên-trái chuẩn hoá -> CI gốc dưới-trái).
        let e = img.extent
        let cx = ext.origin.x + layer.position.x * ext.width
        let cy = ext.origin.y + (1 - layer.position.y) * ext.height
        img = img.transformed(by: CGAffineTransform(translationX: cx - e.midX, y: cy - e.midY))
        return img
    }

    private static func composite(_ overlay: CIImage, over background: CIImage,
                                  blend: BlendKind, extent: CGRect) -> CIImage {
        guard let name = blend.ciFilterName, let filter = CIFilter(name: name) else {
            return overlay.composited(over: background).cropped(to: extent)
        }
        filter.setValue(overlay, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        return (filter.outputImage ?? background).cropped(to: extent)
    }

    // MARK: - Geometry

    static func applyGeometry(_ g: Geometry, to input: CIImage) -> CIImage {
        var image = input
        let originalExtent = image.extent

        // Flip
        if g.flipH {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
                .transformed(by: CGAffineTransform(translationX: image.extent.width, y: 0))
        }
        if g.flipV {
            image = image.transformed(by: CGAffineTransform(scaleX: 1, y: -1))
                .transformed(by: CGAffineTransform(translationX: 0, y: image.extent.height))
        }

        // Xoay 90° * quarterTurns
        if g.quarterTurns % 4 != 0 {
            let angle = -CGFloat(g.quarterTurns) * .pi / 2
            image = image.transformed(by: CGAffineTransform(rotationAngle: angle))
            image = normalizeOrigin(image)
        }

        // Straighten (xoay tự do quanh tâm) + crop lại phần đen
        if abs(g.straighten) > 0.01 {
            let angle = CGFloat(g.straighten) * .pi / 180
            let ext = image.extent
            let center = CGAffineTransform(translationX: -ext.midX, y: -ext.midY)
            let rotate = CGAffineTransform(rotationAngle: angle)
            let back = CGAffineTransform(translationX: ext.midX, y: ext.midY)
            image = image.transformed(by: center.concatenating(rotate).concatenating(back))
            image = image.cropped(to: ext)   // giữ khung cũ (đơn giản cho demo)
        }

        // Crop theo rect chuẩn hoá (trên hệ toạ độ hiện tại)
        if g.cropRect != CGRect(x: 0, y: 0, width: 1, height: 1) {
            let ext = image.extent
            let crop = CGRect(
                x: ext.origin.x + g.cropRect.origin.x * ext.width,
                y: ext.origin.y + (1 - g.cropRect.origin.y - g.cropRect.height) * ext.height,
                width: g.cropRect.width * ext.width,
                height: g.cropRect.height * ext.height
            )
            image = image.cropped(to: crop)
            image = normalizeOrigin(image)
        }

        _ = originalExtent
        return image
    }

    /// Đưa origin của ảnh về (0,0) để các bước sau tính toạ độ nhất quán.
    private static func normalizeOrigin(_ image: CIImage) -> CIImage {
        let ext = image.extent
        guard ext.origin != .zero else { return image }
        return image.transformed(by: CGAffineTransform(translationX: -ext.origin.x, y: -ext.origin.y))
    }

    // MARK: - Adjustments (tone + color + detail)

    static func applyAdjustments(_ a: Adjustments, to input: CIImage) -> CIImage {
        var image = input

        // Exposure
        if a.exposure != 0 {
            let f = CIFilter.exposureAdjust(); f.inputImage = image; f.ev = Float(a.exposure)
            image = f.outputImage ?? image
        }

        // Highlights / Shadows
        if a.highlights != 0 || a.shadows != 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = image
            f.radius = 3
            // highlightAmount: 0...1, 1 = gốc; giảm để tối vùng sáng.
            f.highlightAmount = Float(min(max(1 + a.highlights, 0.3), 1))
            // shadowAmount: -1...1, >0 nâng sáng vùng tối.
            f.shadowAmount = Float(max(min(a.shadows, 1), -1))
            image = f.outputImage ?? image
        }

        // Brightness / Contrast / Saturation
        if a.brightness != 0 || a.contrast != 1 || a.saturation != 1 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.brightness = Float(a.brightness)
            f.contrast = Float(a.contrast)
            f.saturation = Float(a.saturation)
            image = f.outputImage ?? image
        }

        // Temperature / Tint
        if a.temperature != 0 || a.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - CGFloat(a.temperature) * 2500,
                                       y: CGFloat(a.tint) * 80)
            image = f.outputImage ?? image
        }

        // Vibrance
        if a.vibrance != 0 {
            let f = CIFilter.vibrance(); f.inputImage = image; f.amount = Float(a.vibrance)
            image = f.outputImage ?? image
        }

        // Clarity (local contrast qua unsharp mask bán kính lớn)
        if a.clarity != 0 {
            let f = CIFilter.unsharpMask()
            f.inputImage = image
            f.radius = 2.5
            f.intensity = Float(a.clarity)
            image = f.outputImage ?? image
        }

        // Sharpness
        if a.sharpness != 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = image
            f.sharpness = Float(a.sharpness)
            image = f.outputImage ?? image
        }

        return image
    }

    // MARK: - Effects (vignette + grain) — áp sau LUT

    static func applyEffects(_ a: Adjustments, to input: CIImage) -> CIImage {
        var image = input

        if a.vignette > 0 {
            let f = CIFilter.vignette()
            f.inputImage = image
            f.intensity = Float(a.vignette * 2)
            f.radius = 1.5
            image = f.outputImage ?? image
        }

        if a.grain > 0 {
            let extent = image.extent
            let noise = CIFilter.randomGenerator().outputImage?.cropped(to: extent)
            if let noise {
                // Chuyển noise sang xám + alpha thấp rồi phủ lên ảnh.
                let gray = noise.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0.4, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0.4, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0.4, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(a.grain) * 0.18),
                    "inputBiasVector": CIVector(x: 0.2, y: 0.2, z: 0.2, w: 0),
                ])
                image = gray.composited(over: image)
            }
        }

        return image
    }

    // MARK: - Text layers

    static func applyText(_ layers: [TextLayer], to input: CIImage) -> CIImage {
        guard !layers.isEmpty else { return input }
        let extent = input.extent
        guard extent.width > 0, extent.height > 0 else { return input }

        var image = input
        for layer in layers {
            guard !layer.text.isEmpty, let textImage = renderText(layer, imageExtent: extent) else { continue }
            image = textImage.composited(over: image)
        }
        // Chữ tràn mép sẽ nới rộng extent -> phải crop lại đúng khung ảnh gốc,
        // nếu không khi hiển thị aspect-fit ảnh sẽ bị thu nhỏ và lòi nền đen.
        return image.cropped(to: extent)
    }

    private static func renderText(_ layer: TextLayer, imageExtent: CGRect) -> CIImage? {
        let fontSize = max(layer.fontSize * imageExtent.height, 8)
        let font = TextRendering.font(pointSize: fontSize, bold: layer.bold)
        let color = UIColor(hex: layer.colorHex) ?? .white

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .shadow: {
                let s = NSShadow(); s.shadowColor = UIColor.black.withAlphaComponent(0.5)
                s.shadowBlurRadius = fontSize * 0.08; s.shadowOffset = CGSize(width: 0, height: fontSize * 0.03)
                return s
            }(),
        ]
        let attr = NSAttributedString(string: layer.text, attributes: attributes)
        let textSize = attr.size()

        let renderer = UIGraphicsImageRenderer(size: textSize)
        let uiImage = renderer.image { _ in attr.draw(at: .zero) }
        guard let cg = uiImage.cgImage else { return nil }

        var ci = CIImage(cgImage: cg)
        // Xoay quanh tâm hộp chữ (nếu có).
        if abs(layer.rotation) > 0.01 {
            let angle = -CGFloat(layer.rotation) * .pi / 180   // khớp chiều xoay overlay
            let toCenter = CGAffineTransform(translationX: -textSize.width / 2, y: -textSize.height / 2)
            let rotate = CGAffineTransform(rotationAngle: angle)
            let back = CGAffineTransform(translationX: textSize.width / 2, y: textSize.height / 2)
            ci = ci.transformed(by: toCenter.concatenating(rotate).concatenating(back))
        }
        // Vị trí (chuẩn hoá, gốc trên-trái) -> toạ độ Core Image (gốc dưới-trái).
        let cx = imageExtent.origin.x + layer.position.x * imageExtent.width
        let cy = imageExtent.origin.y + (1 - layer.position.y) * imageExtent.height
        let px = cx - ci.extent.width / 2 - ci.extent.origin.x
        let py = cy - ci.extent.height / 2 - ci.extent.origin.y
        ci = ci.transformed(by: CGAffineTransform(translationX: px, y: py))
        return ci
    }
}
