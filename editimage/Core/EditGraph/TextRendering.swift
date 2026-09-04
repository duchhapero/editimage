//
//  TextRendering.swift
//  editimage
//
//  Dùng chung giữa GraphCompiler (render chữ vào ảnh) và TextHandleView (khung
//  kéo-thả), để kích thước khung khớp đúng chữ thật.
//

import UIKit

enum TextRendering {
    static func font(pointSize: CGFloat, bold: Bool) -> UIFont {
        bold ? UIFont.boldSystemFont(ofSize: pointSize) : UIFont.systemFont(ofSize: pointSize)
    }

    /// Kích thước hộp chữ (chưa gồm bóng) tại một cỡ font điểm cho trước.
    static func size(text: String, pointSize: CGFloat, bold: Bool) -> CGSize {
        let attr = NSAttributedString(string: text, attributes: [.font: font(pointSize: pointSize, bold: bold)])
        return attr.size()
    }
}
