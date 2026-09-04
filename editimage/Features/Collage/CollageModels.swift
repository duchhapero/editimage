//
//  CollageModels.swift
//  editimage
//
//  Bố cục lưới collage + trạng thái từng ô (zoom/kéo trong ô).
//

import CoreGraphics

/// Một bố cục collage: danh sách khung ô (chuẩn hoá 0...1 trong khung collage).
struct CollageLayout: Identifiable, Equatable {
    let id: String
    let count: Int
    let frames: [CGRect]
}

/// Trạng thái ảnh trong 1 ô: phóng to + dịch chuyển (theo tỉ lệ kích thước ô).
struct CellTransform: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
}

enum CollageLayouts {
    /// Các bố cục khả dụng theo số ảnh.
    static func templates(for count: Int) -> [CollageLayout] {
        switch count {
        case 2:
            return [
                CollageLayout(id: "2h", count: 2, frames: [
                    CGRect(x: 0, y: 0, width: 0.5, height: 1),
                    CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
                ]),
                CollageLayout(id: "2v", count: 2, frames: [
                    CGRect(x: 0, y: 0, width: 1, height: 0.5),
                    CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
                ]),
            ]
        case 3:
            return [
                CollageLayout(id: "3-1L2R", count: 3, frames: [
                    CGRect(x: 0, y: 0, width: 0.5, height: 1),
                    CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                    CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                ]),
                CollageLayout(id: "3v", count: 3, frames: [
                    CGRect(x: 0, y: 0, width: 1, height: 1.0/3),
                    CGRect(x: 0, y: 1.0/3, width: 1, height: 1.0/3),
                    CGRect(x: 0, y: 2.0/3, width: 1, height: 1.0/3),
                ]),
                CollageLayout(id: "3h", count: 3, frames: [
                    CGRect(x: 0, y: 0, width: 1.0/3, height: 1),
                    CGRect(x: 1.0/3, y: 0, width: 1.0/3, height: 1),
                    CGRect(x: 2.0/3, y: 0, width: 1.0/3, height: 1),
                ]),
                CollageLayout(id: "3-1T2B", count: 3, frames: [
                    CGRect(x: 0, y: 0, width: 1, height: 0.5),
                    CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                    CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                ]),
            ]
        default: // 4
            return [
                CollageLayout(id: "4grid", count: 4, frames: [
                    CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                    CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                    CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                    CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                ]),
                CollageLayout(id: "4-1L3R", count: 4, frames: [
                    CGRect(x: 0, y: 0, width: 0.5, height: 1),
                    CGRect(x: 0.5, y: 0, width: 0.5, height: 1.0/3),
                    CGRect(x: 0.5, y: 1.0/3, width: 0.5, height: 1.0/3),
                    CGRect(x: 0.5, y: 2.0/3, width: 0.5, height: 1.0/3),
                ]),
                CollageLayout(id: "4v", count: 4, frames: (0..<4).map {
                    CGRect(x: 0, y: Double($0) / 4, width: 1, height: 0.25)
                }),
                CollageLayout(id: "4h", count: 4, frames: (0..<4).map {
                    CGRect(x: Double($0) / 4, y: 0, width: 0.25, height: 1)
                }),
            ]
        }
    }

    /// Tỉ lệ khung xuất (width/height).
    static let aspectRatios: [(String, CGFloat)] = [
        ("1:1", 1), ("4:5", 4.0/5), ("3:4", 3.0/4), ("16:9", 16.0/9), ("9:16", 9.0/16),
    ]
}
