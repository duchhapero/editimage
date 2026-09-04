//
//  DebugSeed.swift
//  editimage
//
//  Chỉ dùng khi DEBUG + biến môi trường SEED_DEMO=1: tạo 1 dự án mẫu (ảnh sinh
//  bằng code) để kiểm thử pipeline render mà không cần tương tác photo picker.
//

#if DEBUG
import UIKit
import CoreImage

enum DebugSeed {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SEED_DEMO"] == "1"
    }

    /// Sinh 1 ảnh nhiều màu (gradient + hình khối) để test adjustment/filter.
    static func makeTestImageData(size: CGSize = CGSize(width: 1200, height: 1600)) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            // Gradient nền
            let colors = [UIColor(hex: "#FF7E5F")!.cgColor, UIColor(hex: "#2E7DFF")!.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero,
                                  end: CGPoint(x: size.width, y: size.height), options: [])
            // Vài hình tròn màu
            let circleColors = ["#FFD60A", "#34C759", "#FF2D55", "#FFFFFF"]
            for (i, hex) in circleColors.enumerated() {
                UIColor(hex: hex)!.withAlphaComponent(0.85).setFill()
                let r: CGFloat = 180 + CGFloat(i) * 30
                let rect = CGRect(x: CGFloat(i) * 220 + 60, y: CGFloat(i) * 260 + 120,
                                  width: r, height: r)
                cg.fillEllipse(in: rect)
            }
            // Khối chữ nhật đen để thấy contrast
            UIColor.black.withAlphaComponent(0.7).setFill()
            cg.fill(CGRect(x: 100, y: size.height - 400, width: size.width - 200, height: 200))
        }
        return image.pngData() ?? Data()
    }
}
#endif
