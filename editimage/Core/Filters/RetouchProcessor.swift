//
//  RetouchProcessor.swift
//  editimage
//
//  Retouch chân dung offline:
//   - Làm mịn da: nhận diện vùng da (skin-tone) rồi trộn bản làm mượt chỉ trong vùng da,
//     giữ nét mắt/môi/tóc.
//   - Xoá mụn: mỗi nốt được lấp bằng bản làm mượt cục bộ (trung bình màu da xung quanh).
//

import CoreImage
import CoreImage.CIFilterBuiltins

enum RetouchProcessor {
    static func apply(_ retouch: Retouch, to input: CIImage) -> CIImage {
        guard !retouch.isIdentity else { return input }
        var image = input
        if retouch.skinSmooth > 0 {
            image = smoothSkin(image, intensity: retouch.skinSmooth)
        }
        if !retouch.spots.isEmpty {
            image = healSpots(retouch.spots, in: image)
        }
        return image
    }

    // MARK: - Làm mịn da

    private static func smoothSkin(_ image: CIImage, intensity: Double) -> CIImage {
        let extent = image.extent
        let minDim = min(extent.width, extent.height)

        let blurRadius = minDim * 0.006 * (0.6 + intensity)
        let blurred = image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: extent)

        // Mask da (trắng = da), feather rồi nhân với cường độ.
        var mask = skinMask(for: image)
        mask = mask.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: minDim * 0.004])
            .cropped(to: extent)
        mask = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(intensity), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(intensity), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(intensity), w: 0),
        ])

        let blend = CIFilter.blendWithMask()
        blend.inputImage = blurred
        blend.backgroundImage = image
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    // MARK: - Xoá mụn

    private static func healSpots(_ spots: [HealSpot], in image: CIImage) -> CIImage {
        let extent = image.extent
        let minDim = min(extent.width, extent.height)

        // Bán kính blur tỉ lệ với nốt lớn nhất -> đủ mạnh để xoá hẳn vết.
        let maxR = spots.map { $0.radius }.max() ?? 0.03
        let blurRadius = max(minDim * CGFloat(maxR) * 1.3, minDim * 0.015)
        let blurred = image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: extent)

        // Hợp nhất mask các nốt (radial gradient, lấy max).
        var mask = CIImage(color: .black).cropped(to: extent)
        for spot in spots {
            let cx = extent.origin.x + spot.center.x * extent.width
            let cy = extent.origin.y + (1 - spot.center.y) * extent.height
            let r = max(spot.radius, 0.005) * minDim
            let g = CIFilter.radialGradient()
            g.center = CGPoint(x: cx, y: cy)
            g.radius0 = Float(r * 0.4)
            g.radius1 = Float(r)
            g.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            g.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            if let spotMask = g.outputImage?.cropped(to: extent) {
                mask = spotMask.applyingFilter("CILightenBlendMode", parameters: [
                    kCIInputBackgroundImageKey: mask,
                ])
            }
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = blurred
        blend.backgroundImage = image
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    // MARK: - Skin mask (dùng color cube, dựng 1 lần)

    private static var skinCube: Data?

    private static func skinMask(for image: CIImage) -> CIImage {
        let data: Data
        if let skinCube { data = skinCube } else { data = makeSkinCube(); skinCube = data }
        let f = CIFilter.colorCube()
        f.cubeDimension = 32
        f.cubeData = data
        f.inputImage = image
        return (f.outputImage ?? image).cropped(to: image.extent)
    }

    /// Cube xuất trắng cho pixel màu da (quy tắc Kovac), đen cho phần còn lại.
    private static func makeSkinCube() -> Data {
        let n = 32
        var cube = [Float](repeating: 0, count: n * n * n * 4)
        var offset = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let rf = Float(r) / Float(n - 1)
                    let gf = Float(g) / Float(n - 1)
                    let bf = Float(b) / Float(n - 1)
                    let v: Float = isSkin(rf, gf, bf) ? 1 : 0
                    cube[offset + 0] = v
                    cube[offset + 1] = v
                    cube[offset + 2] = v
                    cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func isSkin(_ r: Float, _ g: Float, _ b: Float) -> Bool {
        let maxV = max(r, g, b), minV = min(r, g, b)
        return r > 0.37 && g > 0.16 && b > 0.078 &&
               (maxV - minV) > 0.05 &&
               abs(r - g) > 0.05 && r > g && r > b
    }
}
