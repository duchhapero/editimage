//
//  HSLProcessor.swift
//  editimage
//
//  Chỉnh Hue/Saturation/Luminance theo 8 dải màu, dựng thành 1 color cube (CIColorCube)
//  tính bằng code. Có cache theo tham số để không dựng lại cube mỗi frame khi không đổi.
//

import CoreImage
import CoreImage.CIFilterBuiltins

enum HSLProcessor {
    private static let dimension = 24
    private static var cache: (key: HSL, data: Data)?

    static func apply(_ hsl: HSL, to image: CIImage) -> CIImage {
        guard !hsl.isIdentity else { return image }

        let data: Data
        if let cache, cache.key == hsl {
            data = cache.data
        } else {
            data = makeCube(hsl)
            cache = (hsl, data)
        }

        let filter = CIFilter.colorCube()
        filter.cubeDimension = Float(dimension)
        filter.cubeData = data
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    private static func makeCube(_ hsl: HSL) -> Data {
        let n = dimension
        var cube = [Float](repeating: 0, count: n * n * n * 4)
        var offset = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let rf = Float(r) / Float(n - 1)
                    let gf = Float(g) / Float(n - 1)
                    let bf = Float(b) / Float(n - 1)
                    let out = adjust(r: rf, g: gf, b: bf, hsl: hsl)
                    cube[offset + 0] = out.0
                    cube[offset + 1] = out.1
                    cube[offset + 2] = out.2
                    cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func adjust(r: Float, g: Float, b: Float, hsl: HSL) -> (Float, Float, Float) {
        var (h, s, l) = rgbToHSL(r, g, b)
        guard s > 0.001 else { return (r, g, b) }   // xám: bỏ qua

        var hueShift: Float = 0, satFactor: Float = 1, lumShift: Float = 0
        for (i, band) in hsl.bands.enumerated() where !band.isZero {
            let center = Float(HSL.bandHues[i])
            let w = weight(hue: h * 360, center: center)
            guard w > 0 else { continue }
            hueShift += w * Float(band.hue) * 30      // ±30°
            satFactor += w * Float(band.sat)          // ±100%
            lumShift += w * Float(band.lum) * 0.4     // ±0.4
        }

        h = (h + hueShift / 360).truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        s = min(max(s * satFactor, 0), 1)
        l = min(max(l + lumShift, 0), 1)
        return hslToRGB(h, s, l)
    }

    /// Trọng số dải theo khoảng cách hue (falloff tam giác, rộng ~45°).
    private static func weight(hue: Float, center: Float) -> Float {
        var d = abs(hue - center).truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        let width: Float = 45
        return max(0, 1 - d / width)
    }

    // MARK: - Chuyển đổi màu

    private static func rgbToHSL(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        guard maxV != minV else { return (0, 0, l) }
        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Float
        if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if maxV == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h /= 6
        return (h, s, l)
    }

    private static func hslToRGB(_ h: Float, _ s: Float, _ l: Float) -> (Float, Float, Float) {
        guard s != 0 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return (hue2rgb(p, q, h + 1.0/3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0/3))
    }

    private static func hue2rgb(_ p: Float, _ q: Float, _ tIn: Float) -> Float {
        var t = tIn
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0/6 { return p + (q - p) * 6 * t }
        if t < 1.0/2 { return q }
        if t < 2.0/3 { return p + (q - p) * (2.0/3 - t) * 6 }
        return p
    }
}
