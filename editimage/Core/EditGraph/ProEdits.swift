//
//  ProEdits.swift
//  editimage
//
//  Kiểu dữ liệu cho các tính năng pro: Curves, HSL theo dải màu, Selective mask.
//  Tất cả Codable để lưu dự án & undo/redo, không phá hủy.
//

import CoreGraphics
import Foundation

// MARK: - Curves

struct CurvePoint: Codable, Equatable {
    var x: Double   // 0...1 (input)
    var y: Double   // 0...1 (output)
}

struct Curves: Codable, Equatable {
    var master: [CurvePoint] = Curves.diagonal
    var red: [CurvePoint] = Curves.diagonal
    var green: [CurvePoint] = Curves.diagonal
    var blue: [CurvePoint] = Curves.diagonal

    static let diagonal = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]

    var isIdentity: Bool {
        master == Curves.diagonal && red == Curves.diagonal &&
        green == Curves.diagonal && blue == Curves.diagonal
    }

    enum Channel: String, CaseIterable, Identifiable {
        case master, red, green, blue
        var id: String { rawValue }
        var title: String {
            switch self {
            case .master: return "RGB"
            case .red:    return "Đỏ"
            case .green:  return "Lục"
            case .blue:   return "Lam"
            }
        }
    }

    subscript(_ channel: Channel) -> [CurvePoint] {
        get {
            switch channel {
            case .master: return master
            case .red:    return red
            case .green:  return green
            case .blue:   return blue
            }
        }
        set {
            switch channel {
            case .master: master = newValue
            case .red:    red = newValue
            case .green:  green = newValue
            case .blue:   blue = newValue
            }
        }
    }
}

// MARK: - HSL (8 dải màu)

struct HSLBand: Codable, Equatable {
    var hue: Double = 0   // -1...1
    var sat: Double = 0   // -1...1
    var lum: Double = 0   // -1...1
    var isZero: Bool { hue == 0 && sat == 0 && lum == 0 }
}

struct HSL: Codable, Equatable {
    var bands: [HSLBand] = Array(repeating: HSLBand(), count: 8)

    /// Tên + hue tâm (độ) của 8 dải: Đỏ, Cam, Vàng, Lục, Xanh ngọc, Lam, Tím, Hồng.
    static let bandNames = ["Đỏ", "Cam", "Vàng", "Lục", "X.ngọc", "Lam", "Tím", "Hồng"]
    static let bandHues: [Double] = [0, 30, 60, 120, 180, 240, 285, 320]

    var isIdentity: Bool { bands.allSatisfy { $0.isZero } }
}

// MARK: - Selective mask

enum MaskShape: Codable, Equatable {
    case radial(center: CGPoint, radius: Double, feather: Double)  // toạ độ chuẩn hoá
    case linear(start: CGPoint, end: CGPoint)
    case brush(maskPNG: Data)

    var label: String {
        switch self {
        case .radial: return "Tròn"
        case .linear: return "Dải"
        case .brush:  return "Cọ"
        }
    }
}

/// Bộ chỉnh cục bộ áp trong vùng mask.
struct LocalAdjust: Codable, Equatable {
    var exposure: Double = 0     // -2...2
    var contrast: Double = 1     // 0.5...1.5
    var saturation: Double = 1   // 0...2
    var temperature: Double = 0  // -1...1
    var sharpness: Double = 0    // 0...2

    static let identity = LocalAdjust()
    var isIdentity: Bool { self == .identity }
}

struct SelectiveMask: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var shape: MaskShape
    var adjust: LocalAdjust = .identity
    var inverted: Bool = false
}

// MARK: - Retouch chân dung

/// Một nốt cần xoá (mụn/vết). Toạ độ & bán kính chuẩn hoá theo ảnh.
struct HealSpot: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var center: CGPoint
    var radius: Double
}

struct Retouch: Codable, Equatable {
    var skinSmooth: Double = 0     // 0...1
    var spots: [HealSpot] = []

    var isIdentity: Bool { skinSmooth == 0 && spots.isEmpty }
}
