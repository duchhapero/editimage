//
//  LUTEngine.swift
//  editimage
//
//  Engine filter/preset dựa trên Color Cube (CIColorCube). Các "look" được sinh
//  bằng thuật toán ngay trong code (không cần file .cube), nên chạy out-of-the-box.
//  Kiến trúc cho phép sau này nạp thêm .cube/Hald PNG mà không đổi UI.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Một preset màu.
struct FilterPreset: Identifiable, Equatable {
    let id: String
    let name: String
    /// Hàm biến đổi màu (đầu vào/ra RGB trong [0,1]).
    let transform: (SIMD3<Float>) -> SIMD3<Float>

    static func == (lhs: FilterPreset, rhs: FilterPreset) -> Bool { lhs.id == rhs.id }
}

enum LUTEngine {
    static let cubeDimension = 32

    /// Danh sách preset hiển thị trong panel Filters.
    static let presets: [FilterPreset] = [
        FilterPreset(id: "original", name: "Gốc", transform: { $0 }),
        FilterPreset(id: "vivid",    name: "Rực rỡ", transform: vivid),
        FilterPreset(id: "warm",     name: "Ấm", transform: warm),
        FilterPreset(id: "cool",     name: "Lạnh", transform: cool),
        FilterPreset(id: "fade",     name: "Faded", transform: fade),
        FilterPreset(id: "tealorange", name: "Teal-Cam", transform: tealOrange),
        FilterPreset(id: "mono",     name: "Đen trắng", transform: mono),
        FilterPreset(id: "noir",     name: "Noir", transform: noir),
        FilterPreset(id: "vintage",  name: "Vintage", transform: vintage),
    ]

    static func preset(id: String?) -> FilterPreset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    // MARK: - Áp LUT lên ảnh

    private static var cubeCache: [String: Data] = [:]

    /// Trả về ảnh đã áp preset với cường độ (0...1). intensity<1 sẽ trộn với ảnh gốc.
    static func apply(presetID: String?, intensity: Double, to image: CIImage) -> CIImage {
        guard let preset = preset(id: presetID), preset.id != "original" else { return image }

        let data: Data
        if let cached = cubeCache[preset.id] {
            data = cached
        } else {
            data = makeCubeData(transform: preset.transform)
            cubeCache[preset.id] = data
        }

        let filter = CIFilter.colorCube()
        filter.cubeDimension = Float(cubeDimension)
        filter.cubeData = data
        filter.inputImage = image
        guard let filtered = filter.outputImage else { return image }

        if intensity >= 0.999 { return filtered }
        // Trộn gốc ↔ filter theo cường độ.
        return blend(base: image, over: filtered, alpha: intensity)
    }

    private static func blend(base: CIImage, over: CIImage, alpha: Double) -> CIImage {
        let mix = CIFilter.dissolveTransition()
        mix.inputImage = base
        mix.targetImage = over
        mix.time = Float(alpha)
        return mix.outputImage ?? over
    }

    // MARK: - Sinh dữ liệu cube

    private static func makeCubeData(transform: (SIMD3<Float>) -> SIMD3<Float>) -> Data {
        let n = cubeDimension
        var cube = [Float](repeating: 0, count: n * n * n * 4)
        var offset = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let input = SIMD3<Float>(Float(r) / Float(n - 1),
                                             Float(g) / Float(n - 1),
                                             Float(b) / Float(n - 1))
                    let out = clamp(transform(input))
                    cube[offset + 0] = out.x
                    cube[offset + 1] = out.y
                    cube[offset + 2] = out.z
                    cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func clamp(_ v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(min(max(v.x, 0), 1), min(max(v.y, 0), 1), min(max(v.z, 0), 1))
    }

    // MARK: - Các "look" (transform)

    private static func luma(_ c: SIMD3<Float>) -> Float {
        0.299 * c.x + 0.587 * c.y + 0.114 * c.z
    }

    private static func vivid(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let l = luma(c)
        let sat: Float = 1.35
        var out = SIMD3(l + (c.x - l) * sat, l + (c.y - l) * sat, l + (c.z - l) * sat)
        // tăng contrast nhẹ
        out = (out - 0.5) * 1.12 + 0.5
        return out
    }

    private static func warm(_ c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(c.x * 1.08 + 0.02, c.y * 1.02, c.z * 0.92)
    }

    private static func cool(_ c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(c.x * 0.93, c.y * 1.0, c.z * 1.09 + 0.02)
    }

    private static func fade(_ c: SIMD3<Float>) -> SIMD3<Float> {
        // nâng đen (lifted blacks), giảm contrast -> phong cách film phai
        let lift: Float = 0.06
        var out = c * (1 - lift) + SIMD3(repeating: lift)
        out = (out - 0.5) * 0.9 + 0.5
        return SIMD3(out.x * 1.02, out.y, out.z * 0.98)
    }

    private static func tealOrange(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let l = luma(c)
        // vùng tối -> teal, vùng sáng -> cam
        let shadowTint = SIMD3<Float>(-0.04, 0.02, 0.06)
        let highTint = SIMD3<Float>(0.06, 0.02, -0.05)
        let t = l
        let tint = shadowTint * (1 - t) + highTint * t
        return c + tint
    }

    private static func mono(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let l = luma(c)
        return SIMD3(repeating: l)
    }

    private static func noir(_ c: SIMD3<Float>) -> SIMD3<Float> {
        var l = luma(c)
        l = (l - 0.5) * 1.35 + 0.5   // contrast cao
        return SIMD3(repeating: l)
    }

    private static func vintage(_ c: SIMD3<Float>) -> SIMD3<Float> {
        var out = SIMD3(c.x * 1.05 + 0.03, c.y * 0.98 + 0.01, c.z * 0.85)
        out = (out - 0.5) * 0.92 + 0.5
        out += SIMD3<Float>(0.02, 0.0, -0.01)  // ám vàng nhẹ
        return out
    }
}
