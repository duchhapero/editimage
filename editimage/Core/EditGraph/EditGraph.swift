//
//  EditGraph.swift
//  editimage
//
//  Mô hình chỉnh sửa KHÔNG phá hủy. Ảnh gốc bất biến; toàn bộ thao tác "rẻ"
//  (adjustment, geometry, LUT, effect, text) lưu ở đây và được compile thành
//  chuỗi CIFilter mỗi lần render. Serialize được để lưu dự án & undo/redo.
//
//  Thao tác "đắt" (AI: tách nền, inpaint, bokeh) không nằm ở đây mà ở AIOp,
//  vì chúng được "bake" 1 lần rồi cache (không chạy lại mỗi frame).
//

import Foundation
import CoreGraphics

// MARK: - Adjustments (Light & Color)

/// Bộ thông số chỉnh sáng/màu. Giá trị mặc định = ảnh gốc (neutral).
struct Adjustments: Codable, Equatable {
    var exposure: Double = 0      // EV, -2...2
    var brightness: Double = 0    // -0.3...0.3
    var contrast: Double = 1      // 0.5...1.5 (1 = gốc)
    var highlights: Double = 0    // -1...1
    var shadows: Double = 0       // -1...1
    var temperature: Double = 0   // -1(lạnh)...1(ấm)
    var tint: Double = 0          // -1(xanh lá)...1(hồng)
    var saturation: Double = 1    // 0...2 (1 = gốc)
    var vibrance: Double = 0      // -1...1
    var sharpness: Double = 0     // 0...2
    var clarity: Double = 0       // -1...1
    var vignette: Double = 0      // 0...1
    var grain: Double = 0         // 0...1

    static let neutral = Adjustments()
    var isNeutral: Bool { self == .neutral }
}

// MARK: - Geometry (Crop / Rotate / Straighten / Flip)

/// Biến đổi hình học. cropRect chuẩn hoá 0...1 theo ảnh gốc (sau khi xoay 90°).
struct Geometry: Codable, Equatable {
    var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var quarterTurns: Int = 0        // số lần xoay 90° (0...3)
    var straighten: Double = 0       // góc chỉnh nghiêng, -45...45 độ
    var flipH: Bool = false
    var flipV: Bool = false

    static let identity = Geometry()
    var isIdentity: Bool { self == .identity }
}

// MARK: - Text layer

struct TextLayer: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String = "Nhập chữ"
    var position: CGPoint = CGPoint(x: 0.5, y: 0.5)  // chuẩn hoá 0...1
    var fontSize: Double = 0.08                       // theo tỉ lệ chiều cao ảnh
    var colorHex: String = "#FFFFFF"
    var bold: Bool = true
    var rotation: Double = 0                          // độ (degrees)
}

// MARK: - Image layer (ảnh chồng)

/// Chế độ hoà trộn khi ghép ảnh chồng lên ảnh nền.
enum BlendKind: String, Codable, CaseIterable, Identifiable {
    case normal, multiply, screen, overlay, darken, lighten, difference
    var id: String { rawValue }
    var label: String {
        switch self {
        case .normal:     return "Bình thường"
        case .multiply:   return "Nhân"
        case .screen:     return "Screen"
        case .overlay:    return "Overlay"
        case .darken:     return "Tối"
        case .lighten:    return "Sáng"
        case .difference: return "Khác biệt"
        }
    }
    /// Tên CIFilter tương ứng (nil = source-over thường).
    var ciFilterName: String? {
        switch self {
        case .normal:     return nil
        case .multiply:   return "CIMultiplyBlendMode"
        case .screen:     return "CIScreenBlendMode"
        case .overlay:    return "CIOverlayBlendMode"
        case .darken:     return "CIDarkenBlendMode"
        case .lighten:    return "CILightenBlendMode"
        case .difference: return "CIDifferenceBlendMode"
        }
    }
}

/// Một lớp ảnh chồng lên ảnh nền (như sticker). Toạ độ/tỉ lệ chuẩn hoá theo ảnh nền.
struct ImageLayer: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var imageData: Data
    var position: CGPoint = CGPoint(x: 0.5, y: 0.5)  // tâm, chuẩn hoá 0...1
    var scale: Double = 0.5                            // bề rộng lớp = scale * bề rộng ảnh nền
    var rotation: Double = 0                           // độ
    var opacity: Double = 1                            // 0...1
    var blend: BlendKind = .normal
}

// MARK: - EditGraph

/// Toàn bộ trạng thái chỉnh sửa "rẻ" của một ảnh.
struct EditGraph: Codable, Equatable {
    var adjustments = Adjustments()
    var geometry = Geometry()
    var retouch = Retouch()
    var curves = Curves()
    var hsl = HSL()
    var masks: [SelectiveMask] = []
    var lutID: String? = nil
    var lutIntensity: Double = 1.0
    var imageLayers: [ImageLayer] = []
    var textLayers: [TextLayer] = []

    static let empty = EditGraph()
    var isEmpty: Bool { self == .empty }

    mutating func reset() { self = .empty }
}
