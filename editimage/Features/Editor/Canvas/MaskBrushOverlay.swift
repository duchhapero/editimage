//
//  MaskBrushOverlay.swift
//  editimage
//
//  Lớp phủ cho phép quẹt tay đánh dấu vùng cần xoá (inpaint). Tạo mask PNG
//  (trắng = vùng xoá) ở đúng độ phân giải bản preview để đưa vào Inpainter.
//
//  Lưu ý demo: nên dùng "xoá vật thể" TRƯỚC khi cắt ảnh để toạ độ mask khớp.
//

import SwiftUI
import UIKit

struct MaskBrushOverlay: View {
    /// Tỉ lệ khung ảnh hiển thị (width/height).
    let imageAspect: CGFloat
    /// Kích thước pixel của bản preview gốc (để render mask).
    let maskPixelSize: CGSize
    let onApply: (Data) -> Void
    let onCancel: () -> Void

    @State private var strokes: [[CGPoint]] = []   // toạ độ chuẩn hoá 0...1 theo khung ảnh
    @State private var current: [CGPoint] = []
    @State private var brush: CGFloat = 0.05        // bán kính theo tỉ lệ chiều rộng

    var body: some View {
        GeometryReader { geo in
            let rect = fittedRect(in: geo.size, aspect: imageAspect)

            ZStack {
                // Bắt cử chỉ + vẽ nét đã quẹt.
                Canvas { ctx, _ in
                    let allStrokes = strokes + [current]
                    for stroke in allStrokes {
                        guard stroke.count > 1 else { continue }
                        var path = Path()
                        let pts = stroke.map { CGPoint(x: rect.minX + $0.x * rect.width,
                                                       y: rect.minY + $0.y * rect.height) }
                        path.addLines(pts)
                        ctx.stroke(path, with: .color(.red.opacity(0.5)),
                                   style: StrokeStyle(lineWidth: brush * rect.width * 2,
                                                      lineCap: .round, lineJoin: .round))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let p = normalize(v.location, in: rect)
                            current.append(p)
                        }
                        .onEnded { _ in
                            if !current.isEmpty { strokes.append(current); current = [] }
                        }
                )
            }
            .overlay(alignment: .bottom) { controls }
        }
        .background(Color.black.opacity(0.001))  // nhận chạm toàn vùng
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Cỡ cọ").font(.caption).foregroundStyle(.white)
                Slider(value: $brush, in: 0.02...0.12).tint(.white)
            }
            HStack(spacing: 12) {
                ActionChip(title: "Huỷ", icon: "xmark") { onCancel() }
                ActionChip(title: "Xoá nét", icon: "arrow.uturn.backward") {
                    if !strokes.isEmpty { strokes.removeLast() }
                }
                Spacer()
                ActionChip(title: "Áp dụng", icon: "checkmark", tint: .green) {
                    if let data = renderMask() { onApply(data) }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func normalize(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: min(max((p.x - rect.minX) / rect.width, 0), 1),
                y: min(max((p.y - rect.minY) / rect.height, 0), 1))
    }

    private func fittedRect(in size: CGSize, aspect: CGFloat) -> CGRect {
        let viewAspect = size.width / size.height
        var w = size.width, h = size.height
        if aspect > viewAspect { h = w / aspect } else { w = h * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    /// Render mask trắng-trên-đen ở độ phân giải preview.
    private func renderMask() -> Data? {
        guard maskPixelSize.width > 1, maskPixelSize.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: maskPixelSize, format: format)
        let image = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: maskPixelSize))
            UIColor.white.setStroke()
            let lineWidth = brush * maskPixelSize.width * 2
            for stroke in strokes where stroke.count > 1 {
                let path = UIBezierPath()
                let pts = stroke.map { CGPoint(x: $0.x * maskPixelSize.width,
                                               y: $0.y * maskPixelSize.height) }
                path.move(to: pts[0])
                pts.dropFirst().forEach { path.addLine(to: $0) }
                path.lineWidth = lineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        }
        return image.pngData()
    }
}
