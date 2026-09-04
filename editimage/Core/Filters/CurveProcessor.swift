//
//  CurveProcessor.swift
//  editimage
//
//  Áp Curves (RGB tổng + từng kênh) qua CIColorCurves. Master áp trước, rồi tới
//  đường cong từng kênh. Nội suy trơn giữa các điểm điều khiển.
//

import CoreImage
import CoreImage.CIFilterBuiltins

enum CurveProcessor {
    private static let sampleCount = 65

    static func apply(_ curves: Curves, to image: CIImage) -> CIImage {
        guard !curves.isIdentity else { return image }

        var data = [Float]()
        data.reserveCapacity(sampleCount * 3)
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleCount - 1)
            let m = evaluate(curves.master, at: t)
            data.append(Float(evaluate(curves.red, at: m)))
            data.append(Float(evaluate(curves.green, at: m)))
            data.append(Float(evaluate(curves.blue, at: m)))
        }

        let curvesData = data.withUnsafeBufferPointer { Data(buffer: $0) }
        let filter = CIFilter.colorCurves()
        filter.inputImage = image
        filter.curvesData = curvesData
        filter.curvesDomain = CIVector(x: 0, y: 1)
        filter.colorSpace = CGColorSpaceCreateDeviceRGB()
        return filter.outputImage ?? image
    }

    /// Nội suy giá trị đường cong tại x (0...1) từ các điểm điều khiển (nội suy Catmull-Rom, kẹp 0...1).
    static func evaluate(_ points: [CurvePoint], at x: Double) -> Double {
        let pts = points.sorted { $0.x < $1.x }
        guard pts.count >= 2 else { return x }
        if x <= pts.first!.x { return clamp(pts.first!.y) }
        if x >= pts.last!.x { return clamp(pts.last!.y) }

        // Tìm đoạn chứa x.
        var i = 0
        while i < pts.count - 1 && !(x >= pts[i].x && x <= pts[i + 1].x) { i += 1 }
        let p1 = pts[i], p2 = pts[i + 1]
        let p0 = i > 0 ? pts[i - 1] : p1
        let p3 = i + 2 < pts.count ? pts[i + 2] : p2

        let span = p2.x - p1.x
        guard span > 0.0001 else { return clamp(p2.y) }
        let t = (x - p1.x) / span

        // Catmull-Rom cho trục y.
        let t2 = t * t
        let t3 = t2 * t
        let y0 = p0.y, y1 = p1.y, y2 = p2.y, y3 = p3.y
        let c0: Double = 2 * y1
        let c1: Double = (-y0 + y2) * t
        let c2base: Double = (2 * y0) - (5 * y1) + (4 * y2) - y3
        let c2: Double = c2base * t2
        let c3base: Double = (-y0) + (3 * y1) - (3 * y2) + y3
        let c3: Double = c3base * t3
        let sum: Double = c0 + c1 + c2 + c3
        let y: Double = 0.5 * sum
        return clamp(y)
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}
