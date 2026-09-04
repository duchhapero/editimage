//
//  CurveEditorView.swift
//  editimage
//
//  Trình chỉnh đường cong tương tác: chạm để thêm điểm, kéo để chỉnh, đường cong
//  vẽ theo đúng thuật toán nội suy dùng khi render.
//

import SwiftUI

struct CurveEditorView: View {
    @Bindable var model: EditorViewModel
    let channel: Curves.Channel

    @State private var dragIndex: Int?

    private var lineColor: Color {
        switch channel {
        case .master: return .white
        case .red:    return .red
        case .green:  return .green
        case .blue:   return .blue
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
                grid(side: side)
                curvePath(side: side).stroke(lineColor, lineWidth: 2)
                pointsView(side: side)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(side: side))
        }
        .frame(height: 200)
    }

    // MARK: - Vẽ

    private func grid(side: CGFloat) -> some View {
        Path { p in
            for i in 0...4 {
                let v = side * CGFloat(i) / 4
                p.move(to: CGPoint(x: v, y: 0)); p.addLine(to: CGPoint(x: v, y: side))
                p.move(to: CGPoint(x: 0, y: v)); p.addLine(to: CGPoint(x: side, y: v))
            }
        }
        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
    }

    private func curvePath(side: CGFloat) -> Path {
        var path = Path()
        let pts = model.graph.curves[channel]
        let steps = 48
        for i in 0...steps {
            let x = Double(i) / Double(steps)
            let y = CurveProcessor.evaluate(pts, at: x)
            let sp = CGPoint(x: CGFloat(x) * side, y: CGFloat(1 - y) * side)
            if i == 0 { path.move(to: sp) } else { path.addLine(to: sp) }
        }
        return path
    }

    private func pointsView(side: CGFloat) -> some View {
        let pts = model.graph.curves[channel]
        return ForEach(Array(pts.enumerated()), id: \.offset) { _, pt in
            Circle().fill(.white).frame(width: 11, height: 11)
                .overlay(Circle().stroke(lineColor, lineWidth: 2))
                .position(x: CGFloat(pt.x) * side, y: CGFloat(1 - pt.y) * side)
        }
    }

    // MARK: - Tương tác

    private func dragGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if dragIndex == nil {
                    dragIndex = nearestOrInsert(at: v.startLocation, side: side)
                }
                if let i = dragIndex { movePoint(i, to: v.location, side: side) }
            }
            .onEnded { _ in dragIndex = nil; model.commitHistory() }
    }

    private func nearestOrInsert(at location: CGPoint, side: CGFloat) -> Int {
        var pts = model.graph.curves[channel]
        let nx = min(max(Double(location.x / side), 0), 1)
        let ny = min(max(Double(1 - location.y / side), 0), 1)
        // Điểm gần nhất trong ngưỡng.
        for (i, p) in pts.enumerated() {
            if abs(p.x - nx) < 0.05 && abs(p.y - ny) < 0.08 { return i }
        }
        // Thêm điểm mới, giữ thứ tự theo x.
        let newPoint = CurvePoint(x: nx, y: ny)
        var insertIndex = pts.count
        for (i, p) in pts.enumerated() where p.x > nx { insertIndex = i; break }
        pts.insert(newPoint, at: insertIndex)
        model.graph.curves[channel] = pts
        return insertIndex
    }

    private func movePoint(_ index: Int, to location: CGPoint, side: CGFloat) {
        var pts = model.graph.curves[channel]
        guard index < pts.count else { return }
        let ny = min(max(Double(1 - location.y / side), 0), 1)
        var nx = min(max(Double(location.x / side), 0), 1)

        if index == 0 {
            nx = 0
        } else if index == pts.count - 1 {
            nx = 1
        } else {
            let lower = pts[index - 1].x + 0.01
            let upper = pts[index + 1].x - 0.01
            nx = min(max(nx, lower), upper)
        }
        pts[index] = CurvePoint(x: nx, y: ny)
        model.graph.curves[channel] = pts
    }
}
