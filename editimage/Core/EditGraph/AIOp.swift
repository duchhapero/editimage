//
//  AIOp.swift
//  editimage
//
//  Thao tác AI "đắt" — được bake 1 lần rồi cache (không chạy lại mỗi frame).
//  Lưu tách khỏi EditGraph để có thể replay trên ảnh full-res khi export.
//

import Foundation

/// Cách lấp nền sau khi tách chủ thể.
enum BackgroundFill: Equatable, Codable {
    case transparent
    case color(hex: String)
}

/// Một thao tác AI. maskPNG là mask nhị phân (trắng = vùng tác động) ở toạ độ ảnh.
enum AIOp: Equatable, Codable {
    case removeBackground(fill: BackgroundFill)
    case bokeh(intensity: Double)
    case inpaint(maskPNG: Data)

    var label: String {
        switch self {
        case .removeBackground: return "Tách nền"
        case .bokeh:            return "Xoá phông"
        case .inpaint:          return "Xoá vật thể"
        }
    }
}
